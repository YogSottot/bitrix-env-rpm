# list information about all sites on the server
package bxSites;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use Output;
use bxSite;
use bxSiteFiles;
use Host;
use bxMysql;
use File::Temp;
use Pool;

# basic path for site
has 'apache',  is => 'ro', default => '/etc/httpd/bx/conf';
has 'filters', is => 'rw', lazy    => 1, builder => 'set_filter';
has 'conf',    is => 'ro', default => 'conf';
has 'pref',    is => 'ro', default => 'bx_ext_';
has 'debug',   is => 'ro', default => 0;
has 'logfile', is => 'ro', default => '/opt/webdir/logs/bxSiteNew.debug';

our $TMPDIR = "/opt/webdir/tmp";
if ( !-d $TMPDIR ) {
    mkdir $TMPDIR, 0700;
}

# set filter
sub set_filter {
    my $self = shift;
    return {};
}

sub generate_password {
    my $password = '';
    my @chars = ( "A" .. "Z", "a" .. "z", "1" .. "9" );
    $password .= $chars[ rand @chars ] for 1 .. 15;
    return $password;
}

#
# listSite - list all sites: kernel, links and ext_kernel
sub listAllSite {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );
    $logOutput->log_data("$message_p: get all sites info");

    # get all configs name from apache directory
    my $apache_config_dir = $self->apache;
    opendir( my $ach, $apache_config_dir )
      or return Output->new(
        error   => 1,
        message => "Can't open $apache_config_dir: $!",
      );
    my $pref = $self->pref;
    my $ext  = $self->conf;

    my @found_sites = grep { /^$pref.+\.$ext$/ } readdir $ach;
    closedir $ach;

    if ( -f catfile( $self->apache, "default." . $self->conf ) ) {
        push @found_sites, "default";
    }

    #print join('|',@found_sites),"\n";
    $logOutput->log_data(
        "$message_p: found configs " . join( ',', @found_sites ) );

    # process site
    my %list_sites;
    my %name_to_db;
    foreach my $site_name (@found_sites) {
        $site_name =~ s/^$pref//;
        $site_name =~ s/\.$ext$//;
        $logOutput->log_data(
            "$message_p: process $site_name; get site_options");

        my $bxSites = bxSite->new( site_name => $site_name );
        my $bxSiteOptions = $bxSites->site_options;

        $list_sites{$site_name} = $bxSiteOptions;
        $logOutput->log_data("$message_p: add $site_name for sites list");
    }

    my $sites_count = keys %list_sites;
    if ( $sites_count == 0 ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Not found sites on teh server"
        );
    }
    else {
        # found ext kernels
        my @ext_kernels;
        foreach my $site_name ( keys %list_sites ) {

            # if site type is kernel, than
            # SiteKernelDir  => DBDir
            if ( $list_sites{$site_name}->{'SiteInstall'} =~ /^kernel$/ ) {
                next;

                # not found kernel,ext_kernel or link
            }
            elsif ( $list_sites{$site_name}->{'SiteInstall'} =~ /^$/ ) {
                next;

                # try found kernel info in site list
            }
            else {
                #print "site: $site_name\n";
                my $site_kernel_root =
                  $list_sites{$site_name}->{'SiteKernelDir'};
                my $site_kernel_root_regexp = $site_kernel_root;
                $site_kernel_root_regexp =~ s/\//\\\//g;

                # test kernel
                foreach my $kernel_name ( keys %list_sites ) {

                    # skip links
                    next
                      if ( $list_sites{$kernel_name}->{'SiteInstall'} =~
                        /^link$/ );

                    # found kernel with the same DBName
                    if ( $list_sites{$kernel_name}->{'DocumentRoot'} =~
                        m/^$site_kernel_root_regexp$/ )
                    {
                        $list_sites{$site_name}->{'SiteKernelDB'} =
                          $list_sites{$kernel_name}->{'DBName'};
                    }
                }

# kernel not found, assume the presence of the external core, without web configs
                if ( $list_sites{$site_name}->{'SiteKernelDB'} =~ /^$/ ) {
                    $logOutput->log_data(
"Not found kernel for $site_name - $site_kernel_root_regexp"
                    );
                    next
                      if ( grep( /^$site_kernel_root_regexp$/, @ext_kernels ) );
                    $logOutput->log_data(
                        "Add $site_kernel_root to external kernel list");
                    push @ext_kernels, $site_kernel_root;
                }
            }

        }

        # if external kernel found
        my $ext_kernels = @ext_kernels;
        if ($ext_kernels) {
            foreach my $kernel_root (@ext_kernels) {
                my $site_name = "ext_" . basename($kernel_root);

                my $bxSite = bxSite->new(
                    site_dir  => $kernel_root,
                    site_name => $site_name,
                );

                my $bxSiteOptions = $bxSite->get_site_options();

                $list_sites{$site_name} = $bxSiteOptions;
            }
        }

        return Output->new(
            error => 0,
            data  => [ $message_t, \%list_sites ],
        );
    }

}

