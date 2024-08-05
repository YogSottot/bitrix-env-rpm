# manage site
# have to return
#   document_root
#   mysql:      db, user, password
#   memcached:  host:port
#   searchd:    host:port
#   cluster:    ip_address|dns, ip_address|dns
#   bx_kernel:  0(link), 1(own)
#   bx_status:  0(disable), 1(enable)
# apache_config is usage for test bx_status
# dbconn is usage for getting mysql option
#
package bxSite;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use DBI;
use Output;
use Pool;
use bxDaemon;
use bxMysql;
use Sys::Hostname;
use bxSiteFiles;
use File::Temp;
use bxInventory qw( generate_password generate_tmp );


# basic path for site
has 'site_name',    is => 'ro', default => undef;
has 'site_dir',     is => 'ro', default => undef;
has 'site_options', is => 'rw', lazy    => 1, builder => 'get_site_options';

has 'dir_kernel',    is => 'ro', default => 'bitrix';
has 'file_dbconn',   is => 'ro', default => 'php_interface/dbconn.php';
has 'file_settings', is => 'ro', default => '.settings.php';
has 'apache',        is => 'ro', default => '/etc/httpd/bx/conf';
has 'conf',          is => 'ro', default => 'conf';
has 'pref',          is => 'ro', default => 'bx_ext_';
has 'debug',         is => 'ro', default => 0;
has 'logfile',       is => 'ro', default => '/opt/webdir/logs/bxSiteNew.debug';

our $MYSOCKET = '/var/lib/mysqld/mysqld.sock';

