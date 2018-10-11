# output information to log or screen
#
package Output;
use Moose;
use JSON;
use POSIX qw(strftime);
use Data::Dumper;

## attributes
# error|code - return value from utils
has 'error' => ( is => 'rw', isa => 'Int', default => 0 );

# text message about error or status
has 'message' => ( is => 'rw', isa => 'Str' );

# status - status of long-running operations
has 'status' => ( is => 'rw', isa => 'Str' );

# data - additional data in the message
# ex. configuration of pool servers
has 'data' => ( is => 'rw', isa => 'ArrayRef' );

# format - output format: json or plain(txt)
has 'format' => ( is => 'ro', isa => 'Str', default => 'plain' );

# path to log file
has 'logfile' =>
  ( is => 'rw', isa => 'Str', default => '/opt/webdir/logs/wrapper.log' );

has 'debug' => ( is => 'rw', isa => 'Int', default => 0 );

# print facts like ansible module
sub printAnsible {
    my $self      = shift;
    my $attribute = shift;    # print only attribute
    my $hiden     = shift;    # print hiden attribute
    my $status    = shift;    # finished|not_istalled|any

    my $data = $self->data;
    my $type = ($data->[0])? $data->[0]: "NOT_DEFINED";
    my $info = $data->[1];

    $attribute = "all" if ( !$attribute );
    if ( not defined $status ) { $status = 'any'; }
    if ( not defined $hiden )  { $hiden  = 1; }

    # final info in that hash
    my $print_info = {};
    $print_info->{'changed'} = 'true';
    $print_info->{'msg'} = $self->message if (defined $self->message);

    if ( $self->error > 0 ) {
        $print_info->{'changed'} = 'false';
        $print_info->{'failed'}  = 'true';
    }
    else {
        if ( $type =~ /^bxSite$/ ) {
            my $id = 0;

            # foreach found sites
            foreach my $site_name ( keys %$info ) {
                my $site_data = $info->{$site_name};

                # if we need only installed or not_itstalled sites info
                if (   $status !~ /^any$/
                    && $site_data->{'SiteStatus'} !~ /^$status$/ )
                {
                    next;
                }

                # create list of sitesnames
                $print_info->{'ansible_facts'}->{'bx_sites'}->[$id]
                  ->{'SiteName'} = $site_name;

                # if need only list of sites
                if ( $attribute =~ /^SiteNames$/ ) { next; }

                # process attributes
                foreach my $key ( keys %{ $info->{$site_name} } ) {
                    if ( $attribute !~ /^all$/ && $key !~ /^$attribute$/ ) {
                        next;
                    }
                    my $val = $info->{$site_name}->{$key};
                    if ( $hiden == 0 && $key =~ /password/i ) {
                        $val = "***************";
                    }
                    $print_info->{'ansible_facts'}->{'bx_sites'}->[$id]->{$key}
                      = $val;
                }
                $id++;
            }
        }
        elsif ( $type =~ /(updateHost|deleteHost)/ ) {
            my $changed = 'false';
            foreach my $k ( keys %{$info} ) {
                if ( $info->{$k} =~ /^(yes|true)$/i ) {
                    $changed = 'true';
                }
            }

            $print_info->{'changed'} = $changed;
            if ( $self->message ) {
                $print_info->{'msg'} = $self->message;
            }
        }
        elsif ( $type =~ /^(pool_interface_revert|pool_interfaces)$/ ) {
            foreach my $k ( keys %{$info} ) {
                $print_info->{'ansible_facts'}->{'bx_network'}->{$k} =
                  $info->{$k};
            }
        }
        elsif ( $type =~ /^testClusterConfig$/ ) {
            foreach my $k ( 'test_kernels', 'test_without_scale',
                'test_without_cluster' )
            {
                $print_info->{'ansible_facts'}->{$k} = $info->{$k};
            }
        }
    }
    print to_json( $print_info, pretty => 1 );
    exit $self->error;
}