# test limits for cluster configurations: web or mysql
# 1. exists sites without Scale module installed
# 2. exists sites without Cluster module installed
# 3. several sites ; type is kernel or ext kernel
# return:
# error => 0|1
# message => User message for output
sub testClusterConfig {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = "testClusterConfig";

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );

    my $test_result = {
        without_scale        => [],
        without_cluster      => [],
        kernels              => [],
        test_without_scale   => 0,
        test_without_cluster => 0,
        test_kernels         => 0,
    };

    my $listAllSite = $self->listAllSite();
    if ( $listAllSite->is_error ) {
        return Output->new(
            error => 0,
            data  => [ $message_t, $test_result ],
        );
    }

    foreach my $site_name ( keys %{ $listAllSite->data->[1] } ) {
        my $bxSiteOptions       = $listAllSite->data->[1]->{$site_name};
        my $site_module_scale   = $bxSiteOptions->{'module_scale'};
        my $site_module_cluster = $bxSiteOptions->{'module_cluster'};
        my $site_state          = $bxSiteOptions->{'SiteStatus'};
        my $site_dir            = $bxSiteOptions->{'DocumentRoot'};
        my $site_type           = $bxSiteOptions->{'SiteInstall'};

        # cluster configuration doesn't use
        if ( $site_state =~ /^finished$/ ) {

            # scale module
            if ( $site_module_scale =~ /^not_installed$/ ) {
                push @{ $test_result->{'without_scale'} },
                  {
                    SiteName     => $site_name,
                    DocumentRoot => $site_dir,
                    SiteInstall  => $site_type,
                  };
            }

            # cluster module
            if ( $site_module_cluster =~ /^not_installed$/ ) {
                push @{ $test_result->{'without_cluster'} },
                  {
                    SiteName     => $site_name,
                    DocumentRoot => $site_dir,
                    SiteInstall  => $site_type,
                  };
            }

            # count kernels
            if ( $site_type =~ /kernel$/ ) {
                push @{ $test_result->{'kernels'} },
                  {
                    SiteName     => $site_name,
                    DocumentRoot => $site_dir,
                    SiteInstall  => $site_type,
                  };
            }
        }
    }

    # testing result and create approve/disapprove for cluster configuration
    $test_result->{'test_kernels'}       = @{ $test_result->{'kernels'} };
    $test_result->{'test_without_scale'} = @{ $test_result->{'without_scale'} };
    $test_result->{'test_without_cluster'} =
      @{ $test_result->{'without_cluster'} };

    return Output->new(
        error => 0,
        data  => [ $message_t, $test_result ],
    );
}

