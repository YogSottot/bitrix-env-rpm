# manage kernel (no web interface, only kernel saved in files and database)
#
package bxSiteFiles;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use JSON;
use DBI;
use Output;
use Pool;
use bxMysql;
use Sys::Hostname;

# basic path for site
has 'site_dir',  is => 'ro', default => '/home/bitrix/www';
has 'site_conf', is => 'ro', default => 'found';
has 'site_files_options',
  is      => 'rw',
  lazy    => 1,
  builder => 'get_site_files_options';

has 'dir_kernel',    is => 'ro', default => 'bitrix';
has 'file_dbconn',   is => 'ro', default => 'php_interface/dbconn.php';
has 'file_settings', is => 'ro', default => '.settings.php';
has 'apache',        is => 'ro', default => '/etc/httpd/bx/conf';
has 'conf',          is => 'ro', default => 'conf';
has 'pref',          is => 'ro', default => 'bx_ext_';
has 'debug',         is => 'ro', default => 0;
has 'logfile',       is => 'ro', default => '/opt/webdir/logs/bxKernel.debug';

sub bx_install_options {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $site_root = $self->site_dir;
    my $site_conf = $self->site_conf;

    my $bx_options = {
        error                               => 0,
        message                             => '',
        SiteInstall                         => '',
        SiteStatus                          => '',
        DBName                              => '',
        DBType                              => '',
        DBLogin                             => '',
        DBPassword                          => '',
        DBHost                              => '',
        DBConn                              => '',
        SiteKernelDir                       => '',
        dbconn_BX_TEMPORARY_FILES_DIRECTORY => '',
    };

    $logOutput->log_data(
        "$message_p: get options from installed files in $site_root");

    my $site_kernel_dir = catfile( $site_root, $self->dir_kernel );
    if ( !-l $site_kernel_dir && !-d $site_kernel_dir ) {
        $bx_options->{'error'} = 3;
        $bx_options->{'message'} =
          "$message_p: Not found $site_kernel_dir on the host";

        # link or kernel install
    }
    else {
        # test if configuration file exists
        my $dbconn_config = catfile( $site_kernel_dir, $self->file_dbconn );
        if ( !-f $dbconn_config ) {
            $bx_options->{'error'} = 3;
            $bx_options->{'message'} =
              "$message_p: Not found config file $dbconn_config on the host";
            $logOutput->log_data(
                "$message_p: Not found config file $dbconn_config");

            # config found try get:
            # 1. finished or not installation
            # 2. DB options
        }
        else {
            # LINK - status of the install
            if ( -l $site_kernel_dir ) {

         # link file can contain own index.php => not found file, not found data
                $bx_options->{'SiteInstall'} = 'link';
                my $basic_kernel_dir = readlink($site_kernel_dir);
                my $kernel_dir       = dirname($basic_kernel_dir);
                $bx_options->{'SiteKernelDir'} = $kernel_dir;

                my $bx_index_file = catfile( $site_root, 'index.php' );
                if ( !-f $bx_index_file ) {
                    $bx_options->{'SiteStatus'} = 'not_installed';
                }
                else {
                    $bx_options->{'SiteStatus'} = 'finished';
                }

                # KERNEL- status of the install
            }
            else {
# if folder contains bitrixsetup => suspect that finished installation doesn't contain it
                $bx_options->{'SiteInstall'} = 'kernel';
                if ( $site_conf !~ /^found$/ ) {
                    $bx_options->{'SiteInstall'} = 'ext_kernel';
                }

                my $bx_setup_file = catfile( $site_root, 'bitrixsetup.php' );
                if ( -f $bx_setup_file ) {
                    $bx_options->{'SiteStatus'} = 'not_installed';
                }
                else {
                    $bx_options->{'SiteStatus'} = 'finished';
                }
            }
            $logOutput->log_data( "$message_p: found next options site_type="
                  . $bx_options->{'SiteInstall'} );
            $logOutput->log_data( "$message_p: found next options status="
                  . $bx_options->{'SiteStatus'} );

            # Get DB options from dbconn and test it
            my $desired_options = 'DBName|DBType|DBLogin|DBPassword|DBHost';
            my $defined_options = 'BX_TEMPORARY_FILES_DIRECTORY';
            open( my $dh, '<', $dbconn_config )
              or die "$message_p: Cannot open $dbconn_config: $!";
            while ( my $line = <$dh> ) {
                next if ( $line =~ /^$/ );
                next if ( $line =~ /^#/ );
                next if ( $line =~ /^;/ );
                $line =~ s/^\s+//;
                $line =~ s/\s+$//;
                $line =~ s/\s*;$//;

                if ( $line =~ /^\$($desired_options)\s*=(.+)$/ ) {
                    my $php_key   = $1;
                    my $php_value = $2;
                    $php_value =~ s/^\s+//;
                    $php_value =~ s/\s+$//;
                    if ( $php_value =~ /^'(.*)'$/ ) {
                        $php_value = $1;
                    }
                    if ( $php_value =~ /^"(.*)"$/ ) {
                        $php_value = $1;
                    }

                    # replace escaped string from php
                    $php_value =~ s/\\([^\d\w\s])/$1/g;

                    $bx_options->{$php_key} = $php_value;
                }

     # define("BX_TEMPORARY_FILES_DIRECTORY", "/home/bitrix/.bx_temp/dbksh770/")
                if ( $line =~ /define\(\"($defined_options)\",\s*\"([^\"]+)\"/ )
                {
                    my $dbconn_key   = $1;
                    my $dbconn_value = $2;

                    #print "$dbconn_key, $dbconn_value\n";

                    $bx_options->{ 'dbconn_' . $dbconn_key } = $dbconn_value;
                }
            }
            close $dh;

            # test found options or create error message
            my $test_options = '';
            foreach my $opt ( 'DBName', 'DBHost', 'DBLogin', 'DBPassword' ) {
                if ( not defined $bx_options ) {
                    $test_options .= "$opt=not_defined ";
                }
            }

            # some options is missing
            if ( $test_options !~ /^$/ ) {
                $logOutput->log_data(
"$message_p: not found some mandatory options in $dbconn_config"
                );
                $logOutput->log_data("$message_p: $test_options");
                $bx_options->{'error'} = 3;
                $bx_options->{'message'} =
                  "$message_p: in $dbconn_config $test_options";

                # all options found
            }
            else {
                # define DBtype if not dfeined in config
                if ( not defined $bx_options->{'DBType'} ) {
                    $bx_options->{'DBType'} = 'mysql';
                }
                if ( $bx_options->{'DBType'} !~ /^mysql$/ ) {
                    $bx_options->{'error'} = 3;
                    $bx_options->{'message'} =
                      "$message_p: not supported DBType="
                      . $bx_options->{'DBType'};

                    # test DB connect
                }
                else {
                    my $dbi_str =
                        "DBI:mysql:"
                      . $bx_options->{'DBName'}
                      . ";host="
                      . $bx_options->{'DBHost'}
                      . ";port=3306";

                    # add socket option for mysql
                    if ( $bx_options->{'DBHost'} =~
                        /^(localhost|localhost\.localdomain|127\.0\.0\.1)$/ )
                    {
                        $dbi_str .= ":mysql_socket=/var/lib/mysqld/mysqld.sock";
                    }

                    #print $dbi_str,"\n";
                    #print "login: ", $bx_options->{'DBLogin'}, "\n";
                    #print "pass ", $bx_options->{'DBPassword'}, "\n";

                    my $dbh = DBI->connect(
                        "$dbi_str",
                        $bx_options->{'DBLogin'},
                        $bx_options->{'DBPassword'},
                        { PrintError => 0 },
                    );
                    if ( !$dbh ) {
                        $bx_options->{'error'} = 3;
                        $bx_options->{'message'} =
"$message_p: Could not connect to database: $DBI::errstr";
                        $logOutput->log_data(
"$message_p: $message_p: Could not connect to database: $DBI::errstr"
                        );
                        $bx_options->{'DBConn'} = 'N';
                    }
                    else {
                        my $sql = 'show create database `'
                          . $bx_options->{'DBName'} . '`';
                        my $sth = $dbh->prepare($sql);
                        if ( $sth->execute ) {
                            while ( my $row = $sth->fetchrow_hashref() ) {
                                my $create_db_str = $row->{'Create Database'};
                                if ( $create_db_str =~ /\s+cp1251\s+/ ) {
                                    $bx_options->{'SiteCharset'} =
                                      'windows-1251';
                                }
                                elsif ( $create_db_str =~ /\s+utf8\s+/ ) {
                                    $bx_options->{'SiteCharset'} = 'utf-8';
                                }
                                else {
                                    if ( $create_db_str =~
                                        /CHARACTER SET\s+(\S+)\s+/ )
                                    {
                                        $bx_options->{'SiteCharset'} = $1;
                                    }
                                }
                            }
                        }
                        $sth->finish;
                        $dbh->disconnect;
                        $logOutput->log_data(
"$message_p: $message_p: Successfully connect to database: $dbi_str"
                        );
                        $bx_options->{'DBConn'} = 'Y';
                    }
                }
            }
        }
    }

    return $bx_options;
}

# test installed or not modules cluster and scale, if not installed we can't use site in the cluster
sub bx_modules_options {
    my ( $self, $db_host, $db_name, $db_user, $db_pass ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_root = $self->site_dir;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $modules_options = {
        'error'                        => 0,
        'message'                      => '',
        'module_cluster'               => 'not_installed',
        'module_scale'                 => 'not_installed',
        'module_transformer'           => 'not_installed',
        'module_transformercontroller' => 'not_installed',
        'module_main_version'          => '',
        'module_message'               => '',
        'upload_dir'                   => '',
    };
    $logOutput->log_data(
        "$message_p: try defined modules options in $site_root");

    # main module, define version
    my $version_file =
      catfile( $site_root, 'bitrix/modules/main/classes/general/version.php' );
    if ( -f $version_file ) {
        my $main_version_cmd =
          qq|php -r 'include("$version_file"); echo SM_VERSION;' 2>/dev/null|;
        my ($mh);
        if ( open( $mh, "$main_version_cmd |" ) ) {
            $modules_options->{module_main_version} = <$mh>;
            close $mh;
        }
        else {
            $modules_options->{error} = 6;
            $modules_options->{message} =
              "$message_p: Cannot find version for main module";
        }
    }
    # upload directory
    my $upload_dir_select = qq(select VALUE from b_option 
    where MODULE_ID="main" and NAME="upload_dir");


    # test if b_options exists on site
    my @test_modules =
      ( 'scale', 'cluster', 'transformer', 'transformercontroller' );
    my $select_modules = qq|select ID from b_module where ID IN ( |;
    for my $m (@test_modules) {
        $select_modules .= qq('$m',);
    }
    $select_modules =~ s/,$/\);/;

    my $dbi_str = "DBI:mysql:" . $db_name . ";host=" . $db_host . ";port=3306";
    if ( $db_host =~ /^(localhost|localhost\.localdomain|127\.0\.0\.1)$/ ) {
        $dbi_str .= ":mysql_socket=/var/lib/mysqld/mysqld.sock";
    }

    ## connect to DB
    my $dbh =
      DBI->connect( "$dbi_str", $db_user, $db_pass, { PrintError => 0 }, );
    if ( !$dbh ) {
        $modules_options->{'error'} = 5;
        $modules_options->{'message'} =
          "$message_p: Could not connect to database: $DBI::errstr";
        $logOutput->log_data(
            "$message_p: Could not connect to database: $DBI::errstr");
        return $modules_options;
    }

    $logOutput->log_data(
        "$message_p: Successfully connected to database $db_name");

    # get upload directory
    my $sth_u = $dbh->prepare("$upload_dir_select");
    if ( ! $sth_u ){
        $modules_options->{'error'} = 5;
        $modules_options->{'message'} =
          "$message_p: query $upload_dir_select return error " . $dbh->errstr;
        $logOutput->log_data(
            "$message_p: query $upload_dir_select return error " . $dbh->errstr );
        return $modules_options;
    }
    if ( $sth_u->execute ){
        my $row = $sth_u->rows;
        if ( $row> 0 ){
            while ( my $data = $sth_u->fetchrow_hashref ) {
                my $upload_dir = $data->{'VALUE'};
                $modules_options->{ 'upload_dir' } =
                    $upload_dir;
            }
        }
    }

    # get defined modules by select
    my $sth_t = $dbh->prepare("$select_modules");

    if ( !$sth_t ) {
        $modules_options->{'error'} = 5;
        $modules_options->{'message'} =
          "$message_p: query $select_modules return error " . $dbh->errstr;
        $logOutput->log_data(
            "$message_p: query $select_modules return error " . $dbh->errstr );
        return $modules_options;
    }

    # b_module is found
    if ( $sth_t->execute ) {
        my $row = $sth_t->rows;
        if ( $row > 0 ) {

            # test all modules one by one
            while ( my $data = $sth_t->fetchrow_hashref ) {
                my $module_name = $data->{'ID'};
                $modules_options->{ 'module_' . $module_name } =
                    'installed';
            }
        }
        else {
            $modules_options->{'module_message'} =
                "$message_p: not found modules "
              . join( ',', @test_modules )
              . " on $site_root";
            $logOutput->log_data( "$message_p: not found modules "
                  . join( ',', @test_modules )
                  . " on $site_root" );

        }

    }
    else {
        $modules_options->{'error'} = 5;
        $modules_options->{'message'} =
          "$message_p: query $select_modules return error " . $sth_t->errstr;
        $logOutput->log_data(
            "$message_p: query $select_modules return error "
              . $sth_t->errstr );
    }

    # test key in modules_options
    my @module_key = grep /^module_/, keys %$modules_options;

    #print join (', ', @module_key),"\n";
    foreach my $k (@module_key) {
        if ( $k =~ /^(module_main_version|module_message)$/ ) { next; }
        if ( $modules_options->{$k} =~ /^installed$/ ) {
            next;
        }
        else {
            my $m = $k;
            $m =~ s/^module_//;
            if ( $modules_options->{'module_message'} =~ /^$/ ) {
                $modules_options->{'module_message'} = "$message_p: ";
            }
            $modules_options->{'module_message'} .=
              "module $m is not installed on $site_root ";
        }
    }

    return $modules_options;
}

#enable or disable nlm option on the sites
sub bx_ntlm_options {
    my ( $self, $db_host, $db_name, $db_user, $db_pass ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_root = $self->site_dir;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $ntlm_options = {
        'error'                      => 0,
        'message'                    => '',
        'NTLM_bitrixvm_auth_support' => 'N',
        'NTLM_use_ntlm'              => 'N',
        'NTLM_module'                => 'N',
    };
    $logOutput->log_data("$message_p: try defined NTLM options for $site_root");

    my $select =
      qq(SELECT VALUE FROM b_option WHERE MODULE_ID='LDAP' AND NAME=?);
    my @options = ( 'use_ntlm', 'bitrixvm_auth_support' );

    my $dbi_str = "DBI:mysql:" . $db_name . ";host=" . $db_host . ";port=3306";

    # add socket option for mysql
    if ( $db_host =~ /^(localhost|localhost\.localdomain|127\.0\.0\.1)$/ ) {
        $dbi_str .= ":mysql_socket=/var/lib/mysqld/mysqld.sock";
    }

    my $dbh =
      DBI->connect( "$dbi_str", $db_user, $db_pass, { PrintError => 0 }, );

    if ( !$dbh ) {
        $ntlm_options->{'error'} = 3;
        $ntlm_options->{'message'} =
          "$message_p: Could not connect to database: $DBI::errstr";
        $logOutput->log_data(
            "$message_p: Could not connect to database: $DBI::errstr");
    }

    $logOutput->log_data(
        "$message_p: Successfully connected to database $db_name");

    # test if module LDAP installed on server
    my $select_module = qq(select ID from b_module where ID ='ldap');
    my $sth_module    = $dbh->prepare("$select_module");
    if ( !$sth_module ) {
        $ntlm_options->{'error'} = 6;
        $ntlm_options->{'message'} =
          "$message_p: query $select_module return error " . $dbh->errstr;
        $logOutput->log_data(
            "$message_p: query $select_module return error " . $dbh->errstr );
        return $ntlm_options;
    }
    if ( $sth_module->execute() ) {
        my $module_count = $sth_module->rows;
        if ( $module_count > 0 ) {
            $ntlm_options->{'NTLM_module'} = 'Y';
        }
    }
    else {
        $ntlm_options->{'error'} = 6;
        $ntlm_options->{'message'} =
          "$message_p: query $select_module return error "
          . $sth_module->errstr;
        $logOutput->log_data(
            "$message_p: query $select_module return error "
              . $sth_module->errstr );
        return $ntlm_options;
    }
    $sth_module->finish;

    # database can be empty
    my $sth = $dbh->prepare(
        'SELECT VALUE FROM b_option WHERE MODULE_ID="LDAP" AND NAME=?');
    if ( !$sth ) {
        $ntlm_options->{'error'} = 6;
        $ntlm_options->{'message'} =
          "$message_p: query $select return error " . $dbh->errstr;
        $logOutput->log_data(
            "$message_p: query $select return error " . $dbh->errstr );
        return $ntlm_options;
    }

    # search fo options
    foreach my $opt (@options) {
        if ( $sth->execute($opt) ) {
            my $b_options_rows = $sth->rows;

            # add options to output
            if ( $b_options_rows > 0 ) {
                while ( my $data_s = $sth->fetchrow_hashref() ) {
                    my $value = $data_s->{'VALUE'};
                    $ntlm_options->{ "NTLM_" . $opt } = $value;
                }
            }

            # select return error
        }
        else {
            $ntlm_options->{'error'} = 6;
            $ntlm_options->{'message'} =
              "$message_p: query $select return error " . $sth->errstr;
            $logOutput->log_data(
                "$message_p: query $select return error " . $sth->errstr );
        }
    }
    $sth->finish;
    $dbh->disconnect;

    foreach my $key ( grep /^NTLM_/, keys %$ntlm_options ) {
        if ( $ntlm_options->{$key} !~ /^(N|Y)$/ ) {
            $ntlm_options->{$key} = 'N';
        }
    }

    return $ntlm_options;
}

# get search module options
sub bx_sphinx_options {
    my ( $self, $db_host, $db_name, $db_user, $db_pass ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_root = $self->site_dir;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $sphinx_options = {
        'error'            => 0,
        'message'          => '',
        'SphinxConnection' => 'not_found',
        'SphinxIndexName'  => '',
    };
    $logOutput->log_data(
        "$message_p: try defined sphinx options for $site_root");

    my $select_module_opts =
      qq(select name, value from b_option where MODULE_ID = 'search';);
    my $select_b_options = qq(show tables like 'b_option';);
    my $dbi_str = "DBI:mysql:" . $db_name . ";host=" . $db_host . ";port=3306";

    # add socket option for mysql
    if ( $db_host =~ /^(localhost|localhost\.localdomain|127\.0\.0\.1)$/ ) {
        $dbi_str .= ":mysql_socket=/var/lib/mysqld/mysqld.sock";
    }

    my $dbh =
      DBI->connect( "$dbi_str", $db_user, $db_pass, { PrintError => 0 }, );
    if ( !$dbh ) {
        $sphinx_options->{'error'} = 3;
        $sphinx_options->{'message'} =
          "$message_p: Could not connect to database: $DBI::errstr";
        $logOutput->log_data(
            "$message_p: Could not connect to database: $DBI::errstr");
    }
    else {
        $logOutput->log_data(
            "$message_p: Successfully connected to database $db_name");

        # database can be empty
        my $sth_t = $dbh->prepare("$select_b_options");
        if ( !$sth_t ) {
            $sphinx_options->{'error'} = 4;
            $sphinx_options->{'message'} =
              "$message_p: query $select_b_options return error "
              . $dbh->errstr;
            $logOutput->log_data(
                "$message_p: query $select_b_options return error "
                  . $dbh->errstr );
        }
        else {
            # b_option is found
            if ( $sth_t->execute ) {
                my $b_options_rows = $sth_t->rows;
                if ( $b_options_rows == 0 ) {
                    $sphinx_options->{'error'} = 4;
                    $sphinx_options->{'message'} =
                      "$message_p: not found records in b_option table";
                    $logOutput->log_data(
                        "$message_p: not found records in b_option table");

                    # get options for search module
                }
                else {
                    my $sth_s = $dbh->prepare("$select_module_opts");

                    # error
                    if ( !$sth_s ) {
                        $sphinx_options->{'error'} = 4;
                        $sphinx_options->{'message'} =
                          "$message_p: query $select_module_opts return error "
                          . $dbh->errstr;
                        $logOutput->log_data(
"$message_p: query $select_module_opts return error "
                              . $dbh->errstr );

                        # execute
                    }
                    else {
                        if ( $sth_s->execute ) {
                            while ( my $data_s = $sth_s->fetchrow_hashref() ) {
                                my $key   = $data_s->{'name'};
                                my $value = $data_s->{'value'};
                                if ( $key =~ /^sphinx_connection$/ ) {
                                    $sphinx_options->{'SphinxConnection'} =
                                      $value;
                                }

                                if ( $key =~ /^sphinx_index_name$/ ) {
                                    $sphinx_options->{'SphinxIndexName'} =
                                      $value;
                                }
                            }

                            $sth_s->finish;
                        }
                        else {
                            $sphinx_options->{'error'} = 4;
                            $sphinx_options->{'message'} =
"$message_p: query $select_module_opts return error "
                              . $sth_s->errstr;
                            $logOutput->log_data(
"$message_p: query $select_module_opts return error "
                                  . $sth_s->errstr );
                        }
                    }
                }
                $sth_t->finish;

                # b_option not found
            }
            else {
                $sphinx_options->{'error'} = 4;
                $sphinx_options->{'message'} =
                  "$message_p: query $select_b_options return error "
                  . $sth_t->errstr;
                $logOutput->log_data(
                    "$message_p: query $select_b_options return error "
                      . $sth_t->errstr );

            }
        }
        $dbh->disconnect;
    }

    return $sphinx_options;
}

sub bx_backup_options {
    my ( $self, $db_name ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );

    $logOutput->log_data(
        "$message_p: try defined backup options for sites with $db_name");

    my $backup_info = {
        BackupTask     => 'disable',
        BackupCronFile => '',
        BackupMinute   => '',
        BackupHour     => '',
        BackupDay      => '',
        BackupMonth    => '',
        BackupWeekDay  => '',
        BackupVersion  => '',
        BackupFolder   => '',
    };

    my $task_backup_v5 = '/opt/webdir/bin/bx_backup.sh';
    my $task_backup_v4 = '/home/bitrix/backup/scripts/bxbackup.sh';

    my $task_crontab = '/etc/crontab';

    # 1. main cron file
    open( my $ch, $task_crontab ) or return $backup_info;

    while (<$ch>) {
        s/^\s+//;
        s/\s+$//;
        next if (/^$/);
        next if (/^#/);

        # min hour day month weekday user script site_name site_backup_folder
        # new version has onw script with site_name and folder defined
        if (
m:^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+$task_backup_v5\s+($db_name)\s+(\S+):
          )
        {
            $backup_info->{'BackupTask'}     = 'enable';
            $backup_info->{'BackupCronFile'} = $task_crontab;
            $backup_info->{'BackupVersion'}  = 'v5';
            $backup_info->{'BackupMinute'}   = $1;
            $backup_info->{'BackupHour'}     = $2;
            $backup_info->{'BackupDay'}      = $3;
            $backup_info->{'BackupMonth'}    = $4;
            $backup_info->{'BackupWeekDay'}  = $5;
            $backup_info->{'BackupFolder'}   = $7;
        }

        # old backup definitions
        # min hour day month weekday user test -f script_name
        if (
m:^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+test\s+\-f\s+$task_backup_v4:
          )
        {
            $backup_info->{'BackupTask'}     = 'enable';
            $backup_info->{'BackupCronFile'} = $task_crontab;
            $backup_info->{'BackupVersion'}  = 'v4';
            $backup_info->{'BackupMinute'}   = $1;
            $backup_info->{'BackupHour'}     = $2;
            $backup_info->{'BackupDay'}      = $3;
            $backup_info->{'BackupMonth'}    = $4;
            $backup_info->{'BackupWeekDay'}  = $5;
            $backup_info->{'BackupFolder'}   = '/home/bitrix/backup/archive';
        }
    }
    close $ch;

    return $backup_info;
}

# convert string
sub convert_php_str {
    my $str = shift;

    $str =~ s/^["']//;
    $str =~ s/['"]$//;

    return $str;
}

# search composite options that hold in the config file and htaccess
sub bx_composite_options {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_root = $self->site_dir;
    $site_root =~ s:/$::;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $composite_info = {
        CompositeStatus        => 'disable',
        CompositeStorage       => '',
        CompositeDomains       => [],
        CompositeExcludeUri    => [],
        CompositeIncludeUri    => [],
        CompositeExcludeParams => [],
        CompositeMemcachedHost => '',
        CompositeMemcachedPort => '',
        CompositeError         => '',
    };

    # test configuration file
    my $composite_config =
      catfile( $site_root, "bitrix/html_pages/.config.php" );
    if ( !-f $composite_config ) { return $composite_info; }

    my $composite_parser = "/opt/webdir/bin/composite.php";
    if ( !-f $composite_parser ) { return $composite_info; }

    open( my $ch, "$composite_parser -f '$composite_config' 2>/dev/null|" )
      or return $composite_info;

    my $composite_json = "";
    while (<$ch>) { $composite_json .= $_; }
    close $ch;
    my $composite_hash;

    eval { $composite_hash = decode_json($composite_json); };
    if ($@) {
        $composite_info->{CompositeError} = $composite_json;
        $composite_info->{CompositeError} =~
          s/^\s+|^(\r?\n)+|\s+$|(\r?\n)+$|\"//g;
        return $composite_info;
    }

    # process composite data
    if ( not defined $composite_hash->{'COMPOSITE'} ) {
        return $composite_info;
    }
    $composite_info->{'CompositeStatus'} =
      ( $composite_hash->{'COMPOSITE'} =~ /^Y$/i ) ? 'enable' : 'disable';

    # storage type
    $composite_info->{'CompositeStorage'} =
      ( $composite_hash->{'STORAGE'} ) ? $composite_hash->{'STORAGE'} : 'files';

    #  list domain where cache is enabled ($host check for site)
    if ( defined $composite_hash->{'DOMAINS'} ) {
        if ( ref( $composite_hash->{'DOMAINS'} ) eq 'HASH' ) {
            @{ $composite_info->{'CompositeDomains'} } =
              map { $composite_hash->{'DOMAINS'}->{$_} }
              keys %{ $composite_hash->{'DOMAINS'} };
        }
        else {
            $composite_info->{CompositeError} =
              qq|Empty DOMAINS list in the composite configuration|;
            $composite_info->{'CompositeStatus'} = 'disable';
            return $composite_info;
        }
    }

    # list excluded uri
    if ( defined $composite_hash->{'~EXCLUDE_MASK'} ) {
        @{ $composite_info->{'CompositeExcludeUri'} } =
          map { convert_php_str($_) } @{ $composite_hash->{'~EXCLUDE_MASK'} };
    }

    # list included uri
    if ( defined $composite_hash->{'~INCLUDE_MASK'} ) {
        @{ $composite_info->{'CompositeIncludeUri'} } =
          map { convert_php_str($_) } @{ $composite_hash->{'~INCLUDE_MASK'} };
    }

    # list excluded params
    if ( defined $composite_hash->{'~EXCLUDE_PARAMS'} ) {
        @{ $composite_info->{'CompositeExcludeParams'} } =
          map { convert_php_str($_) } @{ $composite_hash->{'~EXCLUDE_PARAMS'} };
    }

    # memcached settings, only for memcached* storage
    if (   ( defined $composite_hash->{'STORAGE'} )
        && ( $composite_hash->{'STORAGE'} =~ /^memcached/ ) )
    {
        $composite_info->{'CompositeMemcachedHost'} =
          ( $composite_hash->{'MEMCACHED_HOST'} )
          ? $composite_hash->{'MEMCACHED_HOST'}
          : 'localhost';
        $composite_info->{'CompositeMemcachedPort'} =
          ( $composite_hash->{'MEMCACHED_PORT'} )
          ? $composite_hash->{'MEMCACHED_PORT'}
          : '11211';
    }

    # parse configuration file
    return $composite_info;
}

# search crontab information
sub bx_cron_options {
    my ( $self, $site_db, $site_type, $site_kernel ) = @_;

    my $message_p      = ( caller(0) )[3];
    my $message_t      = __PACKAGE__;
    my $site_root      = $self->site_dir;
    my $site_cron_path = ( $site_type =~ /^link$/ ) ? $site_kernel : $site_root;
    $site_cron_path =~ s:/$::;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $cron_info = {
        CronTask    => 'disable',
        CronFile    => '',
        CronService => {},
    };

    $logOutput->log_data(
        "$message_p: try defined cron options for kernel $site_db");

    my $site_task_tool =
      catfile( $site_cron_path, 'bitrix/modules/main/tools/cron_events.php' );
    my $site_service_tool = "/opt/webdir/bin/bx_cron_services.sh";

    my @cron_files = ('/etc/crontab');
    if ( defined $site_db ) {
        push @cron_files, catfile( "/etc/cron.d", 'bx_' . $site_db );
    }

    # try found cron task
    foreach my $cron_file (@cron_files) {
        $logOutput->log_data("$message_p: test $cron_file");
        open( my $ch, '<', $cron_file ) or next;
        while (<$ch>) {
            s/^\s+//;
            s/\s+$//;
            next if (/^$/);
            next if (/^#/);

            if (m:$site_task_tool:) {
                $cron_info->{'CronTask'} = 'enable';
                $cron_info->{'CronFile'} = $cron_file;
                $logOutput->log_data(
                    "$message_p: found $site_task_tool in $cron_file");
            }

            # test service record
            if (m:$site_service_tool\s+(smtpd|xmppd)\s+$site_root:) {
                my $service = $1;
                $cron_info->{'CronService'}->{$service} =
                  { cron => $cron_file, util => $site_service_tool };
            }

            # test old service record, for default site
            if (   ( $site_root =~ m:^/home/bitrix/www$: )
                && (m:/root/bitrix-env/smtpd.sh:) )
            {
                $cron_info->{'CronService'}->{'smtpd'} =
                  { cron => $cron_file, util => '/root/bitrix-env/smtpd.sh' };
            }
            if (   ( $site_root =~ m:^/home/bitrix/www$: )
                && (m:/root/bitrix-env/xmppd.sh:) )
            {
                $cron_info->{'CronService'}->{'xmppd'} =
                  { cron => $cron_file, util => '/root/bitrix-env/xmppd.sh' };
            }
        }
        close $ch;
    }
    return $cron_info;
}

sub get_site_files_options {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $site_dir  = $self->site_dir;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );

    my $site_options = {
        error                        => 0,
        message                      => '',
        DBHost                       => '',
        DBLogin                      => '',
        DBName                       => '',
        DBPassword                   => '',
        DBType                       => '',
        DBConn                       => '',
        DocumentRoot                 => $site_dir,
        SiteInstall                  => '',
        SiteStatus                   => '',
        SphinxConnection             => '',
        SphinxIndexName              => '',
        module_cluster               => 'not_installed',
        module_scale                 => 'not_installed',
        module_transformer           => 'not_installed',
        module_transformercontroller => 'not_installed',
        NTLM_use_ntlm                => 'N',
        NTLM_bitrixvm_auth_support   => 'N',
        SiteKernelDir                => '',
        SiteKernelDB                 => '',
        BackupCronFile               => '',
        BackupMinute                 => '',
        BackupHour                   => '',
        BackupDay                    => '',
        BackupMonth                  => '',
        BackupWeekDay                => '',
        BackupVersion                => '',
        BackupFolder                 => '',
        CronTask                     => 'disable',
        CronFile                     => '',
        CronService                  => {},
        CompositeStatus              => 'disable',
        CompositeStorage             => '',
        CompositeDomains             => [],
        CompositeExcludeUri          => [],
        CompositeIncludeUri          => [],
        CompositeExcludeParams       => [],
        CompositeMemcachedHost       => '',
        CompositeMemcachedPort       => '',
    };

    ### folder and config options
    my $bx_install_options = $self->bx_install_options();
    foreach my $install_k ( keys %$bx_install_options ) {
        $site_options->{$install_k} = $bx_install_options->{$install_k};
    }
    if ( $bx_install_options->{'error'} ) {
        $site_options->{'SiteStatus'} = 'error';
        return $site_options;
    }

    #print Dumper($bx_install_options);

    if ( $site_options->{'SiteStatus'} =~ /^finished$/ ) {
        ### sphinx options
        my $bx_sphinx_options = $self->bx_sphinx_options(
            $site_options->{'DBHost'},  $site_options->{'DBName'},
            $site_options->{'DBLogin'}, $site_options->{'DBPassword'},
        );
        foreach my $sphinx_k ( keys %$bx_sphinx_options ) {
            $site_options->{$sphinx_k} = $bx_sphinx_options->{$sphinx_k};
        }
        if ( $bx_sphinx_options->{'error'} ) {
            $site_options->{'SiteStatus'} = 'error';
            return $site_options;
        }

        #print Dumper($bx_sphinx_options);
        ### test if modules cluster and scale exists on the site
        my $bx_modules_options = $self->bx_modules_options(
            $site_options->{'DBHost'},  $site_options->{'DBName'},
            $site_options->{'DBLogin'}, $site_options->{'DBPassword'},
        );

        #print Dumper($bx_modules_options);

        foreach my $mod_k ( keys %$bx_modules_options ) {
            $site_options->{$mod_k} = $bx_modules_options->{$mod_k};
        }

        if ( $bx_modules_options->{'error'} ) {
            $site_options->{'SiteStatus'} = 'error';
        }

        #print Dumper($site_options);

        #### NTLM options from DB
        my $bx_ntlm_options = $self->bx_ntlm_options(
            $site_options->{'DBHost'},  $site_options->{'DBName'},
            $site_options->{'DBLogin'}, $site_options->{'DBPassword'},
        );
        foreach my $mod_n ( keys %$bx_ntlm_options ) {
            $site_options->{$mod_n} = $bx_ntlm_options->{$mod_n};
        }
    }

    if ( $site_options->{'SiteInstall'} !~ /^$/ ) {
        ##### Backup options
        my $bx_backup_options =
          $self->bx_backup_options( $site_options->{'DBName'}, );
        foreach my $bak_k ( keys %$bx_backup_options ) {
            $site_options->{$bak_k} = $bx_backup_options->{$bak_k};
        }

        ##### Crontab options
        my $bx_cron_options = $self->bx_cron_options(
            $site_options->{'DBName'},
            $site_options->{'SiteInstall'},
            $site_options->{'SiteKernelDir'},
        );
        foreach my $cron_k ( keys %$bx_cron_options ) {
            $site_options->{$cron_k} = $bx_cron_options->{$cron_k};
        }

        ##### Composite cache options
        my $bx_composite_options = $self->bx_composite_options();
        foreach my $comp_k ( keys %$bx_composite_options ) {
            $site_options->{$comp_k} = $bx_composite_options->{$comp_k};
        }

    }

    return $site_options;
}

1;