# parse nginx config, found certificate options (process includes too)
sub https_options_in_config {
    my ( $nginx_config, $ssl_info ) = @_;
    #print "\ndebug: $nginx_config\n";

    open( my $nh, '<', $nginx_config ) or return $ssl_info;

    my @nginx_includes;
    my $nginx_base = '/etc/nginx';

    while (<$nh>) {
        s/^\s+//;
        s/\s+$//;
        next if (/^$/);
        next if (/^#/);

        if (/^ssl_certificate\s+([^;]+);$/) {
            my $ssl_cert = $1;
            $ssl_cert =~ s/^['"]//;
            $ssl_cert =~ s/['"]$//;
            $ssl_info->{'HTTPSCert'} = $ssl_cert;
        }

        if (/^ssl_certificate_key\s+([^;]+);$/) {
            my $ssl_priv = $1;
            $ssl_priv =~ s/^['"]//;
            $ssl_priv =~ s/['"]$//;
            $ssl_info->{'HTTPSPriv'} = $ssl_priv;
        }

        if (/^ssl_trusted_certificate\s+([^;]+);$/) {
            my $ssl_trusted_certificate = $1;
            $ssl_trusted_certificate =~ s/^['"]//;
            $ssl_trusted_certificate =~ s/['"]$//;
            $ssl_info->{'HTTPSCertChain'} = $ssl_trusted_certificate;
        }

        if (/^ssl_protocols\s+/) {
            $ssl_info->{'HTTPSConf'} = $nginx_config;
        }

        if ($ssl_info->{'HTTPSCert'} =~ m|^/home/bitrix/dehydrated|){

            $ssl_info->{'HTTPSCertType'} = "letsencrypt";
        } elsif ( $ssl_info->{'HTTPSCert'} =~ m|^/etc/nginx/certs| ){

            $ssl_info->{'HTTPSCertType'} = "own";
        }else {

            $ssl_info->{'HTTPSCertType'} = "general";
        }

        if (/^include\s+([^;]+);$/) {
            my $include_file = $1;
            #print "include: $include_file\n";
            $include_file =~ s/^['"]//;
            $include_file =~ s/['"]$//;

            if ( $include_file !~ m:^/: ) {
                $include_file = catfile( $nginx_base, $include_file );
            }
            push @nginx_includes, $include_file;
        }
    }
    close $nh;
    my $include_size = @nginx_includes;
    if (
        (
            not defined $ssl_info->{'HTTPSConf'}
            or $ssl_info->{'HTTPSConf'} =~ /^$/
        )
        and $include_size > 0
      )
    {
        foreach my $include_file (@nginx_includes) {
            #print "  include: $include_file\n";
            $ssl_info = https_options_in_config( $include_file, $ssl_info );
            if ( defined $ssl_info->{'HTTPSConf'}
                && $ssl_info->{'HTTPSConf'} !~ /^$/ )
            {
                next;
            }
        }
    }

    return $ssl_info;
}

# get nginx options for site from main config
sub get_nginx_options {
    my $nginx_config = shift;

    my $nginx_options = { 
        CompositeNginx => 'disable', 
        proxy_ignore_client_abort => 'off', 
        nginx_custom_settings => 'off',
        nginx_bx_temp_files => 'off',
        nginx_bx_temp_config => '',
        nginx_custom_settings_directory => '',
    };

    if ( !-f $nginx_config ) { return $nginx_options; }

    open( my $nh, '<', $nginx_config )
      or return $nginx_options;
    while (<$nh>) {
        chomp;
        s/^\s+//;
        s/\s+$//;
        next if (/^$/);
        next if (/^#/);

        if (/^set\s+\$use_composite_cache\s+\"\"\s*\;$/) {
            $nginx_options->{'CompositeNginx'} = 'enable';
        }
        # proxy_ignore_client_abort on;
        if (/^proxy_ignore_client_abort\s+on;$/) {
            $nginx_options->{'proxy_ignore_client_abort'} = 'on';
        }
        # bx/site_settings/<SiteName>
        if (/^include\s+(bx\/site_settings\/[^\/]+)\/\*\.conf;$/) {
            my $sub_dir = $1;
            my $settings_dir = catfile('/etc/nginx/', $sub_dir);

            if (-d $settings_dir){
                $nginx_options->{'nginx_custom_settings'} = 'on';
                $nginx_options->{'nginx_custom_settings_directory'} = $settings_dir;
            }

            if ( -f catfile( $settings_dir, 'bx_temp.conf' ) ){
                $nginx_options->{nginx_bx_temp_files} = 'on';
                $nginx_options->{nginx_bx_temp_config} = catfile( $settings_dir, 'bx_temp.conf' );
            }

        }
 
    }

    close $nh;

    return $nginx_options;
}

# get map options for composite
# create option for site without composite
sub get_nginx_map_options {
    my $site_name = shift;

    my $nginx_options = {
        CompositeNginxID  => '',
        CompositeNginxMap => '',
    };

    my $nginx_maps_dir = '/etc/nginx/bx/maps';
    opendir( my $dh, $nginx_maps_dir )
      or return $nginx_options;

    my $new_id = 1;

    # try found ID and map config
    while ( my $f = readdir($dh) ) {
        next if ( $f =~ /^\.\.?$/ );
        next if ( -d catfile( $nginx_maps_dir, $f ) );

        # if found map file with id
        if ( $f =~ /^(\d+)\.cache_(\S+)\.conf$/ ) {
            my $found_id   = $1;
            my $found_cn   = sprintf "%d", $found_id;
            my $found_site = $2;

            # save id
            if ( $found_cn > $new_id ) { $new_id = $found_cn; }

            # test site name
            if ( $found_site eq $site_name ) {
                $nginx_options->{'CompositeNginxID'} = $found_id;
                $nginx_options->{'CompositeNginxMap'} =
                  catfile( $nginx_maps_dir, $f );
            }
        }
    }

    closedir $dh;

    # create ID if not exists
    if ( $nginx_options->{'CompositeNginxID'} =~ /^$/ ) {
        $nginx_options->{'CompositeNginxID'} = sprintf "%02d", $new_id + 1;
    }
    return $nginx_options;
}

# return DocumentRoot, ApacheConf, SiteName, PHP settings
sub apache_config_options {
    my $self = shift;

    my $site_name          = $self->site_name;
    my $apache_dir         = $self->apache;
    my $apache_ext         = $self->conf;
    my $apache_site_prefix = $self->pref;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );
    my $apache_options = {
        error           => 0,
        message         => '',
        ApacheConf      => '',
        ApacheConfScale => '',
        ApacheConfNTLM  => '',
        DocumentRoot    => '',
        ServerName      => '',
        SiteCharset     => 'utf-8',
        phpUploadDir    => '',
        phpSessionDir   => '',
        phpMsmtpAccount => 'default',
    };

    # external kernel variant
    if ( not defined $site_name ) {
        $apache_options->{error} = 1;
        return $apache_options;
    }

    $logOutput->log_data("$message_p: parse options for $site_name");

    my $apache_conf = catfile( $apache_dir, $site_name . '.' . $apache_ext );
    my $apache_conf_scale = catfile(
        "/etc/httpd/bx-scale/conf",
        $site_name . '.' . $apache_ext
    );

    my $apache_conf_ntlm = catfile(
        $apache_dir, 'ntlm_'. $site_name . '.' . $apache_ext
    );

    if ($site_name eq 'default'){
        $apache_conf_ntlm = catfile(
            $apache_dir, 'ntlm_'. hostname . '.' . $apache_ext
    );
 
    }
    if ( -f $apache_conf_ntlm ){
        $apache_options->{ApacheConfNTLM} = $apache_conf_ntlm;
    }

    if ( $site_name !~ /^default$/ ) {
        $apache_conf = catfile( $apache_dir,
            $apache_site_prefix . $site_name . '.' . $apache_ext );

        $apache_conf_scale = catfile(
            "/etc/httpd/bx-scale/conf",
            'ext_' . $site_name . '.' . $apache_ext
        );
    }

    $apache_options->{ApacheConfScale} = $apache_conf_scale;

    if ( !-f $apache_conf ) {
        $apache_options->{'error'} = 1;
        $apache_options->{'message'} =
          "$message_p: Not found $apache_conf for $site_name";
    }
    else {
        $apache_options->{'ApacheConf'} = $apache_conf;

        # get options from file
        open( my $ah, '<', $apache_conf )
          or die "Cannot open $apache_conf: $!";
        while ( my $line = <$ah> ) {
            next if ( $line =~ /^$/ );
            next if ( $line =~ /^#/ );
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;

            if ( $line =~ /^ServerName\s+(\S+)$/ ) {
                $apache_options->{'ServerName'} = $1;
            }
            if ( $line =~ /^DocumentRoot\s+(\S+)$/ ) {
                $apache_options->{'DocumentRoot'} = $1;
            }
            if ( $line =~ /^php_admin_value\s+session.save_path\s+(\S+)$/ ) {
                $apache_options->{'phpSessionDir'} = $1;
            }
            if ( $line =~ /^php_admin_value\s+upload_tmp_dir\s+(\S+)$/ ) {
                $apache_options->{'phpUploadDir'} = $1;
            }
#            if ( $line =~
#                /^php_admin_value\s+mbstring.internal_encoding\s+(\S+)$/ )
#            {
#                $apache_options->{'SiteCharset'} = 'windows-1251';
#            }
            if ( $line =~
                /^php_admin_value\s+sendmail_path\s+['"]msmtp([^'"]+)['"]$/ )
            {
                my $options = $1;
                if ( $options =~ /-a\s+(\S+)/ ) {
                    $apache_options->{'phpMsmtpAccount'} = $1;
                }
            }

            # alias id addional values, now we not use them, but who knows
            if ( $line =~ /^ServerAlias\s+(.+)$/ ) {
                my @server_aliases = split( /\s+/, $1 );
                my $sa_count = 0;
                foreach my $sa (@server_aliases) {
                    $sa_count++;
                    $apache_options->{ 'ServerAlias'
                          . sprintf( "%02d", $sa_count ) } = $sa;
                }
                $apache_options->{'ServerAliasesCount'} = $sa_count;
            }
        }
        close $ah;

        # ServerName is not defined in config file => use hostname
        if ( not defined $apache_options->{'ServerName'}
            or $apache_options->{'ServerName'} =~ /^$/ )
        {
            $apache_options->{'ServerName'} = hostname;
        }

        # default values for phpSessionDir and phpUploadDir
        if ( not defined $apache_options->{'phpSessionDir'} ) {
            $apache_options->{'phpSessionDir'} =
              ( $site_name =~ /^default$/ )
              ? "/tmp/php_sessions/www"
              : "/tmp/php_sessions/ext_www/$site_name";
        }

        if ( not defined $apache_options->{'phpUploadDir'} ) {
            $apache_options->{'phpSessionDir'} =
              ( $site_name =~ /^default$/ )
              ? "/tmp/php_upload/www"
              : "/tmp/php_upload/ext_www/$site_name";
        }
    }
    $logOutput->log_data( "$message_p: " . Dumper($apache_options) );

    return $apache_options;
}

# return 
# 0 - disabled
# 1 - enabled
sub getWebClusterStatus {
    my ($self) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $group_vars = "/etc/ansible/group_vars/bitrix-web.yml";
    if ( ! -f $group_vars ){
        return 0;
    }

    my $status = '';
    open(my $hv, "<", $group_vars)
        or return 0;
    while(<$hv>){
        chomp;
        s/^\s+//;
        s/\s+$//;
        next if (/^#/);
        next if (/^$/);

        if (/^cluster_web_configure:\s*(\S+)/){
            $status = $1;
        }
    }
    close $hv;

    if ($status eq "enable"){
        return 1;
    }
    return 0;
}



sub nginx_config_options {
    my $self      = shift;
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );
    my $site_name     = $self->site_name;
    my $nginx_options = {
        error             => 0,
        message           => '',
        NginxHTTPConfig   => '',
        NginxHTTPSConfig  => '',
        NginxHTTPDir      => '',    # site_avaliable
        NginxHTTPEDir     => '',    # site_enabled
        NginxType         => '',
        NginxPort         => '',
        SiteShort         => '',
        SiteCsync2        => '',
        HTTPSCert         => '',
        HTTPSPriv         => '',
        HTTPSConf         => '',
        HTTPSCertChain    => '',
        HTTPSCertType     => '',
        CompositeNginx    => '',
        CompositeNginxID  => '',
        CompositeNginxMap => '',
    };

    $logOutput->log_data("$message_p: estimate nginx options for $site_name");

    my $site_fancy = ( $site_name !~ /^default$/ ) ? $site_name : "s1";
    my $conf_https_nginx =
      ( $site_name =~ /^default$/ )
      ? "ssl." . $site_fancy
      : "bx_ext_ssl_" . $site_fancy;
    my $conf_http_nginx =
      ( $site_name =~ /^default$/ ) ? $site_fancy : "bx_ext_" . $site_fancy;

    # change https config for cluster case
    my $is_cluster_enabled = getWebClusterStatus();
    if ($is_cluster_enabled){   
         $conf_https_nginx = "https_balancer_" . $site_name;
    }
 
    $conf_http_nginx  .= '.conf';
    $conf_https_nginx .= '.conf';
    #print $site_name, "\n";

    $nginx_options->{'SiteShort'} = $site_name;
    $nginx_options->{'SiteShort'} =~ s/^([^\.]+)\..+$/$1/;
    $nginx_options->{'SiteCsync2'} = $site_name;
    $nginx_options->{'SiteCsync2'} =~ s/[\-\_\.]//g;
    $nginx_options->{'SiteCsync2'} =~ s/^[\d]+//;

    $nginx_options->{'NginxHTTPConfig'}  = $conf_http_nginx;
    $nginx_options->{'NginxHTTPSConfig'} = $conf_https_nginx;

    # cluster or single installations
    my @enable_nginx_dirs =
      ( '/etc/nginx/bx/site_enabled', '/etc/nginx/bx/site_ext_enabled' );
    my @cluster_nginx_dir = '/etc/nginx/bx/site_cluster';

    # search nginx config file in enable dirs
    foreach my $dir (@enable_nginx_dirs) {
        $logOutput->log_data(
            "$message_p: process $dir, search $conf_http_nginx");
        my $conf_http_nginx_fn = catfile( $dir, $conf_http_nginx );

        # test if file exists
        if ( -f $conf_http_nginx_fn ) {
            $logOutput->log_data("$message_p: found $conf_http_nginx_fn");
            $nginx_options->{'NginxHTTPDir'} = $dir;

            # get source file
            if ( -l $conf_http_nginx_fn ) {
                my $conf_http_nginx_link = readlink($conf_http_nginx_fn);
                $logOutput->log_data(
"$message_p: $conf_http_nginx_fn is link to $conf_http_nginx_link"
                );

                $nginx_options->{'NginxHTTPDir'} =
                  dirname($conf_http_nginx_link);
                $nginx_options->{'NginxHTTPEDir'} = $dir;
                $logOutput->log_data( "$message_p: set NginxHTTPDir to "
                      . $nginx_options->{'NginxHTTPDir'} );

                # test if cluster install exists
                if ( $nginx_options->{'NginxHTTPDir'} =~ m|/site_cluster$| ) {
                    $logOutput->log_data("$message_p: found cluster config");
                    $nginx_options->{'NginxType'} = 'cluster';
                    $nginx_options->{'NginxPort'} = 8080;

                }
                else {
                    $logOutput->log_data(
"$message_p: not found cluster config, set default options for site"
                    );
                    $nginx_options->{'NginxType'} = 'single';
                    $nginx_options->{'NginxPort'} = 80;
                }
            }
            else {
                $logOutput->log_data(
                    "$message_p: found ordinary file for site config");
                $nginx_options->{'NginxType'} = 'single';
                $nginx_options->{'NginxPort'} = 80;
            }
        }
    }

    # test options and return error is something not found
    if ( not defined $nginx_options->{'NginxHTTPDir'} ) {
        $nginx_options->{'error'} = 2;
        $nginx_options->{'message'} =
          "$message_p: not found nginx config file for $site_name";
    }

    #$logOutput->log_data("$message_p: ".Dumper($nginx_options));

    # get cerificate options
    if ( $nginx_options->{'NginxType'} =~ /^cluster$/ ) {
        my $nginx_https_fn = catfile('/etc/nginx/bx/site_enabled', $conf_https_nginx);
        $nginx_options =
          https_options_in_config( $nginx_https_fn, $nginx_options );
        if (-l $nginx_https_fn ){
            $nginx_options->{'NginxHTTPSFullPath'} = readlink $nginx_https_fn;
        } else {
            $nginx_options->{'NginxHTTPSFullPath'} = $nginx_https_fn;
        }
    }
    else {
        my $nginx_https_fn = catfile(
            $nginx_options->{'NginxHTTPDir'},
            $nginx_options->{'NginxHTTPSConfig'}
        );
        if (-l $nginx_https_fn ){
            $nginx_options->{'NginxHTTPSFullPath'} = readlink $nginx_https_fn;
        } else {
            $nginx_options->{'NginxHTTPSFullPath'} = $nginx_https_fn;
        }
        $nginx_options =
          https_options_in_config( $nginx_https_fn, $nginx_options );
    }

    # get options from primary nginx config
    # CompositeNginx - enable or not
    my $get_nginx_options = get_nginx_options(
        catfile(
            $nginx_options->{'NginxHTTPDir'},
            $nginx_options->{'NginxHTTPConfig'}
        )
    );
    foreach ( keys %$get_nginx_options ) {
        $nginx_options->{$_} = $get_nginx_options->{$_};
    }

    # Search site personal setting (map file) and id internal variable
    my $get_nginx_map_options = get_nginx_map_options($site_name);
    foreach ( keys %$get_nginx_map_options ) {
        $nginx_options->{$_} = $get_nginx_map_options->{$_};
    }

    return $nginx_options;
}

sub bx_https_options {
    my ( $self, $site_root ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_name = $self->site_name;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data(
        "$message_p: try defined https options for site $site_name");

    my $ssl_info = { HTTPS => 'disable', };

    my $site_ssl_switcher = catfile( $site_root, '.htsecure' );
    if ( -f $site_ssl_switcher ) {
        $ssl_info->{'HTTPS'} = 'enable';
    }

    return $ssl_info;
}

sub bx_email_options {
    my ( $self, $msmtprc_account ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_name = $self->site_name;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data(
        "$message_p: try defined email options for site $site_name");

    my $msmtp_info = {
        EmailAddress => undef,
        EmailAccount => undef,
        SMTPHost     => undef,
        SMTPPort     => undef,
        SMTPTLS      => "off",
        SMTPUser     => undef,
        SMTPPassword => undef,
    };

    my $msmtp_conf = "/home/bitrix/.msmtprc";
    my $bxenv_conf = "/etc/php.d/bitrixenv.ini";

    if ( !-f $msmtp_conf ) {
        return $msmtp_info;
    }

    open( my $mh, '<', $msmtp_conf )
      or return $msmtp_info;
    my $account = '';

    while ( my $line = <$mh> ) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if ( $line =~ /^#/ );
        next if ( $line =~ /^$/ );

        if ( $line =~ /^account\s+(\S+)$/ ) {
            $account = $1;
        }

        if ( $account =~ /^$msmtprc_account$/ ) {
            $msmtp_info->{'EmailAccount'} = $account;

            if ( $line =~ /^from\s+(\S+)$/ ) {
                $msmtp_info->{'EmailAddress'} = $1;
            }

            if ( $line =~ /^host\s+(\S+)$/ ) {
                $msmtp_info->{'SMTPHost'} = $1;
            }
            if ( $line =~ /^port\s+(\S+)$/ ) {
                $msmtp_info->{'SMTPPort'} = $1;
            }
            if ( $line =~ /^user\s+(\S+)$/ ) {
                $msmtp_info->{'SMTPUser'} = $1;
            }
            if ( $line =~ /^password\s+(\S+)$/ ) {
                $msmtp_info->{'SMTPPassword'} = $1;
            }
            if ( $line =~ /^password\s*$/ ){
                $msmtp_info->{'SMTPPassword'} = "";
            }
            if ( $line =~ /^tls\s+(\S+)$/ ) {
                $msmtp_info->{'SMTPTLS'} = $1;
            }
        }
    }

    close $mh;

    return $msmtp_info;

}

sub get_site_options {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_name = $self->site_name;
    my $site_dir  = $self->site_dir;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );

    my $site_options = {
        "error"                      => 0,
        "message"                    => '',
        "SiteName"                   => $site_name,
        "ApacheConf"                 => '',
        "BackupCronFile"             => '',
        "BackupDay"                  => '',
        "BackupFolder"               => '',
        "BackupHour"                 => '',
        "BackupMinute"               => '',
        "BackupMonth"                => '',
        "BackupTask"                 => '',
        "BackupVersion"              => '',
        "BackupWeekDay"              => '',
        "CronFile"                   => '',
        "CronTask"                   => '',
        "DBHost"                     => '',
        "DBLogin"                    => '',
        "DBName"                     => '',
        "DBPassword"                 => '',
        "DBType"                     => '',
        "DBConn"                     => '',
        "DocumentRoot"               => '',
        "EmailAccount"               => undef,
        "EmailAddress"               => undef,
        "HTTPS"                      => '',
        "HTTPSCert"                  => '',
        "HTTPSConf"                  => '',
        "HTTPSPriv"                  => '',
        'HTTPSCertChain'             => '',
        'HTTPSCertType'              => '',
        "NginxHTTPConfig"            => '',
        "NginxHTTPDir"               => '',
        "NginxHTTPSConfig"           => '',
        "NginxPort"                  => '',
        "NginxType"                  => '',
        "SMTPHost"                   => undef,
        "SMTPPassword"               => undef,
        "SMTPPort"                   => undef,
        "SMTPTLS"                    => 'off',
        "SMTPUser"                   => undef,
        "ServerName"                 => '',
        "SiteCharset"                => '',
        "SiteInstall"                => '',
        "SiteShort"                  => '',
        "SiteCsync2"                 => '',
        "SiteStatus"                 => '',
        "SphinxConnection"           => '',
        "SphinxIndexName"            => '',
        "phpSessionDir"              => '',
        "phpUploadDir"               => '',
        "phpMsmtpAccount"            => '',
        "ModuleCluster"              => '',
        "ModuleScale"                => '',
        "NTLM_use_ntlm"              => 'N',
        "NTLM_bitrixvm_auth_support" => 'N',
        "SiteKernelDir"              => '',
        "SiteKernelDB"               => '',
        CompositeStatus              => 'disable',
        CompositeStorage             => '',
        CompositeDomains             => [],
        CompositeExcludeUri          => [],
        CompositeIncludeUri          => [],
        CompositeExcludeParams       => [],
        CompositeMemcachedHost       => '',
        CompositeMemcachedPort       => '',
        CompositeNginx               => 'disable',
    };

    ### apache options for site
    my $apache_options = $self->apache_config_options();
    foreach my $apache_k ( keys %$apache_options ) {
        $site_options->{$apache_k} = $apache_options->{$apache_k};
    }

    # if error return found information with error
    if ( $apache_options->{'error'} ) {

        # external kernel doesn't contain web configs
        if ( not defined $site_dir ) {
            $site_options->{'SiteStatus'} = 'error';
            return $site_options;
        }
        else {
            my $bxSiteFiles = bxSiteFiles->new(
                site_dir  => $site_dir,
                site_conf => 'not_found'
            );

            my $bxSiteFilesOptions = $bxSiteFiles->site_files_options;
            $bxSiteFilesOptions->{'SiteName'} = "ext_" . basename($site_dir);
            $bxSiteFilesOptions->{'SiteShort'} =
              $bxSiteFilesOptions->{'SiteName'};
            $bxSiteFilesOptions->{'SiteCsync2'} =
              $bxSiteFilesOptions->{'SiteName'};
            foreach my $fo ( keys %$bxSiteFilesOptions ) {
                $site_options->{$fo} = $bxSiteFilesOptions->{$fo};
            }
            return $site_options;
        }
    }

    ### nginx options for site
    my $nginx_options = $self->nginx_config_options();
    foreach my $nginx_k ( keys %$nginx_options ) {
        $site_options->{$nginx_k} = $nginx_options->{$nginx_k};
    }

    # if error return found information with error
    if ( $nginx_options->{'error'} ) {
        $site_options->{'SiteStatus'} = 'error';
        return $site_options;
    }

    #print Dumper($nginx_options);

    ### folder and config options
    my $bxSiteFiles = bxSiteFiles->new(
        site_dir  => $site_options->{'DocumentRoot'},
        site_conf => 'found'
    );

    my $bxSiteFilesOptions = $bxSiteFiles->site_files_options;
    foreach my $fo ( keys %$bxSiteFilesOptions ) {
        $site_options->{$fo} = $bxSiteFilesOptions->{$fo};
    }
    if ( $bxSiteFilesOptions->{'error'} ) {
        return $site_options;
    }

    #print "SiteFiles: ",Dumper($bxSiteFilesOptions);

    ### email options
    if ( $site_options->{'phpMsmtpAccount'} !~ /^$/ ) {
        my $bx_email_options =
          $self->bx_email_options( $site_options->{'phpMsmtpAccount'}, );
        foreach my $email_k ( keys %$bx_email_options ) {
            $site_options->{$email_k} = $bx_email_options->{$email_k};
        }
    }

    ### cron settings
    if ( $site_options->{'SiteInstall'} !~ /^ext_kernel$/ ) {
        ### https settings on site
        my $bx_https_options = $self->bx_https_options(
            $site_options->{'DocumentRoot'},
            $site_options->{'NginxType'},
        );
        foreach my $ssl_k ( keys %$bx_https_options ) {
            $site_options->{$ssl_k} = $bx_https_options->{$ssl_k};
        }
    }
    return $site_options;
}

# generate my.cnf file  with connection options for the site or password file for ansible lookups
sub my_connect {
    my ( $self, $type, $tmpdir ) = @_;
    $type = "password_file" if ( not defined $type );

    my $site_name = $self->site_name;
    my $site_dir  = $self->site_dir;
    if ( ( not defined $site_name ) && ( not defined $site_dir ) ) {
        return Output->new(
            error => 1,
            message =>
              "For site status you must defined site_name or document root",
        );
    }

    if ( $type !~ /^(password_file|my_cnf)$/ ) {
        return Output->new(
            error => 1,
            message =>
              "Unknown type=$type; Supported types: password_file and my_cnf",
        );
    }
    my $so = $self->site_options;
    if ( not defined $site_name ) {
        $site_name = "ext_" . basename($site_dir);
    }

    # generate tmp file
    my $tmp_file = generate_tmp( $type, $tmpdir );

    open( my $h, '>', $tmp_file )
      or return Output->new(
        error   => 1,
        message => "Cannot open temporary file=$tmp_file"
      );

    if ( $type eq "password_file" ) {
        print $h $so->{DBPassword};
        $so->{DBPasswordFile} = $tmp_file;
    }
    elsif ( $type eq "my_cnf" ) {

        # generate my.cnf file
        print $h "# bitrix management console config file\n";
        print $h "# site=" . $so->{SiteName} . "\n";
        print $h "[client]\n";
        if ( $so->{DBHost} =~ /^(localhost|127\.0\.0\.1)$/ ) {
            print $h "socket=$MYSOCKET\n";
        }
        else {
            print $h "host=" . $so->{DBHost} . "\n";
        }
        print $h "user=" . $so->{DBLogin} . "\n";

        # my.cnf parsing allows quoting only \, ' or "
        # we need quoted ' char only
        my $my_escaped_password = $so->{DBPassword};
        if ( $my_escaped_password =~ /'/ ) {
            $my_escaped_password =~ s/'/\\'/;
        }
        print $h "password='$my_escaped_password'\n";

        $so->{DBMyCnf} = $tmp_file;
    }
    close $h;

    my $message_t = __PACKAGE__;
    return Output->new(
        error => 0,
        data  => [ $message_t, { $site_name => $so } ],
    );
}

sub statusSite {
    my $self = shift;

    my $site_name = $self->site_name;
    my $site_dir  = $self->site_dir;
    if ( ( not defined $site_name ) && ( not defined $site_dir ) ) {
        return Output->new(
            error => 1,
            message =>
              "For site status you must defined site_name or document root",
        );
    }
    my $site_options = $self->site_options;
    if ( not defined $site_name ) {
        $site_name = "ext_" . basename($site_dir);
    }

    my $message_t = __PACKAGE__;

    return Output->new(
        error => 0,
        data  => [ $message_t, { $site_name => $site_options } ],
    );
}

sub statusUpdateSite {
    my $self = shift;

    my $site_name = $self->site_name;
    my $site_dir  = $self->site_dir;
    if ( not defined $site_name ) { $site_name = "ext_" . basename($site_dir); }
    my $site_options = $self->get_site_options;

    my $message_t = __PACKAGE__;

    return Output->new(
        error => 0,
        data  => [ $message_t, { $site_name => $site_options } ],
    );
}

# add or update php values in apache config file
sub replace2apache {
    my ( $self, $site_values ) = @_;

    #print $site_conf," =>",Dumper($site_values);
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $site_status = $self->site_options->{'SiteStatus'};
    my $site_name   = $self->site_name;

    if ( $site_status =~ /^error$/ ) {
        my $site_error = $self->site_options->{'error'};
        if ( $site_error != 5 ) {
            return Output->new(
                error   => 1,
                message => "Site $site_name status=$site_status"
                  . " not allow manage apache settings for it",
            );
        }
    }

    my $apache_conf = $self->site_options->{'ApacheConf'};
    my $apache_temp = $apache_conf . '.temp';

    $logOutput->log_data("$message_p: start update $apache_conf: $!");

    # create work hash with values and statuses
    my ( %php_values, %php_deleted, $php_deleted, $php_values );
    $php_values = $php_deleted = 0;
    foreach my $key ( sort keys %$site_values ) {
        if ( defined $site_values->{$key} ) {
            $php_values{$key} = [ $site_values->{$key}, 0 ];
            $php_values++;
        }
        else {
            $php_deleted{$key} = 0;
            $php_deleted++;
        }
    }

    my $site_root = "";
    my $proc_dir  = undef;
    open( my $sc, '<', $apache_conf )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $apache_conf: $!",
      );

    open( my $st, '>', $apache_temp )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $apache_temp: $!",
      );

    # create new values in tmp file
    while (<$sc>) {
        s/\s+$//;
        my $line = $_;

        if ( $line =~ /^\s*DocumentRoot\s+(\S+)$/ ) {
            $site_root = $1;

            #print "DocumentRoot: $site_root\n";
        }

        if ( $line =~ /^\s*\<Directory\s+([^\>]+)\>$/ ) {
            $proc_dir = $1;

            #print "Process directory: $proc_dir\n";
        }

        # update existen options
        if ( defined $proc_dir && $proc_dir =~ /^$site_root$/ ) {

            # found php value
            if ( $line =~ /^\s*php_admin_value\s+(\S+)\s+(.+)$/ ) {
                my $php_key = $1;
                my $php_val = $2;

                #print " Found key=$php_key val=$php_val\n";
                if ( grep /^$php_key$/, keys %php_values ) {
                    $logOutput->log_data(
                        "$message_p: update $php_key from $php_val to "
                          . $php_values{$php_key}->[0] );

                    #print " Replace key=$php_key\n";
                    $line =~
                      s/$php_key\s+(.+)$/$php_key "$php_values{$php_key}->[0]"/;
                    $php_values{$php_key}->[1] = 1;
                }
                if ( grep /^$php_key$/, keys %php_deleted ) {
                    $logOutput->log_data(
                        "$message_p: delete $php_key in the apache config "
                          . $apache_conf );

                    $line =~ s/$php_key\s+(.+)$/#$php_key $1/;
                    $php_deleted{$php_key} = 1;
                }
            }

            # close directory part and add options that not in the file
            if ( $line =~ /^\s*\<\/Directory\>$/ ) {
                if ( $proc_dir =~ /^$site_root$/ ) {

                    #print "Finish processing: $proc_dir\n\n";
                    foreach my $php_key ( keys %php_values ) {

                        #print "$php_key: ",$php_values{$php_key}->[1],"\n";
                        if ( $php_values{$php_key}->[1] == 0 ) {
                            $logOutput->log_data(
                                "$message_p: create $php_key set it to "
                                  . $php_values{$php_key}->[0] );

                            print $st
qq(    php_admin_value $php_key "$php_values{$php_key}->[0]"\n);
                            $php_values{$php_key}->[1] = 1;
                        }
                    }
                }
                $proc_dir = undef;
            }
        }

        print $st $line, "\n";

    }

    close $sc;
    close $st;

    # create backup config
    $logOutput->log_data(
"$message_t: create backup for $apache_conf and replace it by new values"
    );
    rename $apache_conf, $apache_conf . ".bak";
    rename $apache_temp, $apache_conf;

    # restart httpd
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $cmd_opts = { 'manage_web' => 'restart_web' };

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process =
      $dh->startAnsibleProcess( 'restart_web_services', $cmd_opts );
    return Output->new(
        error => 0,
        data  => [ $message_p, $apache_conf ]
    );
}

# disable email account in config file
sub del2msmtp {
    my $site_name  = shift;
    my $msmtp_conf = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $msmtp_temp = $msmtp_conf . ".temp";

    open( my $mc, $msmtp_conf )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $msmtp_temp: $!",
      );

    open( my $mt, ">" . $msmtp_temp )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $msmtp_temp: $!",
      );

    # comment data for site_name
    my $account = "";
    while (<$mc>) {
        s/^\s+//;
        s/\s+$//;
        next if (/^$/);
        my $line = $_;

        # account alice
        if (/^account\s+(\S+)$/) {
            $account = $1;
        }

        if ( $account =~ /^$site_name$/ ) {
            $line = "#" . $line;
        }

        print $mt $line, "\n";
    }
    close $mt;
    close $mc;

    # delete file with old data
    unlink $msmtp_conf;
    rename $msmtp_temp, $msmtp_conf;

    # change access rights
    chmod 0600, $msmtp_conf;
    my $uid = getpwnam 'bitrix';
    my $gid = getgrnam 'bitrix';
    chown $uid, $gid, $msmtp_conf;

    return Output->new(
        error => 0,
        data  => [ $message_p, $msmtp_conf ]
    );
}

# create account data for site
sub add2msmtp {
    my $site_name           = shift;
    my $site_email_settings = shift;
    my $msmtp_conf          = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    open( my $mh, ">>" . $msmtp_conf )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $msmtp_conf: $!",
      );

    if (not defined $site_email_settings->{'SMTPPassword'}){
        if (defined $site_email_settings->{'SMTPPasswordFile'}){
            open(my $fh, '<', $site_email_settings->{'SMTPPasswordFile'})
                or return Output->new(
                error => 1,
                message => "$message_p: Cannot open ". $site_email_settings->{'SMTPPasswordFile'},
            );

            $site_email_settings->{'SMTPPassword'} = <$fh>;
            close $fh;
            unlink $site_email_settings->{'SMTPPasswordFile'};
        }
    }

    # basic settings
    my $msmtp_info = qq(
\# smtp account configuration for $site_name
account $site_name
logfile /home/bitrix/msmtp_$site_name.log
host $site_email_settings->{'SMTPHost'}
port $site_email_settings->{'SMTPPort'}
from $site_email_settings->{'EmailAddress'}
aliases /etc/aliases
keepbcc off);


    # auth settings
    if ( defined $site_email_settings->{'SMTPUser'} ) {
        my $smtp_auth = 'on';
        if (   ( defined $site_email_settings->{'SMTPAuth'} )
            && ( $site_email_settings->{'SMTPAuth'} !~ /^(auto|on)$/ ) )
        {
            $smtp_auth = $site_email_settings->{'SMTPAuth'};
        }
        my $pass = ($site_email_settings->{'SMTPPassword'})? 
            $site_email_settings->{'SMTPPassword'}: 
            "";
        $msmtp_info = $msmtp_info . qq(
auth $smtp_auth
user $site_email_settings->{'SMTPUser'}
password $pass);
    }
    else {
        $msmtp_info = $msmtp_info . qq(
auth off);
    }

    # tls settings
    if ( defined $site_email_settings->{'SMTPTLS'}
        && $site_email_settings->{'SMTPTLS'} =~ /^(on|yes)$/i )
    {
        $msmtp_info = $msmtp_info . qq(
tls on
tls_certcheck off);
        if ( $site_email_settings->{'EmailAddress'} =~ /yandex\.ru/ ) {
            $msmtp_info = $msmtp_info . qq(
tls_starttls on
      );
        }
    }

    # save info and change access rights
    print $mh $msmtp_info, "\n";
    close $mh;
    chmod 0600, $msmtp_conf;
    my $uid = getpwnam 'bitrix';
    my $gid = getgrnam 'bitrix';
    chown $uid, $gid, $msmtp_conf;

    return Output->new(
        error => 0,
        data  => [ $message_p, $msmtp_conf ]
    );
}

# delete email options for site
sub deleteEmailForSite {
    my ($self) = @_;

    my $site_name = $self->site_name;
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data("$message_p: delete email settings for $site_name");

    # update personal apache config fo site
    my $apache_conf   = $self->site_options->{'ApacheConf'};
    my %msmtp_options = ( 'sendmail_path' => undef );
    my $update_apache = $self->replace2apache( \%msmtp_options );
    if ( $update_apache->is_error ) { return $update_apache; }

    # delete site info in msmtp config
    my $msmtp_conf   = "/home/bitrix/.msmtprc";
    my $msmtp_update = undef;

    # if file exists => delete old site's data
    if ( -f $msmtp_conf ) {
        $msmtp_update = del2msmtp( $site_name, $msmtp_conf );
        if ( $msmtp_update->is_error ) { return $msmtp_update }
    }

    return $self->statusUpdateSite();
}

# update or create email settings
sub createEmailForSite {
    my $self                = shift;
    my $site_email_settings = shift;

    my $site_name = $self->site_name;
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data("$message_p: update email settings for $site_name");

    my $site_status = $self->site_options->{'SiteStatus'};
    if ( $site_status =~ /^error$/ ) {
        my $site_error = $self->site_options->{'error'};
        if ( $site_error != 5 ) {
            return Output->new(
                error => 1,
                message =>
"Site $site_name status=$site_status, not allow create email for it",
            );
        }
    }

    my $msmtp_conf = "/home/bitrix/.msmtprc";

    # create config for msmtp agent
    my $msmtp_update = undef;

    # if file exists => delete old site's data
    if ( -f $msmtp_conf ) {
        $msmtp_update = del2msmtp( $site_name, $msmtp_conf );
        if ( $msmtp_update->is_error ) { return $msmtp_update }
    }

    # adding new data to file
    $msmtp_update = add2msmtp( $site_name, $site_email_settings, $msmtp_conf );
    if ( $msmtp_update->is_error ) { return $msmtp_update }

    # update personal apache config fo site
    my $apache_conf = $self->site_options->{'ApacheConf'};
    my %msmtp_options = ( 'sendmail_path' => 'msmtp -t -i' );
    if ( $site_name !~ /^default$/ ) {
        $msmtp_options{'sendmail_path'} = qq(msmtp -t -i -a $site_name);
        my $update_apache = $self->replace2apache( \%msmtp_options );
        if ( $update_apache->is_error ) { return $update_apache; }
    }

    # create link for cron tasks
    my $msmtp_system_conf = "/etc/msmtprc";
    if ( ( !-f $msmtp_system_conf ) && ( !-l $msmtp_system_conf ) ) {
        symlink $msmtp_conf, $msmtp_system_conf;
    }

    # update cron if it configured
    if (   ( defined $self->site_options->{'CronTask'} )
        && ( $self->site_options->{'CronTask'} =~ /^enable$/ ) )
    {
        $self->addEmail2Cron();
    }

    return $self->statusUpdateSite();
}

# disable cron for internal sites tasks
sub disableCronForSite {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $site_dir     = $self->site_dir;
    my $site_name    = $self->site_name;
    my $site_options = $self->site_options;
    my $site_status  = $site_options->{'SiteStatus'};

    if ( ( $site_status =~ /^error$/ ) && ( $site_options->{'error'} < 4 ) ) {
        return Output->new(
            error => 1,
            message =>
"$message_p: Site status=$site_status, not allow manage cron for it",
        );
    }

    my $cron_task = $self->site_options->{'CronTask'};
    if ( $cron_task =~ /^disable$/ ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Cron is already disabled ",
        );
    }

    my $cron_task_tool = catfile( $site_options->{'DocumentRoot'},
        'bitrix/modules/main/tools/cron_events.php' );
    my $site_crontab = $self->site_options->{'CronFile'};

    $logOutput->log_data("$message_p: update data in $site_crontab");

    my $cron_temp = catfile( "/tmp", basename($site_crontab) );

    my $cron_replace = 0;
    open( my $cth, '>', $cron_temp )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $cron_temp: $!",
      );

    open( my $cfh, '<', $site_crontab )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $site_crontab: $!",
      );

    while (<$cfh>) {
        s/^\s+//;
        s/\s+$//;
        my $line = $_;
        if ( $line !~ /^#/ && $line =~ m:$cron_task_tool: ) {
            $logOutput->log_data("$message_p: found $cron_task_tool");

            $line = "#" . $line;
            $cron_replace++;
        }
        print $cth $line, "\n";
    }
    close $cfh;
    close $cth;

    if ( $cron_replace > 0 ) {
        $logOutput->log_data(
            "$message_p: replace $site_crontab by new version");

        unlink $site_crontab;
        rename $cron_temp, $site_crontab;
        chmod 0644, $site_crontab;
    }
    else {
        unlink $cron_temp;
    }

    return $self->statusUpdateSite();
}

# add email to cron task
sub addEmail2Cron {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $site_dir     = $self->site_dir;
    my $site_name    = $self->site_name;
    my $site_options = $self->site_options;
    my $site_status  = $site_options->{'SiteStatus'};
    my $cron_task    = $self->site_options->{'CronTask'};

    if ( not defined $site_dir ) {
        $site_dir = $site_options->{'DocumentRoot'};
    }
    if ( not defined $site_name ) { $site_name = "ext_" . basename($site_dir); }
    my $site_cron_path =
      ( $site_options->{'SiteInstall'} =~ /^link$/ )
      ? $site_options->{'SiteKernelDir'}
      : $site_dir;

    my $site_mstmtp_str = qq(-d sendmail_path="msmtp -t -i -a $site_name");

    my $cron_task_tool =
      catfile( $site_cron_path, 'bitrix/modules/main/tools/cron_events.php' );
    my $site_crontab =
      catfile( '/etc/cron.d', 'bx_' . $self->site_options->{'DBName'} );

    if ( $cron_task =~ /^enable$/ ) {
        my $cron_file     = $self->site_options->{'CronFile'};
        my $cron_file_bak = $cron_file . ".bak";

        open( my $cf, '<', $cron_file )
          or return Output->new(
            error   => 1,
            message => "$message_p: Cannot open $cron_file: $!",
          );

        open( my $cfb, '>', $cron_file_bak )
          or return Output->new(
            error   => 1,
            message => "$message_p: Cannot open $cron_file_bak: $!",
          );

        my $found = 0;
        while ( my $line = <$cf> ) {
            chomp $line;
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;

            if ( ( $line !~ /^#/ ) && ( $line =~ m:$cron_task_tool: ) ) {
                $line =
qq(* * * * * bitrix test -f $cron_task_tool && { /usr/bin/php $site_mstmtp_str -f $cron_task_tool; } >/dev/null 2>&1\n);
                $found = 1;
            }
            print $cfb $line, "\n";
        }

        close $cf;
        if ( $found == 0 ) {
            print $cfb "#\n# cron tasks for site $site_dir db=";
            print $cfb $self->site_options->{'DBName'};
            print $cfb "\n#\n";
            print $cfb
qq(* * * * * bitrix test -f $cron_task_tool && { /usr/bin/php $site_mstmtp_str -f $cron_task_tool; } >/dev/null 2>&1\n);
        }
        close $cfb;

        unlink $cron_file;
        rename $cron_file_bak, $cron_file;

    }
    else {

        open( my $sch, '>>', $site_crontab )
          or return Output->new(
            error   => 1,
            message => "$message_p: Cannot open $site_crontab: $!",
          );

        print $sch "#\n# cron tasks for site $site_dir db=";
        print $sch $self->site_options->{'DBName'};
        print $sch "\n#\n";
        print $sch
qq(* * * * * bitrix test -f $cron_task_tool && { /usr/bin/php $site_mstmtp_str -f $cron_task_tool; } >/dev/null 2>&1\n);
        close $sch;
    }

    return $self->statusUpdateSite();

}

# enable cron for internal sites tasks
sub enableCronForSite {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $site_dir     = $self->site_dir;
    my $site_name    = $self->site_name;
    my $site_options = $self->site_options;
    my $site_status  = $site_options->{'SiteStatus'};
    if ( ( $site_status =~ /^error$/ ) && ( $site_options->{'error'} < 4 ) ) {
        return Output->new(
            error => 1,
            message =>
"$message_p: Site status=$site_status, not allow manage cron for it",
        );
    }

    my $cron_task = $self->site_options->{'CronTask'};
    if ( $cron_task =~ /^enable$/ ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Cron record already enabled in "
              . $self->site_options->{'CronFile'},
        );
    }

    if ( not defined $site_dir ) {
        $site_dir = $site_options->{'DocumentRoot'};
    }
    if ( not defined $site_name ) { $site_name = "ext_" . basename($site_dir); }
    my $site_mstmtp_str =
      (      ( defined $site_options->{'SMTPHost'} )
          && ( $site_options->{'SMTPHost'} !~ /^$/ ) )
      ? qq(-d sendmail_path="msmtp -t -i -a $site_name")
      : "";

    #print "site_name=$site_name site_dir=$site_dir\n";

    $logOutput->log_data("$message_p: enable cron settings for $site_dir");

    my $cron_task_tool =
      catfile( $site_dir, 'bitrix/modules/main/tools/cron_events.php' );
    my $site_crontab =
      catfile( '/etc/cron.d', 'bx_' . $self->site_options->{'DBName'} );

    open( my $sch, '>>', $site_crontab )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $site_crontab: $!",
      );
    print $sch "#\n# cron tasks for site $site_dir db=";
    print $sch $self->site_options->{'DBName'};
    print $sch "\n#\n";
    print $sch
qq(* * * * * bitrix test -f $cron_task_tool && { /usr/bin/php $site_mstmtp_str -f $cron_task_tool; } >/dev/null 2>&1\n);
    close $sch;

    return $self->statusUpdateSite();
}

# disable SSL for site
sub disableSSLForSite {
    my $self = shift;

    my $site_name = $self->site_name;
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data(
        "$message_p: disable SSL-ONLY settings for $site_name");

    my $site_status = $self->site_options->{'SiteStatus'};
    if ( $site_status =~ /^error$/ ) {
        my $site_error = $self->site_options->{'error'};
        if ( $site_error != 5 ) {
            return Output->new(
                error => 1,
                message =>
"Site $site_name status=$site_status, not allow manage ssl settings for it",
            );
        }
    }

    my $https_status = $self->site_options->{'HTTPS'};
    if ( $https_status =~ /^disable$/ ) {
        return Output->new(
            error   => 1,
            message => "HTTPS-only mode already disabled for $site_name",
        );
    }

    my $site_root = $self->site_options->{'DocumentRoot'};
    my $site_ssl_switcher = catfile( $site_root, '.htsecure' );

    $logOutput->log_data("$message_p: unlink $site_ssl_switcher");
    unlink $site_ssl_switcher;

    # restart nginx
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $cmd_opts = { 'manage_web' => 'restart_web' };

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process =
      $dh->startAnsibleProcess( 'restart_web_services', $cmd_opts );

    return $self->statusUpdateSite();
}

# enable SSL-ONLY for site
sub enableSSLForSite {
    my $self = shift;

    my $site_name = $self->site_name;
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data("$message_p: enable SSL-ONLY settings for $site_name");

    my $site_status = $self->site_options->{'SiteStatus'};
    if ( $site_status =~ /^error$/ ) {
        my $site_error = $self->site_options->{'error'};
        if ( $site_error != 5 ) {
            return Output->new(
                error => 1,
                message =>
"Site $site_name status=$site_status, not allow manage ssl settings for it",
            );
        }
    }

    my $https_status = $self->site_options->{'HTTPS'};
    if ( $https_status =~ /^enable$/ ) {
        return Output->new(
            error   => 1,
            message => "HTTPS-only mode already enabled for $site_name",
        );
    }

    my $site_root = $self->site_options->{'DocumentRoot'};
    my $site_ssl_switcher = catfile( $site_root, '.htsecure' );

    open( my $sss, '>', $site_ssl_switcher )
      or return Output->new(
        error   => 1,
        message => "$message_p: Can't create $site_ssl_switcher: $!"
      );
    close $sss;

    # set rights to .htsecure file
    my $uid = getpwnam 'bitrix';
    my $gid = getgrnam 'bitrix';
    chown $uid, $gid, $site_ssl_switcher;

    $logOutput->log_data("$message_p: created $site_ssl_switcher");

    # restart nginx
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $cmd_opts = { "manage_web" => "restart_web" };

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process =
      $dh->startAnsibleProcess( 'restart_web_services', $cmd_opts );

    return $self->statusUpdateSite();
}

# enable cron for site services
sub enableCronService {
    my ( $self, $service ) = @_;

    my $site_name    = $self->site_name;
    my $site_dir     = $self->site_dir;
    my $site_options = $self->site_options;
    my $site_status  = $site_options->{'SiteStatus'};

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if ( not defined $service ) {
        return Output->new(
            error   => 1,
            message => "$message_p: You must defined service name"
        );
    }

    if ( ( $site_status =~ /^error$/ ) && ( $site_options->{'error'} < 4 ) ) {
        return Output->new(
            error => 1,
            message =>
"$message_p: Site status=$site_status, not allow manage cron for it",
        );
    }
    my $site_root = $site_options->{'DocumentRoot'};

    $logOutput->log_data(
        "$message_p: enable start service $service for site in $site_root");

    if ( $service !~ /^(xmppd|smtpd)$/ ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Service $service is not supported",
        );
    }

    my $cron_services = $self->site_options->{'CronService'};
    if ( defined $cron_services->{$service} ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Service $service already enabled in "
              . $cron_services->{$service}->{'cron'}
        );
    }

    my $service_script = '/opt/webdir/bin/bx_cron_services.sh';
    my $site_db        = $site_options->{'DBName'};
    my $site_crontab   = catfile( '/etc/cron.d', 'bx_' . $site_db );

    open( my $sh, '>>', $site_crontab )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $site_crontab: $!",
      );

    print $sh
      qq(#\n#auto start service=$service tasks for site in $site_root\n#\n);
    print $sh qq(*/5 * * * * root $service_script $service $site_root\n\n);

    close $sh;

    return Output->new(
        error => 0,
        message =>
"$message_t: Add task for service $service to $site_crontab for site in  $site_root"
    );
}