# listSite - list all sites with defined filters
sub listSite {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );
    $logOutput->log_data("$message_p: get all sites info with filters");

    my $listAllSite = $self->listAllSite();
    if ( $listAllSite->is_error ) { return $listAllSite; }
    my %list_sites;

    my $filters       = $self->filters;
    my $filters_count = keys %$filters;
    $logOutput->log_data(
        "$message_p: user define $filters_count filters: " . Dumper($filters) );

    foreach my $site_name ( keys %{ $listAllSite->data->[1] } ) {
        my $skip_site     = 0;
        my $bxSiteOptions = $listAllSite->data->[1]->{$site_name};

        if ($filters_count) {
            foreach my $fk ( keys %$filters ) {
                my $filter_val = $filters->{$fk};
                $filter_val =~ s/^['"]//;
                $filter_val =~ s/['"]$//;
                if ( $bxSiteOptions->{$fk} !~ /^($filter_val)$/ ) {
                    $skip_site = 1;
                    $logOutput->log_data(
                            "$message_p: skip site $site_name because key=$fk "
                          . $bxSiteOptions->{$fk} . "!="
                          . $filter_val );
                }
            }
        }

        next if ( $skip_site == 1 );
        $list_sites{$site_name} = $bxSiteOptions;
        $logOutput->log_data("$message_p: add $site_name for sites list");
    }
    my $sites_count = keys %list_sites;
    if ( $sites_count == 0 ) {
        my $user_message = "Not found sites with defined options:";
        foreach my $k ( sort keys %$filters ) {
            $user_message .= " $k=" . $filters->{$k};
        }

        return Output->new(
            error   => 1,
            message => "$message_p: $user_message"
        );
    }
    else {
        return Output->new(
            error => 0,
            data  => [ $message_t, \%list_sites ],
        );
    }

}

# enable backup task for sites with the same DBName
sub enableBackupForDB {
    my $self        = shift;
    my $kernel_name = shift;
    my $cron_min    = shift;
    my $cron_hour   = shift;
    my $cron_day    = shift;
    my $cron_month  = shift;
    my $cron_wday   = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );
    $logOutput->log_data(
        "$message_p: enable backup for kernel_name=$kernel_name");

    # get cron info
    my $task_backup_v5   = '/opt/webdir/bin/bx_backup.sh';
    my $task_backup_v4   = '/home/bitrix/backup/scripts/bxbackup.sh';
    my $task_crontab     = '/etc/crontab';
    my $task_backup_dir  = '/home/bitrix/backup';
    my $task_archive_dir = catfile( $task_backup_dir, 'archive' );
    my $task_user        = 'bitrix';

    my $task_crontab_bak = '/etc/crontab.bak';

    # this task can do replace for backup and we need temporary file
    open( my $hb, ">$task_crontab_bak" )
      or return Output->new(
        error   => 1,
        message => "Cannot open $task_crontab_bak: $!",
      );

    open( my $hc, "$task_crontab" )
      or return Output->new(
        error   => 1,
        message => "Cannot open $task_crontab: $!",
      );

    my $is_found = 0;
    while (<$hc>) {
        s/^\s+//;
        s/\s+$//;
        my $str = $_;

        if ( $str =~ /^$/ || $str =~ /^#/ ) {
            print $hb $str, "\n";
            next;
        }

        # min hour day month weekday user script site_name site_backup_folder
        # new version has onw script with site_name and folder defined
        if (
m:^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+$task_backup_v5\s+($kernel_name)\s+(\S+):
          )
        {
            $str =
"$cron_min $cron_hour $cron_day $cron_month $cron_wday $task_user $task_backup_v5 $kernel_name $task_archive_dir";
            $is_found = 1;
            $logOutput->log_data(
                "$message_p: found backup v5 for $kernel_name; replace it");
        }

        # old backup definitions
        # min hour day month weekday user test -f script_name
        if (
m|^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+test\s+\-f\s+$task_backup_v4|
          )
        {
            $str =
"$cron_min $cron_hour $cron_day $cron_month $cron_wday $task_user $task_backup_v5 $kernel_name $task_archive_dir";
            $is_found = 1;
            $logOutput->log_data(
                "$message_p: found backup v4 for $kernel_name; replace it");
        }

        print $hb $str, "\n";
    }

    if ( $is_found == 0 ) {
        print $hb
"$cron_min $cron_hour $cron_day $cron_month $cron_wday $task_user $task_backup_v5 $kernel_name $task_archive_dir\n";
        $is_found = 1;
        $logOutput->log_data(
            "$message_p: not found backup for $kernel_name; create new one");
    }

    close $hc;
    close $hb;

    # change access rights
    if ( !-d $task_backup_dir )  { mkdir $task_backup_dir; }
    if ( !-d $task_archive_dir ) { mkdir $task_archive_dir; }

    my ( $task_login, $task_pass, $task_uid, $task_guid ) = getpwnam($task_user)
      or return Output->new(
        error   => 1,
        message => "User $task_user not found in password file",
      );

    chown $task_uid, $task_guid, $task_backup_dir, $task_archive_dir;

    unlink $task_crontab;
    rename $task_crontab_bak, $task_crontab;

    # restart cron service
    my $cron_cmd = qq(/sbin/service crond restart 1>/dev/null 2>/dev/null);
    system($cron_cmd) == 0
      or return Output->new(
        error   => 1,
        message => "Failed restart crond service"
      );

    return $self->listSite( filters => { DBName => $kernel_name } );
}

