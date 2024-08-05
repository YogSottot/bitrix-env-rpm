# main class for manage in the ansible pool
#
package Pool;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use File::Path qw(remove_tree);
use Data::Dumper;
use Sys::Hostname;
use bxNetwork;
use bxNetworkNode;
use bxDaemon;
use Output;
use bxInventory qw( get_from_yaml save_to_yaml);

# main ansible config dir, all hosts and groups file definitions saved here
has 'ansible_dir',  is => 'ro', default => '/etc/ansible';
has 'bitrix_dir',   is => 'ro', default => '/opt/webdir';
has 'ansible_conf', is => 'ro', lazy    => 1, builder => 'set_ansible_conf';
has 'bitrix_conf',  is => 'ro', lazy    => 1, builder => 'set_bitrix_conf';
has 'debug',        is => 'ro', lazy    => 1, default => 0;
has 'logfile',      is => 'ro', default => '/opt/webdir/logs/pool_manage.debug';
has 'bitrix_type',  is => 'ro', default => 'general';

sub esc_chars {
    my $str = shift;
    $str =~ s/([;<>\*\|`&\$!#\(\)\[\]\{\}:'"\\ ])/\\$1/g;
    return $str;
}

# set default config directories
sub set_ansible_conf {
    my $self = shift;

    my $ansible_base = $self->ansible_dir;

    my $ansibleConfigOpt = {
        base        => $ansible_base,
        main        => catfile( $ansible_base, "ansible.cfg" ),
        hosts       => catfile( $ansible_base, "hosts" ),
        sshkeys     => catfile( $ansible_base, ".ssh" ),
        group_vars  => catfile( $ansible_base, "group_vars" ),
        host_vars   => catfile( $ansible_base, "host_vars" ),
        library     => catfile( $ansible_base, "library" ),
        playbook    => "/usr/bin/ansible-playbook",
        ansible     => "/usr/bin/ansible",
        client_conf => catfile( $ansible_base, "ansible-roles" ),
    };

    return $ansibleConfigOpt;
}

sub set_bitrix_conf {
    my $self = shift;

    my $bitrix_base     = $self->bitrix_dir;
    my $bitrixConfigOpt = {
        base           => $bitrix_base,
        logs           => catfile( $bitrix_base, 'logs' ),
        aHostsTemplate => catfile( $bitrix_base, 'templates', 'ansible' ),
        aHostsGroups   => [
            'hosts',     'mgmt',  'web',  'sphinx',
            'memcached', 'mysql', 'push', 'transformer'
        ],
        aHostsDefault => 'hosts',
        aHostsPrefix  => 'bitrix',
    };

    return $bitrixConfigOpt;
}

sub generate_random {
    my $self = shift;
    my $len  = shift;
    if ( not defined $len ) { $len = 10 }
    my @alphanum = ( 'A' .. 'Z', 'a' .. 'z', 0 .. 9 );
    my $random =
      join( '', map( $alphanum[ rand($#alphanum) ], ( 1 .. $len ) ) );
    return $random;
}

sub generate_host_id {
    my $self   = shift;
    my $tm     = time;
    my $random = $self->generate_random;
    return $tm . "_" . $random;
}

sub generate_host_password {
    my $self = shift;
    my $host = shift;
    return $host . "_" . $self->generate_random;
}

sub get_ansible_inventory {
    my ($self) = @_;

    my %ansible_inventory;

    my $ansible_conf = $self->ansible_conf;
    my $bitrix_conf  = $self->bitrix_conf;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    # get info from config file
    open( my $ch, '<', $ansible_conf->{'hosts'} )
      or return Output->new(
        'error'   => '1',
        'message' => "$message_p: Config file "
          . $ansible_conf->{'hosts'}
          . " does not exist"
      );
    my ( $section_name, $is_pool_group );
    my $server_cnt = 0;
    while (<$ch>) {
        chomp;
        next if (/^$/);
        next if (/^#/);
        s/^\s+//;
        s/\s+$//;

        # section found
        if (/^\[([^\]]+)\]/) {
            $section_name = $1;
            if ( $section_name =~ /^$bitrix_conf->{'aHostsPrefix'}\-(\S+)$/ ) {
                $section_name  = $1;
                $is_pool_group = 1;
            }
            else {
                $is_pool_group = 0;
            }
        }

        next if ( $is_pool_group == 0 );

        # option found
        if (/^([^\]\[\s]+)\s+(.+)$/) {
            my $server      = $1;             # vm1
            my $server_opt  = $2;             # ansible_ssh_host=192.168.1.231
            my $server_type = "ssh";          # default connection type
            my $server_ip   = "127.0.0.1";    # default IP address

         # [bitrix-hosts]
         # vm03.ksh.bx ansible_ssh_host=172.17.10.103
         # vm04.ksh.bx   ansible_connection=local ansible_ssh_host=172.17.10.104
            if ( $server_opt =~ /ansible_connection\s*=\s*(\S+)/ ) {
                $server_type = $1;
            }
            if ( $server_opt =~ /ansible_ssh_host\s*=\s*(\S+)/ ) {
                $server_ip = $1;
            }

            # get host connection settings from hosts group
            # and personal settings from host_vars
            if ( $section_name =~ /^$bitrix_conf->{'aHostsDefault'}$/ ) {
                $ansible_inventory{$server} = {
                    'ip'         => $server_ip,
                    'connection' => $server_type,
                    'roles'      => {}
                };

                my $server_file =
                  catfile( $ansible_conf->{'host_vars'}, $server );
                my $get_host_vars = get_from_yaml($server_file);
                if ( $get_host_vars->is_error ) {

                    #return $get_host_vars;
                    $ansible_inventory{$server}->{host_vars}      = {};
                    $ansible_inventory{$server}->{hostname}       = $server;
                    $ansible_inventory{$server}->{host_vars_file} = "";
                    next;
                }

                $server_cnt++;
                my $host_vars = $get_host_vars->data->[1];
                $ansible_inventory{$server}->{host_vars}      = $host_vars;
                $ansible_inventory{$server}->{host_vars_file} = $server_file;
                $ansible_inventory{$server}->{hostname} =
                  ( $host_vars->{bx_host} ) ? $host_vars->{bx_host} : $server;
                $ansible_inventory{$server}->{host_id} = $host_vars->{host_id};
                if (   ( defined $host_vars->{bx_host} )
                    && ( $host_vars->{bx_host} ne $server ) )
                {
                    $ansible_inventory{aliases}->{ $host_vars->{bx_host} } =
                      $server;
                }

            }
            elsif ( $section_name =~
                /^(mysql|memcached|sphinx|push|web|mgmt|transformer)$/ )
            {
                my $group = $1;
                $ansible_inventory{$server}->{groups}->{$group} = 1;
            }
        }
    }
    close $ch;
    if ( $server_cnt == 0 ) {
        return Output->new(
            error   => 2,
            message => "$message_p: Not found records in ansible config "
              . $ansible_conf->{'hosts'},
        );
    }

    foreach my $server ( keys %ansible_inventory ) {
        next if ( $server eq "aliases" );

        #print Dumper($ansible_inventory{$server}->{host_vars});

        #if (grep (/^mysql$/, @{$ansible_inventory->{$server}->{groups}} )){
        if ( exists $ansible_inventory{$server}->{groups}->{mysql} ) {
            $ansible_inventory{$server}->{roles}->{mysql} = {
                type => (
                    $ansible_inventory{$server}->{host_vars}
                      ->{mysql_replication_role}
                  )
                ? $ansible_inventory{$server}->{host_vars}
                  ->{mysql_replication_role}
                : "slave",
                id => (
                    $ansible_inventory{$server}->{host_vars}->{mysql_serverid}
                  ) ? $ansible_inventory{$server}->{host_vars}->{mysql_serverid}
                : 1,
            };
        }

        #if (grep (/^memcached$/, @{$ansible_inventory->{$server}->{groups}} )){
        if ( exists $ansible_inventory{$server}->{groups}->{memcached} ) {

            if ( $ansible_inventory{$server}->{host_vars}->{memcached_socket} )
            {
                $ansible_inventory{$server}->{roles}->{memcached}
                  ->{memcached_socket} =
                  $ansible_inventory{$server}->{host_vars}->{memcached_socket};
            }
            else {
                $ansible_inventory{$server}->{roles}->{memcached}
                  ->{memcached_port} =
                  ( $ansible_inventory{$server}->{host_vars}->{memcached_port} )
                  ? $ansible_inventory{$server}->{host_vars}->{memcached_port}
                  : 11211;
            }
            $ansible_inventory{$server}->{roles}->{memcached}->{memcached_size}
              =
              ( $ansible_inventory{$server}->{host_vars}->{memcached_size} )
              ? $ansible_inventory{$server}->{host_vars}->{memcached_size}
              : 64;
        }

        # searchd
        if ( exists $ansible_inventory{$server}->{groups}->{sphinx} ) {

            $ansible_inventory{$server}->{roles}->{sphinx} = {
                sphinx_general_listen => (
                    $ansible_inventory{$server}->{host_vars}
                      ->{sphinx_general_listen}
                  )
                ? $ansible_inventory{$server}->{host_vars}
                  ->{sphinx_general_listen}
                : 9312,
                sphinx_mysqlproto_listen => (
                    $ansible_inventory{$server}->{host_vars}
                      ->{sphinx_mysqlproto_listen}
                  )
                ? $ansible_inventory{$server}->{host_vars}
                  ->{sphinx_mysqlproto_listen}
                : 9306,
            };
        }

        if ( exists $ansible_inventory{$server}->{groups}->{web} ) {
            $ansible_inventory{$server}->{roles}->{web} = {};
        }
        if ( exists $ansible_inventory{$server}->{groups}->{push} ) {
            $ansible_inventory{$server}->{roles}->{push} = {};
        }
        if ( exists $ansible_inventory{$server}->{groups}->{mgmt} ) {
            $ansible_inventory{$server}->{roles}->{mgmt} = {};
        }
        if ( exists $ansible_inventory{$server}->{groups}->{transformer} ) {


            #$ansible_inventory{$server}->{roles}->{transformer} = {};
            $ansible_inventory{$server}->{roles}->{transformer} = {
                transformer_dir => (
                    $ansible_inventory{$server}->{host_vars}->{transformer_dir}
                  )
                ? $ansible_inventory{$server}->{host_vars}->{transformer_dir}
                : "",
                transformer_site => (
                    $ansible_inventory{$server}->{host_vars}->{transformer_site}
                  )
                ? $ansible_inventory{$server}->{host_vars}->{transformer_site}
                : "",


            };
        }

    }

    return Output->new(
        error => 0,
        data  => [ "inventory", \%ansible_inventory ],
    );
}

# get information about current configuration of ansible pool
sub get_ansible_data {
    my ( $self, $host ) = @_;

    # initilize data
    my $ansible_conf = $self->ansible_conf;
    my $bitrix_conf  = $self->bitrix_conf;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $get_ansible_inventory = $self->get_ansible_inventory();
    return $get_ansible_inventory if ( $get_ansible_inventory->is_error );

    my $ansible_pool_data = $get_ansible_inventory->data->[1];
    delete $ansible_pool_data->{aliases}
      if ( exists $ansible_pool_data->{aliases} );
    if ( defined $host ) {
        foreach my $s ( keys %$ansible_pool_data ) {
            next if ( $host eq $s );
            next if ( $host eq $ansible_pool_data->{$s}->{ip} );
            next if ( $host eq $ansible_pool_data->{$s}->{hostname} );
            delete $ansible_pool_data->{$s};
        }
    }

    return Output->new(
        'error' => 0,
        data    => [ 'hosts', $ansible_pool_data ]
    );

}

sub get_inventory_hostname {
    my ( $self, $host ) = @_;

    if ( not defined $host ) {
        return Output->new(
            error   => 1,
            message => "Option host is mandatory option",
        );
    }

    # initilize data
    my $ansible_conf = $self->ansible_conf;
    my $bitrix_conf  = $self->bitrix_conf;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $get_ansible_inventory = $self->get_ansible_inventory();
    return $get_ansible_inventory if ( $get_ansible_inventory->is_error );

    my $ansible_pool_data = $get_ansible_inventory->data->[1];
    delete $ansible_pool_data->{aliases}
      if ( exists $ansible_pool_data->{aliases} );
    if ( defined $host ) {
        foreach my $s ( keys %$ansible_pool_data ) {
            if (   ( $host eq $s )
                || ( $host eq $ansible_pool_data->{$s}->{ip} )
                || ( $host eq $ansible_pool_data->{$s}->{hostname} ) )
            {
                return Output->new(
                    error => 0,
                    data  => [ 'ident', $s ],
                );
            }
        }
    }

    return Output->new(
        'error'   => 1,
        'message' => "Cannot find host=$host in the pool."
    );

}

sub get_inventory_hostname_at_group {
    my ( $self, $group ) = @_;

    if ( not defined $group ) {
        return Output->new(
            error   => 1,
            message => "Option group is mandatory option",
        );
    }

    # initilize data
    my $ansible_conf = $self->ansible_conf;
    my $bitrix_conf  = $self->bitrix_conf;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $get_ansible_inventory = $self->get_ansible_inventory();
    return $get_ansible_inventory if ( $get_ansible_inventory->is_error );

    my $ansible_pool_data = $get_ansible_inventory->data->[1];
    delete $ansible_pool_data->{aliases}
      if ( exists $ansible_pool_data->{aliases} );
    foreach my $s ( keys %$ansible_pool_data ) {
        next if ( exists $ansible_pool_data->{$s}->{roles}->{$group} );
        delete $ansible_pool_data->{$s};
    }

    return Output->new(
        'error' => 0,
        data    => [ 'hosts', $ansible_pool_data ]
    );

}

# create config file from template
# usage on initial setup
# replace only IP address and HostName by local values
sub create_conf_from_template {
    my $template = shift;    # template file
    my $dest     = shift;    # destination file
    my $master_info =
      shift;    # hash with master info{ netaddr, host, interface, netname }
    my $bitrix_type = shift;
    if ( not defined $bitrix_type ) {
        $bitrix_type = "general";
    }

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $po        = Pool->new();
    my $debug     = $po->debug;
    my $logOutput = Output->new( error => 0, logfile => $po->logfile );

    if ( $bitrix_type ne "general" ) {
        if ( -f $template . "_" . $bitrix_type ) {
            $template .= "_" . $bitrix_type;
        }
    }

    my $netaddr_type = 'ipv4';
    if ( $master_info->{'netaddr'} !~ /^[\d\.]+$/ ) { $netaddr_type = 'fqdn'; }

    # if template not exists - nothing to do
    ( -f $template )
      or return Output->new(
        error   => 0,
        message => "$message_p: not found template. nothing to do!"
      );

    # replace
    open( my $th, '<', "$template" )
      or return Output->new(
        error   => 1,
        message => "$message_p: cannot open $template: $!"
      );
    open( my $dh, '>', "$dest" )
      or return Output->new(
        error   => 1,
        message => "$message_p: cannot open $dest: $!"
      );
    while (<$th>) {
        s/\{\{\s*hostname\s*\}\}/$master_info->{'host'}/g;
        s/\{\{\s*host_ip_address\s*\}\}/$master_info->{'netaddr'}/g;
        s/\{\{\s*host_id\s*\}\}/$master_info->{'host_id'}/g;
        s/\{\{\s*host_pass\s*\}\}/$master_info->{'host_pass'}/g;
        s/\{\{\s*local_interface\s*\}\}/$master_info->{'interface'}/g;
        s/\{\{\s*netaddr_type\s*\}\}/$netaddr_type/g;
        s/\{\{\s*host_netname\s*\}\}/$master_info->{'netname'}/g;

        print $dh $_;
    }

    close $th;
    close $dh;

    # set permission
    chmod 0640, $dest;

    return Output->new(
        error   => 0,
        message => "$message_p: replace in $dest complete"
    );
}

# test ansible clien file
sub test_ansible_client_file {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    # get ansible config options
    my $ansible_conf = $self->ansible_conf;

    # test if host already in the pool
    if ( -f $ansible_conf->{'client_conf'} ) {
        if ($debug) {
            $logOutput->log_data( "$message_p: Found client config "
                  . $ansible_conf->{'client_conf'} );
        }

        open( my $ch, '<', $ansible_conf->{'client_conf'} )
          or return Output->new(
            error   => 2,
            message => "$message_p: Found client "
              . $ansible_conf->{'client_conf'}
              . ", cannot open it: $!",
          );

        my $local_name   = undef;
        my @local_groups = ();
        while (<$ch>) {
            s/^\s+//;
            s/\s\+$//;
            next if (/^#/);
            next if (/^$/);

            if (/^hostname\s*=\s*(\S+)$/) {
                $local_name = $1;
            }

            if (/^groups\s*=(.+)$/) {
                my $groups = $1;
                $groups =~ s/^\s+//;
                $groups =~ s/\s+$//;
                @local_groups = split( /\s+/, $groups );
            }
        }
        close $ch;

        if ( defined $local_name ) {
            if ( grep ( /^bitrix-mgmt$/, @local_groups ) ) {
                return Output->new(
                    error => 1,
                    message =>
                      "$message_p: Bitrix pool already exists in hosts file"
                );
            }
            else {
                return Output->new(
                    error => 1,
                    message =>
                      "$message_p: Host $local_name is configured as a client"
                );
            }
        }
        else {
            return Output->new(
                error   => 0,
                message => "$message_p: file "
                  . $ansible_conf->{'client_conf'}
                  . "doesn't contain pool info",
            );
        }
    }
    else {
        if ($debug) {
            $logOutput->log_data( "$message_p: not found config client "
                  . $ansible_conf->{'client_conf'} );
        }
        return Output->new(
            error   => 0,
            message => "$message_p: not found config client "
              . $ansible_conf->{'client_conf'},
        );
    }
}

# create pool ssh keys and save it for local usage in root directory
sub create_pool_ssh_keys {
    my $self     = shift;
    my $hostname = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $confData  = $self->get_ansible_data();
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    $hostname = Pool::esc_chars($hostname);

    # create directory for ssh keys: /etc/ansible/.ssh
    my $ansible_conf = $self->ansible_conf;

    if ( !-d $ansible_conf->{'sshkeys'} ) {
        mkdir $ansible_conf->{'sshkeys'}
          or return Output->new(
            error   => 2,
            message => "$message_p: Cannot create directory "
              . $ansible_conf->{'sshkeys'}
          );
        chmod 0700, $ansible_conf->{'sshkeys'};
        if ($debug) { $logOutput->log_data("$message_p: create ssh key dir"); }
    }

    # create ssh key file
    my $random     = $self->generate_random;
    my $sshkey_sec = catfile( $ansible_conf->{'sshkeys'}, "$random.bxkey" );
    my $sshkey_pub = catfile( $ansible_conf->{'sshkeys'}, "$random.bxkey.pub" );
    if ( -f $sshkey_sec ) { unlink $sshkey_sec; }
    if ( -f $sshkey_pub ) { unlink $sshkey_pub; }
    if ($debug) { $logOutput->log_data("$message_p: defined ssh key path"); }

    # ssh generate via ssh-keygen (system):
    my $ssh_keygen_cmd =
qq|ssh-keygen -t rsa -N "" -f $sshkey_sec -C "ANSIBLE_KEY_$hostname" >/dev/null 2>&1|;
    system($ssh_keygen_cmd ) == 0
      or return Output->new(
        error   => 3,
        message => "$message_p: Cannot generate sshkey for bitrix pool."
      );
    if ($debug) {
        $logOutput->log_data("$message_p: generate key $sshkey_sec");
    }

    # save public key info to variable
    open( my $sp, '<', $sshkey_pub )
      or return Output->new(
        error   => 1,
        message => "$message_p: cannot open $sshkey_pub: $!",
      );
    my $key_info = "";
    while (<$sp>) { $key_info .= $_; }
    close $sp;

    # install key to local server, on current server
    my $ssh_dir = "/root/.ssh";
    if ( !-d $ssh_dir ) {
        mkdir $ssh_dir;
        chmod 0700, $ssh_dir;
    }

    my $ssh_auth = catfile( $ssh_dir, "authorized_keys" );
    open( my $sa, '>>', $ssh_auth )
      or return Output->new(
        error   => 1,
        message => "$message_p: cannot open $ssh_auth: $!",
      );
    print $sa $key_info;
    close $sa;
    if ($debug) {
        $logOutput->log_data(
            "$message_p: update $ssh_auth by new key $sshkey_pub on localhost");
    }

    return Output->new(
        error => 0,
        data  => [ 'sshkey', $sshkey_sec, $sshkey_pub ],
    );
}

# VMBIRIX 9.0 + ANSIBLE 2.14
# display_skipped_hosts remove at 2.12
#
# save ssh security key to ansible.cfg and set display_skipped_hosts to False
sub update_ansible_main_config {
    my $self       = shift;
    my $sshkey_sec = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $confData  = $self->get_ansible_data();
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    #my $display_skipped_hosts = 'False';

    # replace current ansible private key by new one
    # /etc/ansible/ansible.cfg
    my $ansible_conf = $self->ansible_conf;
    my $work_conf    = $ansible_conf->{'main'};
    my $temp_conf    = $ansible_conf->{'main'} . ".tmp";

    open( my $tmph, '>', $temp_conf )
      or return Output->new(
        error   => 4,
        message => "$message_p: Cannot open temporary $temp_conf: $!"
      );
    open( my $workh, '<', $work_conf )
      or return Output->new(
        error   => 4,
        message => "$message_p: Cannot open config $work_conf: $!"
      );

    my %updates = (
        private_key_file      => [ $sshkey_sec,            0 ],
        #display_skipped_hosts => [ $display_skipped_hosts, 0 ],
    );

    my $new_key_is_set               = 0;
    #my $display_skipped_hosts_is_set = 0;
    while (<$workh>) {
        chomp;
        my $line = $_;
        if ( $line =~ /^#?\s*(\S+)\s*=\s+(\S+)/ ) {
            my $config_key   = $1;
            my $config_value = $2;
            if ( grep /^$config_key$/, keys %updates ) {
                $updates{$config_key}->[1] = 1;
                $line = "$config_key = " . $updates{$config_key}->[0] . "\n";

                if ($debug) {
                    $logOutput->log_data(
"$message_p: replace $config_key, was $config_value set to "
                          . $updates{$config_key}->[0] );
                }
            }
        }
        print $tmph $line, "\n";
    }
    close $tmph;
    close $workh;

    # test if all updates complete
    foreach my $key ( keys %updates ) {
        if ( $updates{$key}->[1] == 0 ) {
            return Output->new(
                error   => 5,
                message => "Cannot replace $key value in $work_conf",
            );
        }
    }

    # delete old config, recreate new one
    unlink $work_conf;
    rename $temp_conf,
      $work_conf
      or return Output->new(
        error   => 6,
        message => "$message_p: Cannot replace work config $work_conf"
      );

    if ($debug) {
        $logOutput->log_data(
            "$message_p: update $work_conf by new private_key_file");
    }

    return Output->new(
        error   => 0,
        message => "update $work_conf",
        data    => [ 'updated', $work_conf ],
    );
}

sub forget_host {
    my ( $self, $host ) = @_;
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );
    my $get_host_ident = $self->get_inventory_hostname($host);
    return $get_host_ident if ( $get_host_ident->is_error );

    my $host_ident = $get_host_ident->data->[1];

    $logOutput->log_data(
        "$message_p: delete server=$host_ident from the config files");

    my $host_file  = catfile( $self->ansible_conf->{'host_vars'}, $host_ident );
    my $hosts_file = $self->{ansible_conf}->{'hosts'};
    my $parse_yaml = get_from_yaml($host_file);
    return $parse_yaml if ( $parse_yaml->is_error );
    my $f_opts = {
        common_manage      => 'forget',
        forget_bx_hostname => $parse_yaml->data->[1]->{bx_hostname},
        forget_bx_netaddr  => $parse_yaml->data->[1]->{bx_netaddr},
        forget_bx_host     => ( $parse_yaml->data->[1]->{bx_host} )
        ? $parse_yaml->data->[1]->{bx_host}
        : $parse_yaml->data->[1]->{bx_hostname},
    };

    my %w_objs;

    # delete records from inventory hosts file
    my $tmp_hosts_file = $hosts_file . ".tmp";
    open( my $hf, '<', $hosts_file )
      or return Output->new(
        error   => 1,
        message => "Cannot open $hosts_file:$!",
      );
    open( my $thf, '>', $tmp_hosts_file )
      or return Output->new(
        error   => 1,
        message => "Cannot open $tmp_hosts_file:$!",
      );
    my $deleted_str = 0;
    while ( my $line = <$hf> ) {
        chomp($line);
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        if ( $line =~ /^$host_ident\s+/ ) {
            $deleted_str++;
            next;
        }
        print $thf "$line\n";
    }
    close $thf;
    close $hf;
    if ($deleted_str) {
        unlink $hosts_file;
        rename $tmp_hosts_file, $hosts_file;
    }
    else {
        $w_objs{$hosts_file} = "Not found record  $host_ident in file";
    }

    # delete host_vars file
    unlink $host_file or $w_objs{$host_file} = "$!";

    # run ansible common script (update iptables and othe configs)
    my $cmd_play = $self->ansible_conf->{'playbook'};
    my $cmd_conf = catfile( $self->ansible_conf->{'base'}, "common.yml" );

    # run as daemon in background
    my $dh = bxDaemon->new( task_cmd => qq($cmd_play  $cmd_conf) );
    my $created_process = $dh->startAnsibleProcess( 'common', $f_opts );

    return Output->new(
        error   => 0,
        message => "Deleting $host_ident configuration files is completed",
        data    => [ $message_p, { 'warnings' => \%w_objs } ]
    );
}

sub change_hostname {
    my ( $self, $host, $hostname ) = @_;
    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );
    my $get_host_ident = $self->get_inventory_hostname($host);
    return $get_host_ident if ( $get_host_ident->is_error );

    my $host_ident = $get_host_ident->data->[1];

    $logOutput->log_data(
"$message_p: change hostname for server=$host_ident from the config files"
    );

    my $host_file = catfile( $self->ansible_conf->{'host_vars'}, $host_ident );
    my $get_host_info = get_from_yaml($host_file);
    if ( $get_host_info->is_error ) {
        return $get_host_info;
    }
    my $host_info = $get_host_info->data->[1];
    $host_info->{bx_host} = $hostname;
    my $save_host_info = save_to_yaml( $host_info, $host_file );
    if ( $save_host_info->is_error ) {
        return $save_host_info;
    }

    # run ansible common script (update iptables and othe configs)
    my $cmd_play = $self->ansible_conf->{'playbook'};
    my $cmd_conf = catfile( $self->ansible_conf->{'base'}, "common.yml" );

    # run as daemon in background
    my $dh = bxDaemon->new( task_cmd => qq($cmd_play  $cmd_conf) );
    my $created_process = $dh->startProcess('common');

    return $created_process;
}

# delete pool
sub delete_pool {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data("$message_p: delete config files for pool");

    # run ansible common script (update iptables and othe configs)
    my $cmd_play = $self->ansible_conf->{'playbook'};
    my $cmd_conf = catfile( $self->ansible_conf->{'base'}, "delete_pool.yml" );

    # run as daemon in background
    my $dh = bxDaemon->new( task_cmd => qq($cmd_play  $cmd_conf) );
    my $created_process = $dh->startProcess('delete_pool');

    return $created_process;
}

# create new pool with default ansible configuration:
# create ssh-key and groups definition in config file
sub create_new_pool {
    my ( $self, $req_hostname, $req_interface, $req_ip ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $confData    = $self->get_ansible_data();
    my $debug       = $self->debug;
    my $bitrix_type = $self->bitrix_type;

    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

# create pool options for first node
#print "Input options: req_hostname=$req_hostname req_interface=$req_interface\n";
    if ( not defined $req_hostname )  { $req_hostname  = hostname; }
    if ( not defined $req_interface ) { $req_interface = 'any'; }
    if ( not defined $req_ip )        { $req_ip        = 'any'; }
    my $net = bxNetworkNode->new(
        manager_interface => $req_interface,
        manager_hostname  => $req_hostname,
        manager_ipaddress => $req_ip,
        debug             => $debug,
    );
    my $net_option = $net->create_network_options();
    if ( $net_option->is_error ) { return $net_option; }
    my $master_data = $net_option->get_data->[1];
    my $host_id     = $self->generate_host_id;
    my $host_pass   = $self->generate_host_password( $master_data->{'ident'} );

    my %master_host = (
        host      => $master_data->{'ident'},
        netaddr   => $master_data->{'netaddr'},
        interface => $master_data->{'interface'},
        netname   => $master_data->{'fqdn'},
        host_id   => $host_id,
        host_pass => $host_pass,
    );

    if ($debug) {
        $logOutput->log_data(
                "$message_p: start create pool; host="
              . $master_host{'host'}
              . " netaddr="
              . $master_host{'netaddr'} . " int="
              . $master_host{'interface'},
        );
    }

    # pool already exists
    if ( $confData->is_error == 0 ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Bitrix pool already exists in hosts file"
        );
    }

    # test client config exist
    my $test_client = $self->test_ansible_client_file;
    if ( $test_client->is_error ) { return $test_client; }

    # create ssh keys
    my $get_sshkeys = $self->create_pool_ssh_keys( $master_host{'host'} );
    if ( $get_sshkeys->is_error ) { return $get_sshkeys; }
    my $sshkey_sec = $get_sshkeys->get_data->[1];

    # update ansible config
    my $update_main_conf = $self->update_ansible_main_config($sshkey_sec);
    if ( $update_main_conf->is_error ) { return $update_main_conf; }
    my $work_conf = $update_main_conf->get_data->[1];

    ### fill out hosts and group information with default data
    my $ansible_conf = $self->ansible_conf;

    # update host interface if subinterface found
    $master_host{'interface'} =~ s/^([^:]+):.+$/$1/;

    # hosts file
    my $hosts_template =
      catfile( $self->bitrix_conf->{'aHostsTemplate'}, "hosts" );
    my $hosts_dest = $ansible_conf->{'hosts'};
    my $replace_hosts =
      create_conf_from_template( $hosts_template, $hosts_dest, \%master_host,
        $bitrix_type );
    if ( $replace_hosts->is_error ) { return $replace_hosts; }
    if ($debug) {
        $logOutput->log_data("$message_p: create new config $hosts_dest");
    }

    # group_vars
    my $roles          = $self->bitrix_conf->{'aHostsGroups'};
    my $template_dir   = $self->bitrix_conf->{'aHostsTemplate'};
    my $prefix         = $self->bitrix_conf->{'aHostsPrefix'};
    my $group_vars_dir = $self->ansible_conf->{'group_vars'};
    if ( !-d $group_vars_dir ) { mkdir $group_vars_dir, 0750 }
    foreach my $group_name (@$roles) {
        my $group_template =
          catfile( $template_dir, $prefix . "-" . $group_name );
        my $group_dest =
          catfile( $group_vars_dir, $prefix . "-" . $group_name . ".yml" );
        my $replace_groups = create_conf_from_template( $group_template,
            $group_dest, \%master_host, $bitrix_type );
        if ( $replace_groups->is_error ) { return $replace_groups; }
        if ($debug) {
            $logOutput->log_data(
"$message_p: create new config $group_dest; with group default options"
            );
        }
    }

    # host_vars
    my $host_vars_dir = $self->ansible_conf->{'host_vars'};
    my $host_template = catfile( $template_dir, 'localhost' );
    my $host_dest     = catfile( $host_vars_dir, $master_host{'host'} );
    if ( !-d $host_vars_dir ) { mkdir $host_vars_dir, 0750 }
    my $replace_host =
      create_conf_from_template( $host_template, $host_dest, \%master_host,
        $bitrix_type );
    if ($debug) {
        $logOutput->log_data(
            "$message_p: create config $host_dest; deafult master host settings"
        );
    }

    if ( $replace_host->is_error ) { return $replace_host; }

    # run common playbook
    # set network, time
    # run monitor playbook with new option setings
    my $cmd_play = $ansible_conf->{'playbook'};
    my $cmd_conf = catfile( $ansible_conf->{'base'}, "common.yml" );

    # run as daemon in background
    my $dh = bxDaemon->new( task_cmd => qq($cmd_play  $cmd_conf) );
    my $created_process = $dh->startProcess('common');
    my ($task_id) =
      grep { !/^task_name$/ } keys %{ $created_process->{data}->[1] };

    my $task_pid    = $created_process->{$task_id}->{pid};
    my $task_status = $created_process->{$task_id}->{status};

    if ($debug) {
        $logOutput->log_data(
            "$message_p: configure common options on master server "
              . $master_host{'host'} );
    }

    # output info
    my $output_message = "Created manager configuration for";
    $output_message .= " identifier=" . $master_host{'host'};
    $output_message .= " interface=" . $master_host{'interface'};
    $output_message .= " netaddress=" . $master_host{'netaddr'} . "\\n";
    $output_message .= "Created sshkey - $sshkey_sec\\n";
    $output_message .= "Update config file $work_conf\\n";
    $output_message .= "Created pool configuration in $hosts_dest\\n";
    $output_message .= "Run configuration pool job task_id=$task_id\\n";
    $output_message .= "All operations complete\\n";

    return Output->new(
        error   => 0,
        message => $output_message,
        data    => [ "sshkey", "$sshkey_sec" ]
    );
}

# get path to ssh key
sub get_ssh_key {
    my $self = shift;

    my $message_p = "BX_KEY_VIEW";

    my $ansData     = $self->ansible_conf;
    my $ansMainConf = $ansData->{'main'};

    # search key in the config file
    open( my $ch, '<', $ansMainConf )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open main config $ansMainConf: $!"
      );
    my $ansSshKey = "";
    while (<$ch>) {
        if (/private_key_file\s*=\s*(\S+)/) { $ansSshKey = $1; }
    }
    close $ch;

    if ( !$ansSshKey ) {
        return Output->new(
            error => 2,
            message =>
"$message_p: Not found private_key_file derictive in config $ansMainConf"
        );
    }

    my $ansSshKeyPub = $ansSshKey . ".pub";
    if ( !-f $ansSshKey ) {
        return Output->new(
            error => 3,
            message =>
"$message_p: Record private_key_file found in the config, but private key does not exist in FS"
        );
    }
    if ( !-f $ansSshKeyPub ) {
        return Output->new(
            error => 3,
            message =>
"$message_p: Record private_key_file found in the config, but public key does not exist in FS"
        );
    }

    return Output->new( data => [ 'sshkey', $ansSshKey ] );
}

## update group information
# updated files in /etc/ansible/group_vars
# options = { group => groupname, opt1 => val1, opt2 => undef }
# opt2 - will be deleted, opt1 - updated|added
sub update_group_vars {
    my ( $self, $options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $bxData  = $self->bitrix_conf;
    my $ansData = $self->ansible_conf;

    #print "bxPool: ".print Dumper($options);
    if ( not defined $options->{"group"} ) {
        return Output->new(
            error   => 1,
            message => "$message_p: group name is mandatory option"
        );
    }

    my $group = $options->{'group'};
    $group =~ s/^["']//;
    $group =~ s/['"]$//;

    my $group_vars_path = catfile( $ansData->{'group_vars'},
        $bxData->{'aHostsPrefix'} . '-' . $group . '.yml' );
    my $group_vars_temp = $group_vars_path . ".tmp";
    if ( !-f $group_vars_path ) {
        return Output->new(
            error   => 1,
            message => "$message_p: not found group_vars in $group_vars_path"
        );
    }
    $logOutput->log_data(
"$message_p: start update inventory group=$group inventory file=$group_vars_path"
    );

    # get current data from yaml
    my $get_inventory = get_from_yaml($group_vars_path);
    if ( $get_inventory->is_error ) {
        return $get_inventory;
    }
    my $inventory_data = $get_inventory->data->[1];

    #print Dumper($inventory_data);

    # create conf data for update
    my $updates      = 0;
    my $deletes      = 0;
    my $made_updates = 0;
    my $made_deletes = 0;
    foreach my $key ( keys %$options ) {

        # skip handler options
        next if ( $key =~ /^(group|state)$/ );

        # convert password_file to value which will be saved in the inventory
        if ( $key =~ /^(\S+_password)_file$/ ) {
            my $inventory_key = $1;
            open( my $h, '<', $options->{$key} )
              or return Output->new(
                error   => 1,
                message => "$message_p: cannot open file=" . $options->{$key},
              );
            my $value = <$h>;
            chomp($value);
            close $h;

            if (   ( defined $inventory_data->{$inventory_key} )
                && ( $inventory_data->{$inventory_key} eq $value ) )
            {
                next;
            }

            $inventory_data->{$inventory_key} = $value;
            $updates++;
        }
        else {
            # key=value
            if ( defined $options->{$key} ) {
                if ( defined $inventory_data->{$key} ) {
                    if ( $inventory_data->{$key} ne $options->{$key} ) {
                        $inventory_data->{$key} = $options->{$key};
                        $updates++;
                    }
                }
                else {
                    $inventory_data->{$key} = $options->{$key};
                    $updates++;
                }
            }

            # key
            else {
                if ( defined $inventory_data->{$key} ) {
                    delete $inventory_data->{$key};
                    $deletes++;
                }
            }

        }

    }

    $logOutput->log_data("$message_p: found updates=$updates deletes=$deletes");

    # update values or create new
    my $save_inventory = save_to_yaml( $inventory_data, $group_vars_temp );
    if ( $save_inventory->is_error ) {
        return $save_inventory;
    }

    # rewrite origin file
    unlink $group_vars_path;
    rename $group_vars_temp, $group_vars_path;
    chmod 0640, $group_vars_path;

    return Output->new(
        error   => 0,
        message => "$message_p: "
          . "File=$group_vars_path is modified; updates=$updates deletes=$deletes",
        data => [
            "$message_p",
            {
                updates => $updates,
                deletes => $deletes,
                file    => $group_vars_path
            }
        ]
    );
}

# get current status of monitoring; enable or disable
sub monitorStatus {
    my $self = shift;

    my $message_p = "BX_MONITOR";

    my $ansData = $self->ansible_conf;
    my $bxData  = $self->bitrix_conf;

    #print "ansData => ",Dumper($ansData);
    #print "bxData => ",Dumper($bxData);
    #
    my $monitoring_opt = {
        'monitoring_status'         => '',
        'monitoring_server'         => '',
        'monitoring_file'           => 0,
        'monitoring_server_netaddr' => '',
    };

# config file that contains monitoring information: /etc/ansible/group_vars/bitrix-hosts
    my $cfg_file = catfile( $ansData->{'group_vars'},
        $bxData->{'aHostsPrefix'} . '-' . $bxData->{'aHostsDefault'} . '.yml' );
    if ( !-f $cfg_file ) {
        return Output->new(
            error => 0,
            data  => [ 'monitor', $monitoring_opt ]
        );
    }

    open( my $ch, '<', $cfg_file )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $cfg_file"
      );

    $monitoring_opt->{'monitoring_file'} = $cfg_file;
    while (<$ch>) {
        chomp;
        s/^\s+//;
        s/\s+$//;
        next if (/^#/);
        next if (/^$/);

        if (
/^(monitoring_status|monitoring_server|monitoring_server_netaddr)\s*:\s*(\S+)$/
          )
        {
            $monitoring_opt->{$1} = $2;
        }
    }

    close $ch;

    # if status wanted
    return Output->new( error => 0, data => [ 'monitor', $monitoring_opt ] );
}

# change config file for monitoring
# run playbook monitor.yml
sub monitorEnable {
    my ( $self, $opts ) = @_;

    my $ansData = $self->ansible_conf;

    # run monitor playbook with new option setings
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "monitor.yml" );
    my $cmd_opts = { 'monitoring_status' => 'enable' };

    # update ansible playbook options by optionals
    foreach my $o ( keys %$opts ) {
        if ( defined $opts->{$o} ) {
            $cmd_opts->{$o} = $opts->{$o};
        }
    }

    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'monitor', $cmd_opts );

    return $created_process;
}

# update monitoring configuration for new host
sub monitorUpdate {
    my $self = shift;

    # get current status of monitoring
    my $monitor = $self->monitorStatus;
    if ( $monitor->is_error ) {
        return Output->new( error => 1, message => "Cannot read config file" );
    }
    my $monitor_status = $monitor->get_data;

    # current monitoring options
    my $mon_file = $monitor_status->[1]->{'monitoring_file'};
    my $mon_flag = $monitor_status->[1]->{'monitoring_status'};
    my $mon_mgmt = $monitor_status->[1]->{'monitoring_server'};

    my $ansData = $self->ansible_conf;
    my $bxData  = $self->bitrix_conf;

    # existen or not file with default value for group bitrix-hosts
    if ( !$mon_file ) {
        return Output->new(
            error   => 1,
            message => "Monitoring does not enable"
        );
    }

    # run monitor playbook with new option setings
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "monitor.yml" );
    my $cmd_opts = { 'monitoring_status' => 'update' };

    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'monitor', $cmd_opts );

    return $created_process;
}

# change config file for monitoring
# run playbook monitor.yml
sub monitorDisable {
    my $self = shift;

    # get current status of monitoring
    my $monitor = $self->monitorStatus;
    if ( $monitor->is_error ) {
        return Output->new( error => 1, message => "Cannot read config file" );
    }
    my $monitor_status = $monitor->get_data;

    # current monitoring options
    my $mon_file = $monitor_status->[1]->{'monitoring_file'};
    my $mon_flag = $monitor_status->[1]->{'monitoring_status'};
    my $mon_mgmt = $monitor_status->[1]->{'monitoring_server'};

    my $ansData = $self->ansible_conf;
    my $bxData  = $self->bitrix_conf;

    # existen or not file with default value for group bitrix-hosts
    if ( !$mon_file ) {
        return Output->new(
            error   => 1,
            message => "Monitoring does not enable"
        );
    }

    # if
    if ( $mon_flag =~ /^enable$/ ) {

        # run monitor playbook with new option setings
        my $cmd_play = $ansData->{'playbook'};
        my $cmd_conf = catfile( $ansData->{'base'}, "monitor.yml" );
        my $cmd_opts = { 'monitoring_status' => 'disable' };

        # run as daemon in background
        my $dh = bxDaemon->new(
            debug    => $self->debug,
            task_cmd => qq($cmd_play $cmd_conf)
        );
        my $created_process = $dh->startAnsibleProcess( 'monitor', $cmd_opts );

        return $created_process;

    }
    else {
        return Output->new(
            error   => 0,
            message => "Monitoring already disable for pool",
            data    => $monitor_status
        );
    }

}

sub update_pool {
    my ( $self, $host, $type ) = @_;
    if ( not defined $type ) {
        $type = "bx_update";
    }

    my ($host_ident);

    if ( defined $host ) {
        my $get_host_ident = $self->get_inventory_hostname($host);
        return $get_host_ident if ( $get_host_ident->is_error );
        $host_ident = $get_host_ident->data->[1];
    }

    # initilize data
    my $ansData = $self->ansible_conf;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "common.yml" );
    my $cmd_opts = { 'common_manage' => 'version' };
    if ( $type eq "bx_upgrade" ) {
        $cmd_opts->{common_manage} = "update_packages";
    }

    if ( defined $host_ident ) {
        $cmd_opts->{'common_server'} = $host_ident;
    }

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'update', $cmd_opts );

    return $created_process;
}

sub reboot_server {
    my ( $self, $host ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $get_host_ident = $self->get_inventory_hostname($host);
    return $get_host_ident if ( $get_host_ident->is_error );

    my $host_ident = $get_host_ident->data->[1];

    # initilize data
    my $ansData = $self->ansible_conf;

    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "common.yml" );
    my $cmd_opts = {
        'common_manage' => 'reboot',
        'common_server' => $host_ident
    };

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'reboot', $cmd_opts );

    return $created_process;
}

sub timezone_in_the_pool {
    my $self   = shift;
    my $tz     = shift;    # timezone, default: UTC
    my $tz_php = shift;    # update php settings or not

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    if ( not defined $tz_php ) {
        $tz_php = 1;
    }

    my $update_str = 'update';
    if ( $tz_php == 0 ) { $update_str = 'not_update'; }

    if ( not defined $tz ) {
        $tz = 'UTC';
    }

    # initilize data
    my $ansData = $self->ansible_conf;

    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "configure_timezone.yml" );
    my $cmd_opts = {
        'timezone_string'     => $tz,
        'timezone_php_update' => $update_str
    };

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'configure_tz', $cmd_opts );

    return $created_process;
}

sub password_on_server {
    my ( $self, $host, $user, $password ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    if (   ( not defined $host )
        || ( not defined $user )
        || ( not defined $password ) )
    {
        return Output->new(
            error   => 1,
            message => "$message_p: host, user, password is mandatory",
        );
    }
    my $get_host_ident = $self->get_inventory_hostname($host);
    return $get_host_ident if ( $get_host_ident->is_error );

    my $host_ident = $get_host_ident->data->[1];

    # create file for chpasswd
    my $tmp_dir = "/opt/webdir/keys";
    if ( !-d $tmp_dir ) {
        mkdir $tmp_dir;
        chmod 0700, $tmp_dir;
    }
    my $tmp_file = catfile( $tmp_dir, "source_passwd" );
    open( my $th, '>', $tmp_file )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $tmp_file: $!",
      );
    print $th "$user:$password";
    close $th;

    # initilize data
    my $ansData = $self->ansible_conf;

    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "common.yml" );
    my $cmd_opts = {
        'common_manage' => 'password',
        'common_server' => $host_ident,
        'common_file'   => $tmp_file,
        'common_user'   => $user
    };

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'password', $cmd_opts );

    return $created_process;
}

sub deleteSSHFinger {
    my $self   = shift;
    my $old_ip = shift;    # old
    my $new_ip = shift;

    $old_ip = Pool::esc_chars($old_ip);
    $new_ip = Pool::esc_chars($new_ip);

    my $cmd = qq(ssh-keygen -R $old_ip >/dev/null 2>&1);
    system($cmd) == 0
      or return Output->new(
        error   => 1,
        message => "cmd \`ssh-keygen -R $old_ip\` return error: $!",
      );

    # get new rsa key
    my $cmd_gen =
      qq(ssh-keyscan -t rsa $new_ip >> /root/.ssh/known_hosts 2>/dev/null);
    system($cmd_gen) == 0
      or return Output->new(
        error   => 1,
        message => "cmd \`ssh-keyscan -t rsa $new_ip\` return error: $!",
      );

    return Output->new(
        error   => 0,
        message => "known_hosts updated",
    );
}

sub replaceIPAddress {
    my $self      = shift;
    my $old_value = shift;
    my $new_value = shift;
    my $config    = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    $old_value =~ s/\./\\\./g;
    my $tmp_config = $config . ".tmp";
    open( my $tmp, '>', "$tmp_config" )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $tmp_config: $!",
      );

    open( my $cfg, '<', "$config" )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $config: $!",
      );
    while (<$cfg>) {
        s/\b$old_value\b/$new_value/;
        print $tmp $_;
    }

    close $cfg;
    close $tmp;
    unlink $config;
    rename $tmp_config, $config;
    chmod 0640, $config;
    return Output->new(
        error   => 0,
        message => "$message_p: $config updated\n"
    );

}

sub update_network {
    my ( $self, $host, $new_ip ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug     = $self->debug;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );
    my $get_host_ident = $self->get_inventory_hostname($host);
    return $get_host_ident if ( $get_host_ident->is_error );
    my $host_ident = $get_host_ident->data->[1];

    if ( not defined $new_ip ) {
        return Output->new(
            error   => 1,
            message => "New IP is mandatory option",
        );
    }

    $logOutput->log_data(
"$message_p: change ipaddress for server=$host_ident from the config files"
    );

    # get current ip address
    my $current_ip    = undef;
    my $get_all_hosts = $self->get_ansible_data();
    if ( $get_all_hosts->is_error ) { return $get_all_hosts }
    my $data_all_hosts = $get_all_hosts->get_data->[1];

    # found host by host_id
    foreach my $ident ( keys %$data_all_hosts ) {
        if ( $ident eq $host_ident ) {
            $current_ip = $data_all_hosts->{$ident}->{'ip'};
        }
    }

    if ( !$current_ip ) {
        return Output->new(
            error   => 1,
            message => "$message_p: not found host host_id=$host_ident"
        );
    }

    $logOutput->log_data(
        "$message_p: ident=$host_ident old_ip=$current_ip new_ip=$new_ip");

   # have to update all group settings and personal host settings and hosts file
   # after that start common task + monitor task
    my $ansible_conf  = $self->ansible_conf;
    my $bitrix_conf   = $self->bitrix_conf;
    my @updated_files = (
        $ansible_conf->{'hosts'},
        catfile( $ansible_conf->{'host_vars'}, $host_ident ),
    );
    foreach my $role ( @{ $bitrix_conf->{'aHostsGroups'} } ) {
        my $fp = catfile( $ansible_conf->{'group_vars'},
            $bitrix_conf->{'aHostsPrefix'} . '-' . $role . '.yml' );
        if ( -f $fp ) {
            push @updated_files, $fp;
        }
    }

    # update files
    #print "$current_ip, $new_ip\n";
    foreach my $cfg (@updated_files) {
        my $update_file = $self->replaceIPAddress( $current_ip, $new_ip, $cfg );
        if ( $update_file->is_error ) { return $update_file; }
    }

    # update ssh keygen
    my $update_known_hosts = $self->deleteSSHFinger( $current_ip, $new_ip );

    # start ansible common play
    my $cmd_play        = $ansible_conf->{'playbook'};
    my $cmd_conf        = catfile( $ansible_conf->{'base'}, "monitor.yml" );
    my $dh              = bxDaemon->new( task_cmd => qq($cmd_play  $cmd_conf) );
    my $created_process = $dh->startProcess( "network_" . $host_ident );
    return $created_process;

    #return Output->new(error=>0, message => "123");
}

# by unique host_id
sub UpdateHostNetwork {
    my ( $self, $host_id, $new_ip ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug     = $self->debug;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug,
    );

    if ( not defined $host_id ) {
        return Output->new(
            error   => 1,
            message => "Host identifier is mandatory option",
        );
    }

    if ( not defined $new_ip ) {
        return Output->new(
            error   => 1,
            message => "New IP is mandatory option",
        );
    }

    $logOutput->log_data(
"$message_p: change ipaddress for host_id=$host_id from the config files"
    );

    # get current ip address
    my $current_ip    = undef;
    my $host_ident    = undef;
    my $get_all_hosts = $self->get_ansible_data();
    if ( $get_all_hosts->is_error ) { return $get_all_hosts }
    my $data_all_hosts = $get_all_hosts->get_data->[1];

    # found host by host_id
    foreach my $ident ( keys %$data_all_hosts ) {
        if ( $data_all_hosts->{$ident}->{host_id} eq $host_id ) {
            $current_ip = $data_all_hosts->{$ident}->{'ip'};
            $host_ident = $ident;
        }
    }

    if ( !$current_ip ) {
        return Output->new(
            error   => 1,
            message => "$message_p: not found host host_id=$host_id"
        );
    }

    $logOutput->log_data(
        "$message_p: ident=$host_ident old_ip=$current_ip new_ip=$new_ip");

    return $self->update_network( $host_ident, $new_ip );
}

sub TestHostNetwork {
    my $self = shift;
    my $log  = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    if ( !$log ) {
        return Output->new(
            error   => 1,
            message => "$message_p: path to log file is mandatory",
        );
    }
    if ($debug) {
        $logOutput->log_data("$message_p: parse log=$log");
    }

    my %updates;
    my $updates_count = 0;
    open( my $lh, '<', $log )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $log: $!",
      );
    while (<$lh>) {

# 172.17.0.120 - 1402045968_VzleKSTLPM [06/Jun/2014:13:24:56 +0400 - -] 200 "GET /change?client_ip=172.17.0.120 HTTP/1.1" 0 "-" "Updater/www2" "-"
        chomp;
        next if (/^$/);
        if (/^([\d\.]+)\s+\S+\s+(\S+)\s+\[[^\]]+\]\s+(\d+)\s+"([^"]+)"/) {
            my $remote_address = $1;
            my $host_id        = $2;
            my $code           = $3;
            my $request        = $4;
            my ( $type, $uri, $proto ) = split( /\s+/, $request );
            my $client_ip = "";
            if ( $uri =~ m:^/change\?client_ip=([\d\.]+)$: ) {
                $client_ip = $1;
            }

            #print "$remote_address:$host_id:$code:$client_ip\n";
            if ( $code == 200 && $client_ip !~ /^$/ ) {
                $updates{$host_id} = $remote_address;
                $updates_count++;
            }
        }
    }
    close $lh;

    if ( $updates_count > 0 ) {
        foreach my $host_id ( keys %updates ) {
            my $update_host =
              $self->UpdateHostNetwork( $host_id, $updates{$host_id} );
            if ( $update_host->is_error ) { return $update_host; }
        }
    }
    else {
        return Output->new(
            error   => 0,
            message => "$message_p: Not found request for network update",
        );
    }

    unlink $log;
    my $nginx_cmd = "/sbin/service nginx reload 1>/dev/null 2>/dev/null";
    system($nginx_cmd) == 0
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot reload nginx service",
      );

    my $update_servers = join( ', ', keys %updates );
    return Output->new(
        error   => 0,
        message => "$message_p: Updated $update_servers",
    );
}

sub beta_version {
    my $self = shift;
    my $type = shift;

    $type = "disable" if ( not defined $type );

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    # initilize data
    my $ansData = $self->ansible_conf;

    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "beta_version.yml" );
    my $cmd_opts = { 'beta_version' => $type };

    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'beta_version', $cmd_opts );

    return $created_process;
}

1;