# disable cron for site services
sub disableCronService {
    my ( $self, $service ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $site_dir     = $self->site_dir;
    my $site_name    = $self->site_name;
    my $site_options = $self->site_options;
    my $site_status  = $site_options->{'SiteStatus'};

    if ( not defined $service ) {
        return Output->new(
            error   => 1,
            message => "$message_p: You must defined service name"
        );
    }

    if ( $service !~ /^(xmppd|smtpd)$/ ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Service $service is not supported",
        );
    }

    if ( ( $site_status =~ /^error$/ ) && ( $site_options->{'error'} < 4 ) ) {
        return Output->new(
            error => 1,
            message =>
"$message_p: Site status=$site_status, not allow manage cron for it",
        );
    }

    $logOutput->log_data(
        "$message_p: disable start service $service for site in "
          . $site_options->{'DocumentRoot'} );

    my $cron_services = $site_options->{'CronService'};
    if ( not defined $cron_services->{$service} ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Service $service already disabled"
        );
    }

    my $site_root        = $site_options->{'DocumentRoot'};
    my $site_crontab     = $cron_services->{$service}->{'cron'};
    my $site_util        = $cron_services->{$service}->{'util'};
    my $site_crontab_tmp = $site_crontab . ".tmp";

    open( my $ch, '<', $site_crontab )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $site_crontab: $!"
      );

    open( my $cn, '>', $site_crontab_tmp )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $site_crontab_tmp: $!"
      );

    while ( my $line = <$ch> ) {
        if ( $line =~ m:$site_util\s+$service\s+$site_root: ) {
            $line = "#$line";
        }
        if ( $line =~ m:$site_util\s*$: ) {
            $line = "#$line";
        }

        print $cn $line;
    }

    close $cn;
    close $ch;

    unlink $site_crontab;
    rename $site_crontab_tmp, $site_crontab;

    return Output->new(
        error => 0,
        message =>
"$message_t: Delete task for service $service from $site_crontab for site $site_root"
    );
}