# disable backup cron task for dbname
sub disableBackupForDB {
    my $self        = shift;
    my $kernel_name = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    # get cron info
    my $task_backup_v5 = '/opt/webdir/bin/bx_backup.sh';
    my $task_backup_v4 = '/home/bitrix/backup/scripts/bxbackup.sh';
    my $task_crontab   = '/etc/crontab';

    my $task_crontab_bak = '/etc/crontab.bak';

    # this task can do replace for backup and we need temporary file
    open( my $hb, ">$task_crontab_bak" )
      or return Output->new(
        error   => 1,
        message => "Cannot open $task_crontab_bak: $!",
      );
    open( my $hc, "$task_crontab" )
      or return Output->new(
        error   => 1,
        message => "Cannot open $task_crontab: $!",
      );
    my $is_found = 0;
    while (<$hc>) {
        s/^\s+//;
        s/\s+$//;
        my $str = $_;

        if ( $str =~ /^$/ || $str =~ /^#/ ) {
            print $hb $str, "\n";
            next;
        }

        # min hour day month weekday user script site_name site_backup_folder
        # new version has onw script with site_name and folder defined
        if (
m:^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+$task_backup_v5\s+($kernel_name)\s+(\S+):
          )
        {
            $is_found = 1;
            next;
        }

        # old backup definitions
        # min hour day month weekday user test -f script_name
        if (
m|^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+test\s+\-f\s+$task_backup_v4|
          )
        {
            $is_found = 1;
            next;
        }

        print $hb $str, "\n";
    }

    close $hc;
    close $hb;

    unlink $task_crontab;
    rename $task_crontab_bak, $task_crontab;

    return $self->listSite( filters => { DBName => $kernel_name } );
}

# add or delete web role from server;
# in case creation second server in group with web role => create balancer
sub changeHostForWebCluster {
    my ( $self, $host1, $action, $fstype ) = @_;

    my $p = Pool->new( debug => $self->debug, );
    my $get_hi = $p->get_inventory_hostname($host1);
    return $get_hi if ( $get_hi->is_error );
    my $server_name = $get_hi->data->[1];

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if ( $action !~ /^(create_web|delete_web|web1|web2)$/ ) {
        return Output->new(
            error => 1,
            message =>
"$message_p: action can hold 'create_web', 'delete_web', 'web1' or 'web2' values"
        );
    }

    # csync or lsync
    if ( not defined $fstype ) {
        $fstype = "lsync";
    }

    $logOutput->log_data("$message_p: $action for $server_name");

    my $host = Host->new( host => $server_name );
    my $is_host_in_pool = $host->host_in_pool();
    if ( $is_host_in_pool->is_error ) {
        return $is_host_in_pool;
    }

    # test sites; scale and cluster modules + number kernels sites
    if ( ( $action eq "web2" ) or ( $action eq "create_web" ) ) {
        my $testClusterConfig = $self->testClusterConfig();
        my $test_data         = $testClusterConfig->get_data->[1];
        if (   ( $test_data->{'test_kernels'} > 1 )
            || ( $test_data->{'test_without_scale'} > 0 )
            || ( $test_data->{'test_without_cluster'} > 0 ) )
        {
            return Output->new(
                error => 1,
                message =>
"$message_p: Found conditions when web-cluster configuration is disabled",
            );
        }
    }

    # create cluster and replica passwords
    my $mysql_group   = bxMysql->new();
    my $mysql_options = $mysql_group->mysql_cluster_options;
    $mysql_options->{'group'} = 'mysql';

    # run ansible playbook
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );

    $mysql_options->{manage_web} =
      $action;    # create_web, delete_web, web1 or web2
    $mysql_options->{fstype} = $fstype;

    # run playbook
    if ( $action eq "delete_web" ) {
        $mysql_options->{'deleted_web_server'} = $server_name;
    }
    else {
        if ( $action eq "web1" ) {

            delete $mysql_options->{cluster_password_file}
              if ( defined $mysql_options->{cluster_password_file} );
            delete $mysql_options->{replica_password_file}
              if ( defined $mysql_options->{replica_password_file} );
        }
        $mysql_options->{'new_web_server'} = $server_name;
    }

    #print Dumper($mysql_options);
    #exit;

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );

    my $created_process =
      $dh->startAnsibleProcess( 'web_cluster', $mysql_options );
    return $created_process;
}