# print message to stdout
sub print {
    my $self   = shift;
    my $format = shift;
    my $hiden  = shift;

    if ( !$format ) { $format = $self->format; }
    if ( !$hiden )  { $hiden  = 0; }

    #print Dumper($self);

    # JSON output
    if ( $format =~ /^json$/ ) {
        my $output_hash = {};
        if ( $self->error > 0 ) { $output_hash->{'error'}   = $self->error }
        if ( $self->message )   { $output_hash->{'message'} = $self->message }
        if ( $self->data ) {
            if ( $self->data->[0] =~ /^(hosts|bxDaemon)$/ ) {
                $output_hash->{'params'} = $self->data->[1];
                #if ( $self->data->[0] =~ /^bxDaemon$/ ){
                #    print Dumper($self->data->[1]);
                #}
            }
            elsif ( $self->data->[0] =~ /^bxSite$/ ) {
                my $info = $self->data->[1];
                if ( $hiden == 0 ) {
                    foreach my $site_name ( keys %{$info} ) {
                        foreach my $key ( keys %{ $info->{$site_name} } ) {
                            if ( $key =~ /password/i ) {
                                $info->{$site_name}->{$key} = "*************";
                            }
                        }
                    }
                }
                $output_hash->{'params'} = $info;
            }
            else {
                $output_hash->{'params'} =
                  { $self->data->[0] => $self->data->[1] };
            }
        }
        if ( $self->status ) { $output_hash->{'status'} = $self->status }

        my $json_text = to_json( $output_hash, pretty => 1 );
        print $json_text

          # plain|txt format
    }
    else {
# process additional data
# two types of structs:
# [type, values] or [type, {key => { opt => value, }, }
# ex.
# sshkey => [ sshkey, '/path/to/ssh/key' ]
# hosts  => [ hosts,  { vm => { ip => 1.1.1.1, roles => [mgmt, web, mysql ] } , vm2 => { ip => 1.2.2.2 } } ]
        if ( $self->data ) {
            my $data = $self->data;

            #print Dumper($data);
            my $data_type = $data->[0];
            my $data_info = $data->[1];

            # host information
            if ( $data_type =~ /^hosts$/ ) {
                foreach my $h ( sort keys %$data_info ) {
                    my $roles = $data_info->{$h}->{'roles'};
                    my $ip    = $data_info->{$h}->{'ip'};
                    my $host_id =
                      ( $data_info->{$h}->{'host_id'} )
                      ? $data_info->{$h}->{'host_id'}
                      : '';
                    my $roles_out = '';
                    $roles_out .= join( ',', sort keys %$roles );
                    if ( $roles_out =~ /mysql/ ) {
                        my $mysql_type = $roles->{'mysql'}->{'type'};
                        my $mysql_id   = $roles->{'mysql'}->{'id'};
                        $roles_out =~
                          s/\bmysql\b/mysql_${mysql_type}_${mysql_id}/;
                    }
                    my $hostname =
                        ( $data_info->{$h}->{hostname} )
                        ? $data_info->{$h}->{hostname}
                        : $h;
                    print "host:$h:$ip:$roles_out:$host_id:$hostname\n";

                }

                # ssh key info
            }
            elsif ( $data_type =~ /^sshkey$/ ) {
                print "info:$data_type:$data_info\n";
            }
            elsif ( $data_type =~ /^monitor$/ ) {
                print "info:$data_type:",
                  $data_info->{'monitoring_server_netaddr'}, ":",
                  $data_info->{'monitoring_status'},         "\n";
            }
            elsif ( $data_type =~ /^bxDaemon$/ ) {

                #print Dumper( $data_info );
                foreach my $task_id ( grep {!/^task_name$/} sort keys %$data_info ) {
                    my $t = $data_info->{$task_id};

                    #print Dumper($t);
                    my $pid     = $t->{'pid'};
                    my $status  = $t->{'status'};
                    my $created = $t->{'created'};
                    $created = "" if ( not defined $created );
                    my $modified = $t->{'modified'};
                    $modified = "" if ( not defined $modified );
                    my $last_action = $t->{'last_action'};
                    $last_action = "" if ( not defined $last_action );
                    my $errors = $t->{'errors'};
                    $errors = "" if ( not defined $errors );
                    my $hosts_wirh_errors = "";

                    if ( defined $t->{'error_on_hosts'} ) {
                        $hosts_wirh_errors =
                          join( ',', @{ $t->{'error_on_hosts'} } );
                    }

                    print
"info:$data_type:$task_id:$pid:$created:$modified:$status:$errors:$hosts_wirh_errors:$last_action\n";
                }
            }
            elsif ( $data_type =~ /^bxMC$/ ) {

                #print Dumper($data_info);
                foreach my $srv_name ( sort keys %$data_info ) {
                    my $t = $data_info->{$srv_name};
                    my $mc_port =
                      ( $t->{'memcached_port'} ) ? $t->{'memcached_port'} : "";
                    my $mc_size =
                      ( $t->{'memcached_size'} ) ? $t->{'memcached_size'} : "";
                    my $ip = $t->{'ip'};
                    print "info:$data_type:$srv_name:$ip:$mc_port:$mc_size\n";
                }
            }
            elsif ( $data_type =~ /^bxSphinx$/ ) {
                foreach my $srv_name ( sort keys %$data_info ) {
                    my $t = $data_info->{$srv_name};
                    my $sphinx_general_port =
                      ( $t->{'sphinx_general_listen'} )
                      ? $t->{'sphinx_general_listen'}
                      : "";
                    my $sphinx_mysql_port =
                      ( $t->{'sphinx_mysqlproto_listen'} )
                      ? $t->{'sphinx_mysqlproto_listen'}
                      : "";
                    my $ip = $t->{'ip'};
                    print
"info:$data_type:$srv_name:$ip:$sphinx_general_port:$sphinx_mysql_port\n";
                }
            }
            elsif ( $data_type =~ /^bxSite$/ ) {
                foreach my $site_name ( sort keys %$data_info ) {
                    my $t = $data_info->{$site_name};
                    my $status =
                      ( $t->{'SiteStatus'} ) ? $t->{'SiteStatus'} : "";
                    my $server_name =
                      $t->{'ServerName'} ? $t->{'ServerName'} : "";
                    my $server_root =
                      $t->{'DocumentRoot'} ? $t->{'DocumentRoot'} : "";
                    my $site_charset =
                      $t->{'SiteCharset'} ? $t->{'SiteCharset'} : "";
                    my $type = $t->{'SiteInstall'} ? $t->{'SiteInstall'} : "";
                    my $db_type = $t->{'DBType'}     ? $t->{'DBType'}     : "";
                    my $db_host = $t->{'DBHost'}     ? $t->{'DBHost'}     : "";
                    my $db_name = $t->{'DBName'}     ? $t->{'DBName'}     : "";
                    my $db_user = $t->{'DBLogin'}    ? $t->{'DBLogin'}    : "";
                    my $db_pass = $t->{'DBPassword'} ? $t->{'DBPassword'} : "";
                    my $db_mycnf = $t->{'DBMyCnf'} ? $t->{'DBMyCnf'} : "";
                    my $db_pass_file = $t->{'DBPasswordFile'} ? $t->{'DBPasswordFile'} : "";
                    if ( ( $db_pass_file ne "" ) || ( $db_mycnf ne "" ) ){
                        $db_pass = "";
                    }
                    my $sh_conn =
                      $t->{'SphinxConnection'} ? $t->{'SphinxConnection'} : "";
                    my $sh_name =
                      $t->{'SphinxIndexName'} ? $t->{'SphinxIndexName'} : "";
                    my $email_addr =
                      $t->{'EmailAddress'} ? $t->{'EmailAddress'} : "";
                    my $email_acc =
                      $t->{'EmailAccount'} ? $t->{'EmailAccount'} : "";
                    my $email_host = $t->{'SMTPHost'} ? $t->{'SMTPHost'} : "";
                    my $email_port = $t->{'SMTPPort'} ? $t->{'SMTPPort'} : "";
                    my $email_user = $t->{'SMTPUser'} ? $t->{'SMTPUser'} : "";
                    my $email_pass =
                      $t->{'SMTPPassword'} ? $t->{'SMTPPassword'} : "";
                    my $email_tls = $t->{'SMTPTLS'}  ? $t->{'SMTPTLS'}  : "";
                    my $cron_task = $t->{'CronTask'} ? $t->{'CronTask'} : "";
                    my $cron_file = $t->{'CronFile'} ? $t->{'CronFile'} : "";
                    my $ssl_status = $t->{'HTTPS'} ? $t->{'HTTPS'} : "disable";
                    my $ssl_cert = $t->{'HTTPSCert'}  ? $t->{'HTTPSCert'}  : "";
                    my $ssl_priv = $t->{'HTTPSPriv'}  ? $t->{'HTTPSPriv'}  : "";
                    my $ssl_file = $t->{'HTTPSConf'}  ? $t->{'HTTPSConf'}  : "";
                    my $b_status = $t->{'BackupTask'} ? $t->{'BackupTask'} : "";
                    my $b_version =
                      $t->{'BackupVersion'} ? $t->{'BackupVersion'} : "";
                    my $b_folder =
                      $t->{'BackupFolder'} ? $t->{'BackupFolder'} : "";
                    my $b_min =
                      $t->{'BackupMinute'} ? $t->{'BackupMinute'} : "";
                    my $b_hour = $t->{'BackupHour'} ? $t->{'BackupHour'} : "";
                    my $b_day  = $t->{'BackupDay'}  ? $t->{'BackupDay'}  : "";
                    my $b_month =
                      $t->{'BackupMonth'} ? $t->{'BackupMonth'} : "";
                    my $b_weekday =
                      $t->{'BackupWeekDay'} ? $t->{'BackupWeekDay'} : "";
                    my $site_message = $t->{'message'} ? $t->{'message'} : "";
                    my $site_error   = $t->{'error'}   ? $t->{'error'}   : "";
                    my $module_cluster =
                        $t->{'module_cluster'}
                      ? $t->{'module_cluster'}
                      : "not_installed";
                    my $module_scale =
                        $t->{'module_scale'}
                      ? $t->{'module_scale'}
                      : "not_installed";
                    my $module_main_version = 
                    $t->{module_main_version}
                    ? $t->{module_main_version}
                    : "";

                    # composite output
                    my $c_status =
                      ( $t->{'CompositeStatus'} =~ /^enable$/ ) ? "Y" : "N";
                    my $c_nginx_status =
                      ( $t->{'CompositeNginx'} =~ /^enable$/ ) ? "Y" : "N";
                    my $c_storage = $t->{'CompositeStorage'};
                    my $c_nginx_map =
                      ( $t->{'CompositeNginxMap'} )
                      ? $t->{'CompositeNginxMap'}
                      : "";
                    my $c_nginx_id =
                      ( $t->{'CompositeNginxID'} )
                      ? $t->{'CompositeNginxID'}
                      : "";
                    my $c_error =
                      ( $t->{'CompositeError'} ) ? $t->{'CompositeError'} : "";

                    # nginx and apache configs
                    my $config_string = "";
                    foreach my $ck (
                        'NginxHTTPConfig', 'NginxHTTPSConfig',
                        'NginxHTTPDir',    'NginxHTTPEDir',
                        'ApacheConf',      'DocumentRoot',
                        'phpSessionDir',   'phpUploadDir',
                        'proxy_ignore_client_abort',
                      )
                    {
                        $config_string .= ":";
                        $config_string .= ( $t->{$ck} ) ? $t->{$ck} : "";
                    }

                    $module_scale =
                      ( $module_scale =~ /^installed$/ ) ? 'Y' : 'N';
                    $module_cluster =
                      ( $module_cluster =~ /^installed$/ ) ? 'Y' : 'N';

                    my $ntlm1 =
                        $t->{'NTLM_bitrixvm_auth_support'}
                      ? $t->{'NTLM_bitrixvm_auth_support'}
                      : "N";
                    my $ntlm2 =
                      $t->{'NTLM_use_ntlm'} ? $t->{'NTLM_use_ntlm'} : "N";
                    my $ntlm_module =
                      $t->{'NTLM_module'} ? $t->{'NTLM_module'} : "N";

                    if ( $hiden == 0 ) {
                        $db_pass    = "*************";
                        $email_pass = $db_pass;
                    }

                    print
"$data_type:general:$site_name:$db_name:$type:$status:$server_name:$server_root:$site_charset:$module_scale:$module_cluster:$c_status:$c_nginx_status:$c_storage:$module_main_version\n";
                    print 
"$data_type:db:$site_name:$db_name:$db_type:$db_host:$db_user:$db_pass:$db_pass_file:$db_mycnf\n";
                    print
"$data_type:search:$site_name:$db_name:$sh_conn:$sh_name\n";
                    print
"$data_type:email:$site_name:$db_name:$email_acc:$email_addr:$email_host:$email_port:$email_user:$email_pass:$email_tls\n";
                    print
"$data_type:cron:$site_name:$db_name:$cron_task:$cron_file\n";
                    print
"$data_type:https:$site_name:$db_name:$ssl_status:$ssl_cert:$ssl_priv:$ssl_file\n";
                    print
"$data_type:backup:$site_name:$db_name:$b_status:$b_version:$b_folder:$b_min:$b_hour:$b_day:$b_month:$b_weekday\n";
                    print
"$data_type:status:$site_name:$db_name:$status:'$site_error|$site_message'\n";
                    print
"$data_type:ntlm:$site_name:$db_name:$ntlm1:$ntlm2:$ntlm_module\n";
                    print "$data_type:modules:$module_cluster:$module_scale:$module_main_version\n";
                    print
"$data_type:composite:$site_name:$c_status:$c_storage:$c_nginx_status:$c_nginx_id:$c_nginx_map\n";

                    if ( $c_error !~ /^$/ ) {
                        print
                          "$data_type:composite_error:$site_name:$c_error\n";
                    }
                    my $cron_status = "disabled";
                    my $cron_services =
                      join( ',', keys %{ $t->{'CronService'} } );
                    if ( $cron_services !~ /^$/ ) {
                        $cron_status = "enabled";
                    }
                    print
"$data_type:cron_services:$site_name:$db_name:$cron_status:$cron_services\n";
                    print "$data_type:configs:$site_name" . "$config_string\n";

                    #print Dumper($data_info);
                }
            }
            elsif ( $data_type =~ /^bxSite::searchBackupForDB$/ ) {
                my $b_status  = $data_info->{'BackupTask'};
                my $b_version = $data_info->{'BackupVersion'};
                my $b_folder  = $data_info->{'BackupFolder'};
                my $b_min     = $data_info->{'BackupMinute'};
                my $b_hour    = $data_info->{'BackupHour'};
                my $b_day     = $data_info->{'BackupDay'};
                my $b_month   = $data_info->{'BackupMonth'};
                my $b_weekday = $data_info->{'BackupWeekDay'};
                print
"$data_type:backup:$b_status:$b_version:$b_folder:$b_min:$b_hour:$b_day:$b_month:$b_weekday\n";

            }
            elsif ( $data_type =~ /^testClusterConfig$/ ) {
                my $kernels_sites    = "";
                my $no_scale_sites   = "";
                my $no_cluster_sites = "";
                my $status_message   = $data_info->{'test_kernels'};
                $status_message .= ':' . $data_info->{'test_without_cluster'};
                $status_message .= ':' . $data_info->{'test_without_scale'};

                if ( $data_info->{'test_kernels'} ) {
                    foreach my $s ( @{ $data_info->{'kernels'} } ) {
                        $kernels_sites .=
                          $s->{'SiteName'} . "=" . $s->{'DocumentRoot'} . ";";
                    }
                }
                if ( $data_info->{'test_without_cluster'} ) {
                    foreach my $s ( @{ $data_info->{'without_cluster'} } ) {
                        $no_cluster_sites .=
                          $s->{'SiteName'} . "=" . $s->{'DocumentRoot'} . ";";
                    }
                }
                if ( $data_info->{'test_without_scale'} ) {
                    foreach my $s ( @{ $data_info->{'without_scale'} } ) {
                        $no_scale_sites .=
                          $s->{'SiteName'} . "=" . $s->{'DocumentRoot'} . ";";
                    }
                }

                print "$data_type:general:$status_message\n";
                print "$data_type:kernels:$kernels_sites\n";
                print "$data_type:cluster:$no_cluster_sites\n";
                print "$data_type:scale:$no_scale_sites\n";

            }
            elsif ( $data_type =~ /^bxMysql$/ ) {
                foreach my $srv_name ( sort keys %$data_info ) {
                    my $t    = $data_info->{$srv_name};
                    my $type = ( $t->{'type'} )? $t->{'type'}: "";
                    my $id   = ( $t->{'id'} ) ? $t->{'id'}: "";
                    my $ip   = $t->{'ip'};
                    my $hostname = $t->{hostname};
                    print "info:$data_type:$srv_name:$ip:$id:$type:$hostname\n";
                }
            }
            elsif ( $data_type =~ /^(options\S+)$/ ) {
                my $options_type = $1;
                my $conf_status  = "";
                my $conf_options = "";
                foreach my $key ( sort keys %$data_info ) {
                    if ( $key =~ /^configure$/ ) {
                        $conf_status = $data_info->{$key};
                    }

                    if ( $key =~ /^options$/ ) {
                        $conf_options = join( ',', @{ $data_info->{$key} } );
                    }
                }
                print "info:$options_type:$conf_status:$conf_options\n";
            }
            elsif ( $data_type =~ /^bx_variables$/ ) {
                foreach my $srv_name ( keys %$data_info ) {
                    my $facts      = $data_info->{$srv_name};
                    my $bx_version = $facts->{'bx_version'};
                    my $bx_pwd     = $facts->{'bx_last_password_change'};
                    my $bx_uid     = $facts->{'bx_bitrix_uid'};
                    my $mysql_version =
                      ( $facts->{'mysql_version'} )
                      ? $facts->{'mysql_version'}
                      : 'not_installed';
                    my $php_version =
                      ( $facts->{'php_version'} )
                      ? $facts->{'php_version'}
                      : 'not_installed';

                    my $os_version =
                      ( $facts->{'os_version'} )
                      ? $facts->{'os_version'}
                      : 'unknown';


                    my $mysql_root_password = $facts->{'mysql_root_password'};
                    my $mysql_root_config   = $facts->{'mysql_root_config'};
                    my $mysql_service_status= $facts->{'mysql_service_status'};
                    my $mysql_package       = $facts->{'mysql_package'};

                    my $sphinx_version      = $facts->{'sphinx_version'};


                    my @addr = grep /addr_/, sort keys %$facts;
                    my $bx_addr = "";

                    foreach my $a (@addr) {
                        my $ip = $facts->{$a};
                        if ( $ip !~ /^none$/ ) {
                            my $int = $a;
                            $int =~ s/^addr_//;
                            $bx_addr .= "$int=$ip,";
                        }
                    }
                    $bx_addr =~ s/,$//;
                    printf "%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s\n",
                    (
                      $data_type, $srv_name, $bx_version, $bx_pwd,
                      $bx_addr, $bx_uid, $mysql_version, $php_version,
                      $mysql_package, $mysql_root_password, 
                      $mysql_root_config, $mysql_service_status,
                      $os_version,$sphinx_version,

                    );
                }
            }
            elsif ( $data_type =~ /^dbs_list$/ ) {
                foreach my $srv_name ( keys %$data_info ) {
                    my $facts = $data_info->{$srv_name};
                    my $dbs = join( ',', @{ $facts->{'dbs_list'} } );
                    print "$data_type:$srv_name:$dbs\n";
                }
            }
            elsif ( $data_type =~ /^pool_interfaces$/ ) {
                foreach my $int ( keys %$data_info ) {
                    print "info:$data_type:$int:", $data_info->{$int}, "\n";
                }
            }
            elsif ( $data_type =~ /^pool_manager$/ ) {
                my $ident   = $data_info->{'ident'};
                my $int     = $data_info->{'interface'};
                my $netaddr = $data_info->{'netaddr'};
                my $type    = $data_info->{'type'};
                my $name    = $data_info->{'fqdn'};
                print "info:$data_type:$int:$netaddr:$ident:$type:$name\n";
            }
            elsif ( $data_type =~ /^pool_interface_revert$/ ) {
                my $int     = $data_info->{'interface'};
                my $netaddr = $data_info->{'netaddr'};
                print "info:$data_type:$int:$netaddr\n";
            }
            elsif ( $data_type =~ /^provider_options$/ ) {
                foreach my $provider_name ( sort keys %$data_info ) {
                    my $provider_status =
                      $data_info->{$provider_name}->{'status'};
                    my $provider_options =
                      $data_info->{$provider_name}->{'options'};
                    my $provider_print_options = "";
                    foreach my $opt_name ( sort keys %$provider_options ) {
                        if ( $provider_options->{$opt_name} == 1 ) {
                            $provider_print_options .= $opt_name . ",";
                        }
                    }
                    $provider_print_options =~ s/,$//;
                    print
"provider:options:$provider_name:$provider_status:$provider_print_options\n";
                }
            }
            elsif ( $data_type =~ /^provider_configs$/ ) {
                foreach my $provider_name ( sort keys %$data_info ) {
                    my $provider_configs =
                      $data_info->{$provider_name}->{'configurations'};
                    my $provider_status =
                      $data_info->{$provider_name}->{'status'};
                    foreach my $pc ( sort { $a->{'id'} <=> $b->{'id'} }
                        @$provider_configs )
                    {
                        my $id   = $pc->{'id'};
                        my $desc = $pc->{'descr'};
                        print
qq(provider:configs:$provider_name:$provider_status:$id:$desc\n);
                    }
                }
            }
            elsif ( $data_type =~ /^provider_order$/ ) {
                foreach my $provider_name ( sort keys %$data_info ) {
                    my $provider_task =
                      $data_info->{$provider_name}->{'task_id'};
                    print qq(provider:order:$provider_name:$provider_task);
                }
            }
            elsif ( $data_type =~ /^providers$/ ) {
                foreach my $provider_name ( sort keys %$data_info ) {
                    my $provider_status =
                      $data_info->{$provider_name}->{'status'};
                    if ($provider_status) {
                        print
                          "provider:status:$provider_name:$provider_status\n";
                    }
                    else {
                        print "provider:status:$provider_name:error\n";
                    }
                }
            }
            elsif ( $data_type =~ /^provider_order_list$/ ) {
                foreach my $provider_name ( sort keys %$data_info ) {
                    my $provider_data = $data_info->{$provider_name};
                    foreach my $task_id ( sort keys %$provider_data ) {
                        my $st    = $provider_data->{$task_id}->{'status'};
                        my $mtime = $provider_data->{$task_id}->{'mtime'};
                        my $error =
                          ( $provider_data->{$task_id}->{'error'} )
                          ? $provider_data->{$task_id}->{'error'}
                          : "";
                        my $msg =
                          ( $provider_data->{$task_id}->{'message'} )
                          ? $provider_data->{$task_id}->{'message'}
                          : "";
                        print
"provider:orders:$provider_name:$task_id:$st:$mtime:$error:$msg\n";
                    }
                }
            }
            elsif ( $data_type =~ /^NTLMStatus$/ ) {
                my $TimeOffset = $data_info->{'TimeOffset'};
                my $BindPath   = $data_info->{'BindPath'};
                my $LDAPServer = $data_info->{'LDAPServer'};
                my $Realm      = $data_info->{'Realm'};
                my $KDCServer  = $data_info->{'KDCServer'};
                my $LDAPPort   = $data_info->{'LDAPPort'};
                my $Status     = $data_info->{'Status'};

                print
"$data_type:$Status:$Realm:$LDAPServer:$LDAPPort:$BindPath:$KDCServer:$TimeOffset\n";
            }
            elsif ( $data_type =~ /^Pool::delete_pool$/ ) {
                my $warnings = $data_info->{'warnings'};
                my $w_cnt    = keys %$warnings;
                print "delete_pool:warnings:$w_cnt\n";
                if ($w_cnt) {
                    my $str = join( "\n",
                        map { "$_: $warnings->{$_}" } keys %$warnings );
                    print $str, "\n";
                }
            }

        }

        # process main info
        if ( $self->message ) { print "message:", $self->message, "\n" }
        if ( $self->status )  { print "status:",  $self->status,  "\n" }
        if ( $self->error )   { print "error:",   $self->error,   "\n" }
    }
    exit $self->error;
}