# Manage composite settings for the site
# enable  - create new settings or update existen
# disable - disable nginx settings
sub manageNginxComposite {
    my ( $self, $opt ) = @_;

    my $site_name    = $self->site_name;
    my $site_install = $self->site_options->{'SiteInstall'};
    my $site_status  = $self->site_options->{'SiteStatus'};

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if ( ( $site_install =~ /^$/ ) && ( $site_status =~ /^error$/ ) ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Not found site=$site_name on the server",
        );
    }

    if ( $site_install =~ /^ext_kernel$/ ) {
        return Output->new(
            error => 1,
            message =>
"$message_p: Site=$site_name hasn't nginx configs. Nothing to do.",
        );
    }

    my $a_opts = {
        web_site_name => $site_name,
        manage_web    => 'composite',
    };

    if ( $opt =~ /^enable$/ ) {
        $a_opts->{'manage_web'} = 'enable_composite';
    }
    elsif ( $opt =~ /^disable$/ ) {
        $a_opts->{'manage_web'} = 'disable_composite';
    }
    else {
        return Output->new(
            error => 1,
            message =>
              "$message_p: You can usage only enable or disable actions"
        );
    }
    $logOutput->log_data("$message_p: start $opt fo site_name=$site_name");

    # create site by ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );

    my $created_process = $dh->startAnsibleProcess( "site_composite", $a_opts );
    return $created_process;
}

# Manage Site options
sub siteOptions {
    my ( $self, $opt, $val ) = @_;

    my $site_name    = $self->site_name;
    my $site_install = $self->site_options->{'SiteInstall'};
    my $site_status  = $self->site_options->{'SiteStatus'};

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if ( ( $site_install =~ /^$/ ) && ( $site_status =~ /^error$/ ) ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Not found site=$site_name on the server",
        );
    }

    if ( $site_install =~ /^ext_kernel$/ ) {
        return Output->new(
            error => 1,
            message =>
"$message_p: Site=$site_name hasn't nginx configs. Nothing to do.",
        );
    }

    my $a_opts = {
        web_site_name   => $site_name,
        option          => $opt,
        value           => $val,
        manage_web      => 'site_options',
    };

    $logOutput->log_data("$message_p: start $opt fo site_name=$site_name");

    # create site by ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );

    my $created_process = $dh->startAnsibleProcess( "site_options", $a_opts );
    return $created_process;
}


# Manage certificates by LE


1;