# create site
# site_options define parametrs for new site
# mandatory:
# ServerName
# SiteInstall
sub CreateSite {
    my $self         = shift;
    my $site_options = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    # set option to default values
    if ( not defined $site_options->{'SiteInstall'} ) {
        $site_options->{'SiteInstall'} = "link";
    }

    # test mandatory options
    if ( not defined $site_options->{'ServerName'} ) {
        if ( not defined $site_options->{'DocumentRoot'} ) {
            return Output->new(
                error => 1,
                message =>
"$message_p: for site creation you must defined site_name or site_dir"
            );
        }
        else {
            if ( $site_options->{'SiteInstall'} =~ /^ext_kernel$/ ) {
                $site_options->{'ServerName'} =
                  basename( $site_options->{'DocumentRoot'} );
            }
            else {
                return Output->new(
                    error   => 1,
                    message => "$message_p: for creation site "
                      . $site_options->{'SiteInstall'}
                      . " you must defined site_name"
                );
            }
        }
    }

    # charset option test
    if ( defined $site_options->{'SiteCharset'} ) {
        if ( $site_options->{'SiteCharset'} !~ /^(utf-8|windows-1251)$/i ) {
            return Output->new(
                error   => 1,
                message => "$message_p: charset="
                  . $site_options->{'SiteCharset'}
                  . "; it can contain only 'utf-8' or 'windows-1251'",
            );
        }
        $site_options->{'SiteCharset'} =~ tr/A-Z/a-z/;
    }

    # transform site_options to playbook options
    my $p_opts = {
        manage_web    => "create_site",
        web_site_name => $site_options->{'ServerName'},
        web_site_type => $site_options->{'SiteInstall'},
    };
    if ( $site_options->{'DocumentRoot'} ) {
        $p_opts->{'web_site_dir'} = $site_options->{'DocumentRoot'};
    }
    if ( $site_options->{'DBName'} ) {
        $p_opts->{'web_site_db'} = $site_options->{'DBName'};
    }
    if ( $site_options->{'DBLogin'} ) {
        $p_opts->{'web_site_dbuser'} = $site_options->{'DBLogin'};
    }
    if ( $site_options->{'DBPassword'} ) {
        if ( not defined $site_options->{DBPasswordFile} ) {
            my $tmp = File::Temp->new(
                TEMPLATE => '.siteXXXXXXXX',
                UNLINK   => 0,
                DIR      => $TMPDIR,
            );

            print $tmp $site_options->{'DBPassword'};
            $site_options->{DBPasswordFile} = $tmp->filename;
        }
    }
    if ( $site_options->{'SiteKernelName'} ) {
        $p_opts->{'web_kernel_site'} = $site_options->{'SiteKernelName'};
    }
    if ( $site_options->{'SiteKernelDir'} ) {
        $p_opts->{'web_kernel_root'} = $site_options->{'SiteKernelDir'};
    }
    if ( $site_options->{'SiteCharset'} ) {
        $p_opts->{'bitrix_site_charset'} = $site_options->{'SiteCharset'};
    }
    if ( $site_options->{'DBPasswordFile'} ) {
        $p_opts->{'web_site_dbpass_file'} = $site_options->{'DBPasswordFile'};
    }

    # create cron settings for site or not
    if ( $site_options->{'CronTask'} ) {
        $p_opts->{'web_site_cron'} = 'enable';
    }
    else {
        $p_opts->{'web_site_cron'} = 'disable';
    }

    # push
    if ( $site_options->{NodeJSPush} ) {
        $p_opts->{NodeJSPush} = "enable";
    }
    else {
        $p_opts->{NodeJSPush} = "disable";
    }

    $logOutput->log_data( "$message_p: start creation of new site="
          . $site_options->{'ServerName'} . "type="
          . $site_options->{'SiteInstall'} );

    # create site by ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( "site_create", $p_opts );

    return $created_process;
}