# print message to file
sub log_data {
    my $self    = shift;
    my $message = shift;

    # format of log message is:
    # [YYYY-MM-DD hh:mm:ss] PID Level MessageText
    my $lt    = strftime "%Y-%m-%d %H:%M:%S", localtime;
    my $pid   = $$;
    my $level = sprintf "CODE_%02d", $self->error;

    open( my $lh, ">>" . $self->logfile )
      or return [ 1, "Can't open file " . $self->logfile . ": $!" ];
    if ( $self->message ) {
        printf $lh "\[%s\] %d %s \"%s\"\n",
          ( $lt, $pid, $level, $self->message );
    }

    if ( $message && $self->debug ) {
        printf $lh "\[%s\] %d %s \"%s\"\n", ( $lt, $pid, $level, $message );
    }

    close $lh;

    return [ 0, 'message saved' ];
}

# return error number from object
sub is_error {
    my $self = shift;
    if ( $self->error > 0 ) {
        $self->log_data;
    }
    return $self->error;
}

# return data object if exist
sub get_data {
    my $self = shift;

    #print Dumper($self);

    my $data = $self->data;
    return $data;
}

# return message object if exist
sub get_message {
    my $self = shift;

    #print Dumper($self);

    my $data = $self->message;
    return $data;
}

1;