# delete site
# site_options define parametrs for new site
# mandatory:
# ServerName or DocumentRoot
sub DeleteSite {
    my $self         = shift;
    my $site_options = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    # test mandatory options
    if (   ( not defined $site_options->{'ServerName'} )
        && ( not defined $site_options->{'DocumentRoot'} ) )
    {
        return Output->new(
            error => 1,
            message =>
"$message_p: for site creation you must defined site_name or site_dir"
        );
    }

    # transform site_options to playbook options
    my $p_opts = { manage_web => "delete_site", };

    my $log_str = "delete site";
    if ( $site_options->{'DocumentRoot'} ) {
        $p_opts->{'web_site_dir'} = $site_options->{'DocumentRoot'};
        $log_str .= " site_dir=" . $site_options->{'DocumentRoot'};
    }
    if ( $site_options->{'ServerName'} ) {
        $p_opts->{'web_site_name'} = $site_options->{'ServerName'};
        $log_str .= " site_name=" . $site_options->{'ServerName'};
    }

    $logOutput->log_data("$message_p: $log_str");

    # create site by ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( "site_delete", $p_opts );

    return $created_process;
}

# create NTLM settings for all sites on the server
sub changeNTLMForSite {
    my ( $self, $domain, $fqdn, $ads, $login, $host, $dbname, $password_file )
      = @_;
    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if (   !$domain
        || !$fqdn
        || !$ads
        || !$login
        || !$password_file
        || !$dbname )
    {
        return Output->new(
            error => 1,
            message =>
"$message_p: Options ntlm_domain= ntlm_fqdn= ntlm_ads= and password_file= dbname= are mandatory",
        );
    }
    my $p_opts;
    $p_opts->{'manage_web'}     = 'ntlm_on';
    $p_opts->{'ntlm_name'}      = $domain;
    $p_opts->{'ntlm_fqdn'}      = $fqdn;
    $p_opts->{'ntlm_dps'}       = $ads;
    $p_opts->{'manage_kernel'}  = $dbname;
    $p_opts->{'ntlm_user'}      = $login;
    $p_opts->{'ntlm_pass_file'} = $password_file;
    if ($host) { $p_opts->{'ntlm_host'} = $host; }

    # create ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    $logOutput->log_data(
        "$message_p: start create ntlm settings for host and db="
          . $p_opts->{'manage_kernel'} );

    my $created_process = $dh->startAnsibleProcess( 'change_ntlm', $p_opts );
    return $created_process;
}

# update NTLM settings for all sites on the server
sub updateNTLMForSite {
    my ( $self, $dbname ) = @_;
    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if ( !$dbname ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Options dbname= are mandatory",
        );
    }
    my $p_opts;
    $p_opts->{'manage_web'}    = 'ntlm_on';
    $p_opts->{'manage_kernel'} = $dbname;

    # start playbook
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    $logOutput->log_data(
        "$message_p: start create ntlm settings for host and db="
          . $p_opts->{'manage_kernel'} );

    my $created_process = $dh->startAnsibleProcess( 'change_ntlm', $p_opts );
    return $created_process;
}

#NTLM Status
sub getNTLMServerStatus {
    my ($self) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $ntlm_options = {
        'LDAPServer' => '',
        'LDAPPort'   => '',
        'Realm'      => '',
        'BindPath'   => '',
        'KDCServer'  => '',
        'TimeOffset' => '',
        'Status'     => 'not_configured',
    };

    my $net_cmd = qq(/usr/bin/net ads info);
    open( my $nh, "-|", "$net_cmd 2>/dev/null" )
      or return Output->new(
        error   => 1,
        message => "$message_p: command \`$net_cmd\` return error: $!",
      );
    while ( my $line = <$nh> ) {
        chomp($line);
        if ( $line =~ /^LDAP server name:\s+(\S+)/ ) {
            $ntlm_options->{'LDAPServer'} = $1;
        }
        if ( $line =~ /^LDAP port:\s+(\S+)/ ) {
            $ntlm_options->{'LDAPPort'} = $1;
        }
        if ( $line =~ /^Realm:\s+(\S+)/ ) {
            $ntlm_options->{'Realm'} = $1;
        }
        if ( $line =~ /^Bind Path:\s+(\S+)/ ) {
            $ntlm_options->{'BindPath'} = $1;
        }
        if ( $line =~ /^KDC server:\s+(\S+)/ ) {
            $ntlm_options->{'KDCServer'} = $1;
        }
        if ( $line =~ /^Server time offset:\s+(\S+)/ ) {
            $ntlm_options->{'TimeOffset'} = $1;
        }
    }
    close $nh;

    my $is_empty = 0;
    foreach my $k ( keys %$ntlm_options ) {
        if ( $ntlm_options->{$k} =~ /^$/ ) { $is_empty = 1 }
    }

    if ( $is_empty == 0 ) { $ntlm_options->{'Status'} = 'configured'; }

    return Output->new(
        error => 0,
        data  => [ 'NTLMStatus', $ntlm_options ]
    );
}

# enable|disable php extension
sub php_extension {
    my ( $self, $ext, $type ) = @_;
    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxSite';

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if ( !$ext || !$type ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Options ext= and type= are mandatory",
        );
    }
    my $p_opts;
    $p_opts->{'extension'}  = $ext;
    $p_opts->{'type'}       = $type;
    $p_opts->{'manage_web'} = "php_extension";

    # start playbook
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    $logOutput->log_data( "$message_p: change settiongs for php extension=="
          . $p_opts->{'extension'} );

    my $created_process = $dh->startAnsibleProcess( 'php_ext', $p_opts );
    return $created_process;
}

# configure Push Server
sub configurePushServer {
    my ( $self, $host, $manage ) = @_;
    my $message_p = ( caller(0) )[3];
    my $message_t = 'bxPush';

    my $p = Pool->new( debug => $self->debug, );
    my $get_hi = $p->get_inventory_hostname($host);
    return $get_hi if ( $get_hi->is_error );
    my $hostname = $get_hi->data->[1];

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    if ( !$manage ) {
        return Output->new(
            error => 1,
            message =>
              "$message_p: Options hostname= and action= are mandatory",
        );
    }
    $manage =~ s/^push_//;

    my $p_opts;
    $p_opts->{'hostname'} = $hostname;
    $p_opts->{'manage'}   = $manage;

    # start playbook
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "push-server.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    $logOutput->log_data(
        "$message_p: $manage Push Nodejs server on hostname="
          . $p_opts->{'hostname'} );

    my $created_process = $dh->startAnsibleProcess( 'pushserver', $p_opts );
    return $created_process;
}

sub testListSites {
    my ( $self, $opts ) = @_;
    my ( @site_names, $sites_filter );
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    if ( not defined $opts->{site_names} ) {
        return Output->new(
            error   => 1,
            message => "Sites list cannot be empty",
        );
    }

    $opts->{site_names} =~ s/\s+//g;

    # create list of sites
    if ( $opts->{site_names} =~ /,/ ) {
        @site_names = split( ",", $opts->{site_names} );
        $sites_filter = join( '|', @site_names );
    }
    else {
        push @site_names, $opts->{site_names};
        $sites_filter = $opts->{site_names};
    }

    #print Dumper(\@site_names);

    my $l = $self->listAllSite();
    return $l if ( $l->is_error );
    my $sites = $l->data->[1];

    # test site list
    foreach my $site_name (@site_names) {
        if ( not defined $sites->{$site_name} ) {
            return Output->new(
                error => 1,
                message =>
                  "$message_p: Not found site $site_name on the server",
            );
        }

        my $site_install = $sites->{$site_name}->{'SiteInstall'};
        my $site_status  = $sites->{$site_name}->{'SiteStatus'};

        if ( ( $site_install =~ /^$/ ) && ( $site_status =~ /^error$/ ) ) {
            return Output->new(
                error => 1,
                message =>
                  "$message_p: Not found site $site_name on the server",
            );
        }

        if ( $site_install =~ /^ext_kernel$/ ) {
            return Output->new(
                error => 1,
                message =>
"$message_p: Site=$site_name hasn't nginx configs. Nothing to do.",
            );
        }

        #print "$site_name $site_install $site_status\n";
    }

    return Output->new(
        error => 0,
        data  => [ "site_names", \@site_names, $sites_filter ],
    );

}

sub configureLE {
    my ( $self, $opts ) = @_;

    my ( @site_names, @dns, $email, $sites_filter );
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $test_sites = $self->testListSites($opts);
    return $test_sites if ( $test_sites->is_error );
    @site_names   = @{ $test_sites->data->[1] };
    $sites_filter = $test_sites->data->[2];

    # test options
    foreach my $k ( "dns", "email" ) {
        if ( not defined $opts->{$k} ) {
            return Output->new(
                error    => 1,
                messages => "$message_p: Option $k cannot be empty",
            );
        }
    }
    if ( $opts->{dns} =~ /,/ ) {
        @dns = map { s/\s+//g; $_ } split( ",", $opts->{dns} );
    }
    else {
        $dns[0] = $opts->{dns};
    }

    my $a_opts = {
        dns_names    => \@dns,
        site_names   => \@site_names,
        email        => $opts->{email},
        manage_web   => 'configure_le',
        sites_filter => $sites_filter,
    };

    $logOutput->log_data( "$message_p: configure LE certificate fo sites "
          . $opts->{site_names} );

    # create site by ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );

    my $created_process =
      $dh->startAnsibleProcess( "site_certificate", $a_opts );
    return $created_process;
}

sub configureCert {
    my ( $self, $opts ) = @_;

    my ( @site_names, $sites_filter );
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $test_sites = $self->testListSites($opts);
    return $test_sites if ( $test_sites->is_error );
    @site_names   = @{ $test_sites->data->[1] };
    $sites_filter = $test_sites->data->[2];

    # test options
    foreach my $k ( "private_key", "certificate" ) {
        if ( not defined $opts->{$k} ) {
            return Output->new(
                error    => 1,
                messages => "$message_p: Option $k cannot be empty",
            );
        }
    }
    if ( not defined $opts->{certificate_chain} ) {
        $opts->{certificate_chain} = "";
    }

    my $nginx_path = "/etc/nginx/certs";
    foreach my $opt ( "certificate_chain", "certificate", "private_key" ) {
        if ( ( $opt eq "certificate_chain" ) && ( $opts->{$opt} =~ /^$/ ) ) {
            delete $opts->{$opt};
            next;
        }

        if ( !-f $opts->{$opt} ) {
            if ( -f catfile( $nginx_path, $opts->{$opt} ) ) {
                $opts->{$opt} = catfile( $nginx_path, $opts->{$opt} );
            }
            else {
                return Output->new(
                    error => 1,
                    message =>
                      "$message_p: Not found $opt=$opts->{$opt} on the server",
                );
            }
        }
    }
    $opts->{manage_web}   = "configure_cert";
    $opts->{site_names}   = \@site_names;
    $opts->{sites_filter} = $sites_filter;

    $logOutput->log_data( "$message_p: configure own certificate fo sites "
          . $opts->{site_names} );

    # create site by ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );

    my $created_process = $dh->startAnsibleProcess( "site_certificate", $opts );
    return $created_process;
}

sub resetCert {
    my ( $self, $opts ) = @_;

    my ( @site_names, $sites_filter );
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $test_sites = $self->testListSites($opts);
    return $test_sites if ( $test_sites->is_error );
    @site_names   = @{ $test_sites->data->[1] };
    $sites_filter = $test_sites->data->[2];

    $opts->{manage_web}   = "reset_cert";
    $opts->{site_names}   = \@site_names;
    $opts->{sites_filter} = $sites_filter;

    $logOutput->log_data(
        "$message_p: reset certificate configuration for sites "
          . $opts->{site_names} );

    # create site by ansible task
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "web.yml" );
    my $dh       = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );

    my $created_process = $dh->startAnsibleProcess( "site_certificate", $opts );
    return $created_process;
}

1;
