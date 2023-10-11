package bxInventory;

# 1. fill out information about pool status
# 2. update/delete information for hosts groups and pool itself
#
use Moose;
use Moose::Exporter;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Sys::Hostname;
use Data::Dumper;
use Output;
use JSON;
use YAML::XS qw(DumpFile LoadFile);
use SSHAuthUser;
use bxNetworkNode;

Moose::Exporter->setup_import_methods( as_is =>
      [ 'get_from_yaml', 'generate_password', 'save_to_yaml', 'generate_tmp' ],
);

# ident short name host in config files
has 'status', is => 'ro', lazy => 1, builder => 'get_pool_status';
has 'ansible_dir', is => 'ro', default => '/etc/ansible';
has 'bitrix_dir',  is => 'ro', default => '/opt/webdir';

has 'ansible_options', is => 'ro', lazy => 1, builder => 'get_ansible_options';
has 'bitrix_options',  is => 'ro', lazy => 1, builder => 'get_bitrix_options';

has 'debug', is => 'ro', lazy => 1, default => 0;
has 'logfile', is => 'ro', default => '/opt/webdir/logs/config_pool.debug';

# possible pool statuses
our %POOL_STATUS = (
    0   => "POOL_EXIST",
    2   => "POOL_NOT_EXIST",
    3   => "SSH_KEY_ERROR",
    255 => "ERROR",
);

# status for ansible-roles file which defines client options
our %CLIENT_STATUS = (
    0   => 'EXIST',
    1   => 'NOT_EXIST',
    255 => 'ERROR',
);

# save temporary file in it
our $TMP_DIR = "/tmp";

our $CACHE_DIR = '/opt/webdir/tmp';

sub get_pool_status_types {
    my $self = shift;

    return \%POOL_STATUS;
}

sub get_ansible_options {
    my $self = shift;

    my $ansible_dir = $self->ansible_dir;

    my $ansible_files = {
        base        => $ansible_dir,
        main        => catfile( $ansible_dir, "ansible.cfg" ),
        hosts       => catfile( $ansible_dir, "hosts" ),
        sshkeys     => catfile( $ansible_dir, ".ssh" ),
        group_vars  => catfile( $ansible_dir, "group_vars" ),
        host_vars   => catfile( $ansible_dir, "host_vars" ),
        library     => catfile( $ansible_dir, "library" ),
        playbook    => "/usr/bin/ansible-playbook",
        ansible     => "/usr/bin/ansible",
        client_conf => catfile( $ansible_dir, "ansible-roles" ),
    };

    return $ansible_files;
}

# ansible client options
sub get_bitrix_options {
    my $self = shift;

    my $bitrix_dir = $self->bitrix_dir;

    # default options for bitrix
    my $bitrix_options = {
        base              => $bitrix_dir,
        logs              => catfile( $bitrix_dir, 'logs' ),
        aHostsTemplate    => catfile( $bitrix_dir, 'templates', 'ansible' ),
        aHostsRoles       => [ 'mgmt', 'mysql', 'web', 'memcached', 'sphinx', 'transformer' ],
        aHostsDefaultRole => 'hosts',
        aHostsPrefix      => 'bitrix',
    };

    # create full group name, aka bitrix-mysql
    foreach my $r ( @{ $bitrix_options->{'aHostsRoles'} } ) {
        if ( not defined $bitrix_options->{'aHostsGroups'} ) {
            $bitrix_options->{'aHostsGroups'}->[0] =
              $bitrix_options->{'aHostsPrefix'} . '-' . $r;
        }
        else {
            push @{ $bitrix_options->{'aHostsGroups'} },
              $bitrix_options->{'aHostsPrefix'} . '-' . $r;
        }
    }

    # create full host group name
    $bitrix_options->{'aHostsDefaultGroup'} =
        $bitrix_options->{'aHostsPrefix'} . '-'
      . $bitrix_options->{'aHostsDefaultRole'};

    return $bitrix_options;
}

# generate random number with defined length
sub generate_random {
    my $self = shift;
    my $len  = shift;
    if ( not defined $len ) { $len = 10 }
    my @alphanum = ( 'A' .. 'Z', 'a' .. 'z', 0 .. 9 );
    my $random =
      join( '', map( $alphanum[ rand($#alphanum) ], ( 1 .. $len ) ) );
    return $random;
}

sub generate_password {
    my $password = '';
    my @chars    = (
        "A" .. "Z",
        "a" .. "z",
        "1" .. "9",
        '?', '!', '@', '&', '-', '_', '+', '@', '%', '(', ')', '{', '}',
        '}', '[', ']', '=',
    );
    $password .= $chars[ rand @chars ] for 1 .. 15;
    return $password;
}

sub generate_tmp {
    my ( $prefix, $tmpdir ) = @_;
    if ( not defined $tmpdir ) {
        $tmpdir = $CACHE_DIR;
    }

    $prefix = "site" if ( not defined $prefix );
    mkdir $tmpdir, 0700 if ( !-d $tmpdir );

    my $tmp = File::Temp->new(
        TEMPLATE => "." . $prefix . "XXXXXXXX",
        UNLINK   => 0,
        DIR      => $tmpdir,
    );

    chmod 0600, $tmp->filename;
    return $tmp->filename;
}

# generate host id
sub generate_host_id {
    my $self   = shift;
    my $tm     = time;
    my $random = $self->generate_random;
    return $tm . "_" . $random;
}

# generate host password
sub generate_host_password {
    my $self = shift;
    my $host = shift;
    return $host . "_" . $self->generate_random;
}

# pasre main config and found ssh key
sub ssh_key {
    my $ansible_config = shift;

    my $ssh_key_status = {
        status         => 1,
        status_message => 'NOT_FOUND',
        private        => '',
        public         => '',
    };

    my $ah = undef;
    unless ( open( $ah, '<', $ansible_config ) ) {
        $ssh_key_status->{'status_message'} = "Cannot open $ansible_config: $!";
        return { 'ssh_key' => $ssh_key_status };
    }

    while ( my $line = <$ah> ) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if ( $line =~ /^#/ );
        next if ( $line =~ /^$/ );

        if ( $line =~ /^private_key_file\s*=\s*(\S+)/ ) {
            $ssh_key_status->{'private'} = $1;
        }
    }

    close $ah;
    if ( $ssh_key_status->{'private'} =~ /^$/ ) {
        $ssh_key_status->{'status_message'} =
          "Not found private_key_file option in $ansible_config";
        return $ssh_key_status;
    }

    $ssh_key_status->{'public'} = $ssh_key_status->{'private'} . '.pub';

    foreach my $type ( 'public', 'private' ) {
        if ( !-f $ssh_key_status->{$type} ) {
            $ssh_key_status->{'status_message'} =
              $type . " key doesn't exist" . $ssh_key_status->{$type};
            return $ssh_key_status;
        }
    }

    $ssh_key_status->{'status'}         = 0;
    $ssh_key_status->{'status_message'} = 'FOUND';
    return $ssh_key_status;
}

# return ssh key
sub get_ssh_key {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'Pool';

    # get pool status
    my $pool_status = $self->status;
    if ( $pool_status->{'status'} ) {
        return Output->new(
            error   => $pool_status->{'status'},
            message => $pool_status->{'status_message'}
        );
    }

    if ( $pool_status->{'ssh_key'}->{'status'} ) {
        return Output->new(
            error   => 1,
            message => "$message_p: "
              . $pool_status->{'ssh_key'}->{'status_message'},
        );
    }

    return Output->new(
        error => 0,
        data  => [ 'sshkey', $pool_status->{'ssh_key'}->{'private'} ],
    );
}

sub save_to_yaml {
    my ( $options, $file ) = @_;

    # workaround about numbers
    foreach my $k ( keys %$options ) {
        if ( $options->{$k} =~ /^\d+$/ ) {
            $options->{$k} = $options->{$k} - 0;
        }
    }

    #print Dumper($options);

    my $message_p = ( caller(0) )[3];

    if ( -f $file ) { unlink $file; }

    my $yaml = undef;
    eval { $yaml = DumpFile( $file, $options ); };
    if ($@) {
        return Output->new(
            error   => 1,
            message => "$message_p: $@",
        );
    }

    chmod 0640, $file;
    return Output->new( error => 0, );
}

sub get_from_yaml {
    my ($file) = @_;

    my $message_p = ( caller(0) )[3];
    if ( !-f $file ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Not found $file",
        );
    }

    my $yaml_options = undef;
    eval { $yaml_options = LoadFile($file); };
    if ($@) {
        return Output->new(
            error   => 1,
            message => "$message_p: $@",
        );
    }

    return Output->new(
        error => 0,
        data  => [ 'options', $yaml_options ],
    );
}

# generate hostname
sub generate_inventory_hostname {
    my $self = shift;

    my $pool_status = $self->status;
    my $base_name   = "server";
    my $base_id     = 1;

    my $inventory_hostname = undef;

    until ($inventory_hostname) {
        my $tested_name = $base_name . $base_id;
        if ( grep !/^$tested_name$/, keys %{ $pool_status->{'params'} } ) {
            $inventory_hostname = $tested_name;
        }
        else {
            $base_id++;
        }
    }

    return $inventory_hostname;
}

# create hostname and othe options if it not defined by user
sub test_network_options {
    my ( $self, $host_options ) = @_;

    my $message_p   = ( caller(0) )[3];
    my $message_t   = __PACKAGE__;
    my $pool_status = $self->status;

    ( $host_options->{'netaddr'} || $host_options->{'inventory_hostname'} )
      or return Output->new(
        error   => 1,
        message => "$message_p: options must exist: hostname or netaddress",
      );
    my $ipv4_regexp = '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$';
    my $lo_regexp =
      '(localhost|127\.\d{1,3}\.\d{1,3}.\d{1,3}|localhost\.localdomain)';

    # localhost regexp
    if ( defined $host_options->{'inventory_hostname'}
        && $host_options->{'inventory_hostname'} =~ /^$lo_regexp$/ )
    {
        return Output->new(
            error   => 1,
            message => "$message_p: Could not use "
              . $host_options->{'inventory_hostname'}
              . " in inventory",
        );
    }

    if ( defined $host_options->{'netaddr'}
        && $host_options->{'netaddr'} =~ /^$lo_regexp$/ )
    {
        return Output->new(
            error   => 1,
            message => "$message_p: Could not use "
              . $host_options->{'netaddr'}
              . " in inventory",
        );
    }

    # defined only one options: netaddr or inventory_hostname
    # netaddr = test.bx
    my $tested_ipaddress = undef;
    my $tested_fqdn      = undef;
    if ( defined $host_options->{'netaddr'}
        && not defined $host_options->{'inventory_hostname'} )
    {
        if ( $host_options->{'netaddr'} =~ /$ipv4_regexp/ ) {
            $tested_ipaddress = $host_options->{'netaddr'};
        }
        else {
            $tested_fqdn = $host_options->{'netaddr'};
        }

        # hostname = only name, not ip address
    }
    elsif ( defined $host_options->{'inventory_hostname'}
        && not defined $host_options->{'netaddr'} )
    {
        if ( $host_options->{'inventory_hostname'} =~ /$ipv4_regexp/ ) {
            $tested_ipaddress = $host_options->{'inventory_hostname'};
        }
        else {
            $tested_fqdn = $host_options->{'inventory_hostname'};
        }

        # both options presend and them have the same values
    }
    else {
        if ( $host_options->{'inventory_hostname'} =~
            /^$host_options->{'netaddr'}$/ )
        {
            # fill like ip address
            if ( $host_options->{'inventory_hostname'} =~ /$ipv4_regexp/ ) {
                $tested_ipaddress = $host_options->{'inventory_hostname'};
            }
            else {
                $tested_fqdn = $host_options->{'inventory_hostname'};
            }
        }
    }

    # create options for case if one of the options exists
    # if ip address present in input args
    if ( defined $tested_ipaddress && not defined $tested_fqdn ) {
        my $bxNetwork = bxNetwork->new( netaddr => $tested_ipaddress );
        my $inventory_hostname = $bxNetwork->ptr_lookup($tested_ipaddress);

        # not found PTR record for ip address
        if ( $inventory_hostname =~ /^$/ ) {

            # create it
            $inventory_hostname = $self->generate_inventory_hostname();
        }
        $host_options->{'inventory_hostname'} = $inventory_hostname;
        $host_options->{'netaddr'}            = $tested_ipaddress;

        # if fqdn present in input args
    }
    elsif ( defined $tested_fqdn && not defined $tested_ipaddress ) {
        my $bxNetwork = bxNetwork->new( netaddr => $tested_fqdn );
        my $netaddr = $bxNetwork->a_lookup($tested_fqdn);

        # not found A record for hostname
        if ( $netaddr =~ /^$/ ) {
            return Output->new(
                error => 1,
                message =>
                  "$message_p: not found ip address for inventory_hostname="
                  . $tested_fqdn,
            );
        }
        $host_options->{'inventory_hostname'} = $tested_fqdn;
        $host_options->{'netaddr'}            = $netaddr;

        # if both options present in input args and have different values
    }
    else {
        # if netaddress doesn't contain ip address
        if ( $host_options->{'netaddr'} !~ /$ipv4_regexp/ ) {
            my $bxNetwork =
              bxNetwork->new( netaddr => $host_options->{'netaddr'} );
            my $netaddr = $bxNetwork->a_lookup( $host_options->{'netaddr'} );
            if ( $netaddr =~ /^$/ ) {
                return Output->new(
                    error   => 1,
                    message => "$message_p: not found ip for net address="
                      . $host_options->{'netaddr'},
                );
            }

            #$host_options->{'inventory_hostname'} = $host_options->{'netaddr'};
            $host_options->{'netaddr'} = $netaddr;
        }
    }

    return Output->new(
        error => 0,
        data  => [ 'host', $host_options ],
    );
}

# test input inventory_hostname and ip_address
# Note: test converted options!!!! netaddr is ipaddress (not fqdn name)
sub test_host_inpool {
    my ( $self, $host_options ) = @_;

    my $message_p   = ( caller(0) )[3];
    my $message_t   = __PACKAGE__;
    my $pool_status = $self->status;

    ( $host_options->{'netaddr'} && $host_options->{'inventory_hostname'} )
      or return Output->new(
        error   => 1,
        message => "$message_p: options must exist: hostname and netaddress",
      );

    my $pool               = $self->status;
    my $inventory_hostname = $host_options->{'inventory_hostname'};
    my $netaddr            = $host_options->{'netaddr'};
    my $netaddr_regexp     = $netaddr;
    $netaddr_regexp =~ s|\.|\\.|;

    # test if that name already exist in the pool
    if ( grep /^$inventory_hostname$/, keys %{ $pool_status->{'params'} } ) {
        return Output->new(
            error   => 1,
            message => "$message_p: inventory hostname="
              . $inventory_hostname
              . " exist in the pool",
        );
    }

    ## test if that IP already exist in the pool
    foreach my $ident ( keys %{ $pool_status->{'params'} } ) {
        if ( $pool_status->{'params'}->{$ident}->{'ip'} =~ /^$netaddr_regexp$/ )
        {
            return Output->new(
                error   => 1,
                message => "$message_p: inventory hostname="
                  . $ident
                  . " with ip="
                  . $netaddr
                  . " exist in the pool",
            );
        }
    }

    return Output->new( error => 0 );
}

# update simple config file by new value: riplace or add new
# key = value
# comment char #
sub update_config_file {
    my ( $self, $config_file, $config_options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

# create replace config_options with flag that indicates complete update for options or not
    my $replace_options = {};
    foreach my $k ( keys %$config_options ) {
        $replace_options->{$k} = [ $config_options->{$k}, 0 ];
    }

    # create temporary file name
    # ex. /tmp/253fd257sD_ansible.cfg
    my $replace_random = $self->generate_random();
    my $replace_config =
      catfile( $TMP_DIR, $replace_random . '_' . basename($config_file) );

    # start fill out replace_config file
    open( my $ch, '<', $config_file )
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not open $config_file: $!",
      );

    open( my $rh, '>', $replace_config )
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not open $replace_config: $!",
      );

    # process config file and save updated keys in new one
    while ( my $config_line = <$ch> ) {
        chomp $config_line;
        $config_line =~ s/^\s+//;
        $config_line =~ s/\s+$//;

        # found key = val
        if ( $config_line =~ /^([^#\s]+)\s*=\s*(.+)$/ ) {
            my $key = $1;
            my $val = $2;

            if ( grep /^$key$/, keys %$replace_options ) {
                $replace_options->{$key}->[1] = 1;
                $config_line = "$key = " . $replace_options->{$key}->[0];
            }
        }
        print $rh $config_line, "\n";
    }
    close $ch;

# process replaced options, found that don't changed by pasring origin and add it to new one
    foreach my $key ( keys %$replace_options ) {
        if ( !$replace_options->{$key}->[1] ) {
            print $rh "$key = " . $replace_options->{$key}->[0] . "\n";
            $replace_options->{$key}->[1] = 1;
        }
    }
    close $rh;

    # replace old file by new version
    unlink $config_file
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not unlink $config_file: $!",
      );

    rename $replace_config,
      $config_file
      or return Output->new(
        error => 1,
        message =>
          "$message_p: Could not replace $config_file by $replace_config",
      );

    unlink $replace_config;

    return Output->new(
        error   => 0,
        message => "Update config $config_file",
        data    => [ 'updated', $config_file ],
    );
}

# create config file by template
sub create_hosts_file {
    my ( $self, $manager_options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $hosts_file = $self->ansible_options->{'hosts'};

    open( my $hh, '>', $hosts_file )
      or Output->new(
        error   => 1,
        message => "$message_p: Could not open $hosts_file: $1 ",
      );

    # create host string
    # ex. server1 ansible_connection=local ansible_ssh_host=1.1.1.1
    my $host_str = $manager_options->{'inventory_hostname'};
    foreach my $opt ( grep /^ansible_/, keys %$manager_options ) {
        $host_str .= " $opt=" . $manager_options->{$opt};
    }

    # fill out group with host
    my $default_group = $self->bitrix_options->{'aHostsDefaultGroup'};
    my $roles         = $self->bitrix_options->{'aHostsRoles'};
    my $prefix        = $self->bitrix_options->{'aHostsPrefix'};

    # bitrix-hosts
    print $hh qq|[$default_group]\n|;
    print $hh qq|$host_str\n\n|;

    # additional group
    foreach my $role (@$roles) {
        print $hh qq|[$prefix-$role]\n|;
        if ( grep /^$role$/, @{ $manager_options->{'roles'} } ) {
            print $hh qq|$host_str\n\n|;
        }
        else {
            print $hh qq|\n|;
        }
    }
    close $hh;

    chmod 0640, $hosts_file;

    return Output->new(
        error   => 0,
        message => "$message_p: create $hosts_file"
    );
}

# add hosts to hosts file
sub add_host_to_hosts {
    my ( $self, $host_options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $hosts_file    = $self->ansible_options->{'hosts'};
    my $default_group = $self->bitrix_options->{'aHostsDefaultGroup'};
    my $prefix        = $self->bitrix_options->{'aHostsPrefix'};

    my $replace_random = $self->generate_random();
    my $replace_hosts =
      catfile( $TMP_DIR, $replace_random . '_' . basename($hosts_file) );

    # start fill out replace_config file
    open( my $hh, '<', $hosts_file )
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not open $hosts_file: $!",
      );

    open( my $rh, '>', $replace_hosts )
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not open $replace_hosts: $!",
      );

    # create host string for hosts file
    my $host_str = $host_options->{'inventory_hostname'};
    foreach my $opt ( grep /^ansible_/, keys %$host_options ) {
        $host_str .= " $opt=" . $host_options->{$opt};
    }
    $host_str .= "\n";

    my $specific_roles = keys %{ $host_options->{'roles'} };

    while ( my $line = <$hh> ) {
        print $rh $line;

        # add inventory_hostname to bitrix-hosts group
        if ( ( $line !~ /^#/ ) && ( $line =~ /\[$default_group\]/ ) ) {
            print $rh $host_str;
        }

        # if user defined roles we can add host to specific group
        if (   ($specific_roles)
            && ( $line !~ /^#/ )
            && ( $line =~ /\[${prefix}-(\S+)\]/ ) )
        {
            if ( grep /^$1$/, keys %{ $host_options->{'roles'} } ) {
                print $rh $host_str;
            }
        }
    }

    close $rh;
    close $hh;

    unlink $hosts_file
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not unlink $hosts_file: $!",
      );

    rename $replace_hosts,
      $hosts_file
      or return Output->new(
        error => 1,
        message =>
          "$message_p: Could not replace $hosts_file by $replace_hosts",
      );

    unlink $replace_hosts;
    chmod 0640, $hosts_file;

    return Output->new(
        error   => 0,
        message => "Update hosts $hosts_file",
        data    => [ 'updated', $hosts_file ],
    );
}

# create group_vars files
sub create_group_vars {
    my ( $self, $manager_options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    # create default configs
    my $group_vars_dir = $self->ansible_options->{'group_vars'};
    if ( !-d $group_vars_dir ) {
        mkdir $group_vars_dir,
          0750
          or return Output->new(
            error => 1,
            message =>
              "$message_p: Could not create directory $group_vars_dir: $!"
          );
    }
    my $password = '';

    # present options which should be in configurations files
    my %group_vars_options = (
        'bitrix-mysql' => {
            mysql_logs             => '/var/log/mysql',
            mysql_enable_logs      => 1,
            mysql_enable_slow      => 3,
            mysql_max_binlog_size  => '100M',
            mysql_expire_logs_days => 5,
            mysql_configs          => '/etc/mysql/conf.d',
            master_server          => $manager_options->{'inventory_hostname'},
            master_server_netaddr  => $manager_options->{'ansible_ssh_host'},
            mysql_host             => 'localhost',
            mysql_port             => '3306',
            mysql_socket           => '/var/lib/mysqld/mysqld.sock',
            mysql_last_id          => 1,
            cluster_login          => 'bx_clusteruser',
            replica_login          => 'bx_repluser',
            super_login            => 'bx_super',
            mysql_login            => 'root',
            mysql_password         => $password,
        },
        'bitrix-hosts' => {
            iface                     => '{{ ansible_default_ipv4.interface }}',
            ifaddr                    => '{{ ansible_default_ipv4.address }}',
            monitoring_status         => 'disable',
            monitoring_server_netaddr => $manager_options->{'ansible_ssh_host'},
            monitoring_server     => $manager_options->{'inventory_hostname'},
            cluster_web_configure => 'disable',
            cluster_web_server    => $manager_options->{'inventory_hostname'},
            cluster_web_netaddr   => $manager_options->{'ansible_ssh_host'},
            iptables_configure    => 'enable',
        },
        'bitrix-web' => {
            cluster_mysql_configure => 'disable',
            web_mysql_login         => 'root',
            web_mysql_password      => $password,
            web_mysql_server        => 'localhost',
            web_mysql_port          => 3306,
            web_mysql_socket        => '/var/lib/mysqld/mysqld.sock',
            cluster_web_configure   => 'disable',
            cluster_web_server      => $manager_options->{'inventory_hostname'},
            cluster_web_netaddr     => $manager_options->{'ansible_ssh_host'},
        },
    );

    # prcess manager roles and create files with default settings
    foreach my $role ( @{ $manager_options->{'roles'} } ) {
        if ( grep /^bitrix-$role$/, keys %group_vars_options ) {
            my $config = 'bitrix-' . $role . ".yml";
            my $file = catfile( $group_vars_dir, $config );
            my $save_to_yaml =
              save_to_yaml( $group_vars_options{$config}, $file );
            if ( $save_to_yaml->is_error ) { return $save_to_yaml; }
        }
    }

    return Output->new(
        error   => 0,
        message => "Created files: "
          . join( ', ', keys %group_vars_options ) . ' in '
          . $group_vars_dir,
    );
}

# create host_vars file with inventory_hostname
sub create_host_vars {
    my ( $self, $host_options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    # create default configs
    my $host_vars_dir = $self->ansible_options->{'host_vars'};
    if ( !-d $host_vars_dir ) {
        mkdir $host_vars_dir,
          0750
          or return Output->new(
            error => 1,
            message =>
              "$message_p: Could not create directory $host_vars_dir: $!"
          );
    }

    # present options which should be in configurations files
    my $host_vars_options = {
        host_id     => $host_options->{'host_id'},
        host_pass   => $host_options->{'host_pass'},
        bx_hostname => $host_options->{'inventory_hostname'},
        bx_netaddr  => $host_options->{'ansible_ssh_host'},
        bx_netname  => $host_options->{'netname'},
        ifaddr      => $host_options->{'ansible_ssh_host'},
    };

    if ( defined $host_options->{'interface'} ) {
        $host_vars_options->{'iface'} = $host_options->{'interface'};
    }

    if ( grep /^mysql$/, @{ $host_options->{'roles'} } ) {
        $host_vars_options->{'mysql_replication_role'} = 'master';
        $host_vars_options->{'mysql_serverid'}         = 1;
    }

    my $file = catfile( $host_vars_dir, $host_options->{'inventory_hostname'} );
    my $save_to_yaml = save_to_yaml( $host_vars_options, $file );
    if ( $save_to_yaml->is_error ) { return $save_to_yaml; }

    return Output->new(
        error   => 0,
        message => "Created $file with host settings",
    );
}

# parse config file /etc/ansible/hosts
sub parse_hosts_file {
    my $hosts_file     = shift;
    my $bitrix_options = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $default_status = 2;    # pool configuration does not exist
    my $pool_status    = {
        status         => $default_status,
        status_name    => $POOL_STATUS{$default_status},
        status_message => '',
        params         => {},
    };

    # test file
    if ( !-f $hosts_file ) {
        $pool_status->{'status_message'} =
          'Not found records in ansible config ' . $hosts_file;
        return $pool_status;
    }

    # test data in the file
    my $hh = undef;
    unless ( open( $hh, '<', $hosts_file ) ) {
        $pool_status->{'status_message'} =
          "$message_p: Could not open $hosts_file: $!";
        $pool_status->{'status'}      = 255;
        $pool_status->{'status_name'} = $POOL_STATUS{255};

        return $pool_status;
    }

    # parse config file hosts
    #
    my $group_name      = "";
    my $role_name       = "";
    my $is_bitrix_group = 0;
    my @bitrix_groups   = (
        @{ $bitrix_options->{'aHostsGroups'} },
        $bitrix_options->{'aHostsDefaultGroup'}
    );

    while ( my $line = <$hh> ) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if ( $line =~ /^$/ );
        next if ( $line =~ /^#/ );

        # section found
        # ex. [bitrix-hosts] or [test-group]
        if ( $line =~ /^\[([^\]]+)\]/ ) {
            $group_name = $1;
            if ( grep /^$group_name$/, @bitrix_groups ) {
                $is_bitrix_group = 1;
                $role_name       = $group_name;
                $role_name =~ s/^$bitrix_options->{'aHostsPrefix'}\-//;
            }
            else {
                $is_bitrix_group = 0;
            }
        }

# found definition for host instance
# exclude chars: [,] and space:
# ex. server1 ansible_connection=local ansible_ssh_host=server1.bx ansible_ssh_port=2202 ...
# or (not used in our configuration, don't care)
# ex. server1
        if ( $is_bitrix_group && ( $line =~ /^([^\]\[\s]+)\s+(.+)$/ ) ) {
            my $inv_server = $1;    # aka server1
            my @inv_server_opts =
              split( /\s+/, $2 );    # aka ansible_ssh_host=server1.bx ...

            # hosts group
            # get connection and other options from config file for server
            if ( $group_name =~ /^$bitrix_options->{'aHostsDefaultGroup'}$/ ) {
                my %inv_server_opts;

                # process server options
                foreach my $opt (@inv_server_opts) {
                    my ( $inv_var, $inv_val ) = split( '=', $opt );

                    # delete quotes
                    $inv_var =~ s/^["']//;
                    $inv_var =~ s/["']$//;
                    $inv_val =~ s/^["']//;
                    $inv_val =~ s/["']$//;

                    # delete ansible prefix
                    $inv_var =~ s/^ansible_//;

                    $inv_server_opts{$inv_var} = $inv_val;

                }

                # for compatibility
                # ip address in output
                if ( defined $inv_server_opts{'ssh_host'} ) {
                    $inv_server_opts{'ip'} = $inv_server_opts{'ssh_host'};
                }

                # connection type in the output
                if ( not defined $inv_server_opts{'connection'} ) {
                    $inv_server_opts{'connection'} = 'ssh';
                }

                $inv_server_opts{'inventory_hostname'} = $inv_server;

                $pool_status->{'params'}->{$inv_server} = \%inv_server_opts;

                # roles group
            }
            else {
                $pool_status->{'params'}->{$inv_server}->{'roles'}->{$role_name}
                  = {};
            }
        }
    }
    close $hh;

    # servers count in inventory config
    my $server_count = keys %{ $pool_status->{'params'} };
    if ($server_count) {
        $pool_status->{'status'}      = 0;
        $pool_status->{'status_name'} = $POOL_STATUS{0};
        $pool_status->{'status_message'} =
          "Found bitrix-hosts records in " . $hosts_file;
    }
    else {
        $pool_status->{'status_message'} =
          'Not found records in ansible config ' . $hosts_file;
    }

    return $pool_status;
}

# parse host file, and update inventory information about host
sub parse_host_vars {
    my ( $host_file, $host_info ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    if ( !-f $host_file ) { return $host_info; }
    $host_info->{'config_file'} = $host_file;

    # parse yml config file
    my $get_from_yaml = get_from_yaml($host_file);
    if ( $get_from_yaml->is_error ) {
        $host_info->{'error'} = $get_from_yaml->message;
    }

    # get options from first document
    my $co = $get_from_yaml->data->[1];

    # get host_id for host
    if ( defined $co->{'host_id'} ) {
        $host_info->{'host_id'} = $co->{'host_id'};
    }

    # mysql options
    if ( defined $host_info->{'roles'}->{'mysql'} ) {
        $host_info->{'roles'}->{'mysql'}->{'type'} =
          ( $co->{'mysql_replication_role'} )
          ? $co->{'mysql_replication_role'}
          : 'slave';
        $host_info->{'roles'}->{'mysql'}->{'id'} =
          ( $co->{'mysql_serverid'} ) ? $co->{'mysql_serverid'} : 1;
    }

    # memcached options
    if ( defined $host_info->{'roles'}->{'memcached'} ) {
        $host_info->{'roles'}->{'memcached'}->{'memcached_port'} =
          ( $co->{'memcached_port'} ) ? $co->{'memcached_port'} : 11211;
        $host_info->{'roles'}->{'memcached'}->{'memcached_size'} =
          ( $co->{'memcached_size'} ) ? $co->{'memcached_size'} : 64;
    }

    # searchd (sphinx options)
    if ( defined $host_info->{'roles'}->{'sphinx'} ) {
        $host_info->{'roles'}->{'sphinx'}->{'sphinx_general_listen'} =
          ( $co->{'sphinx_general_listen'} )
          ? $co->{'sphinx_general_listen'}
          : 9312;
        $host_info->{'roles'}->{'sphinx'}->{'sphinx_mysqlproto_listen'} =
          ( $co->{'sphinx_mysqlproto_listen'} )
          ? $co->{'sphinx_mysqlproto_listen'}
          : 9306;
    }

    # transformer
    if ( defined $host_info->{roles}->{transformer} ){
        $host_info->{roles}->{transformer} = {
            transformer_site => ( $co->{transformer_site} ) ? $co->{transformer_site} : '',
            transformer_dir => ( $co->{transformer_dir} ) ? $co->{transformer_dir} : ''
        };
    }

    return $host_info;
}

# parse local client file
# /etc/ansible/ansible-roles
sub parse_local {
    my $local_file = shift;

    my $message_p = ( caller(0) )[3];

    my $local_options = {
        status      => 1,
        status_name => $CLIENT_STATUS{1},
    };

    if ( !-f $local_file ) { return $local_options }

    my $lh = undef;
    unless ( open( $lh, '<', $local_file ) ) {
        $local_options->{'status'}      = 255;
        $local_options->{'status_name'} = $CLIENT_STATUS{255};
        $local_options->{'status_message'} =
          "$message_p: Could not open $local_file: $!";
        return $local_options;
    }

    while ( my $line = <$lh> ) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;

        next if ( $line =~ /^#/ );
        next if ( $line =~ /^$/ );

        if ( $line =~ /^([^=\s]+)\s*=\s*(.+)$/ ) {
            my $o_key = $1;
            my $o_val = $2;

            if ( $o_key =~ /^groups$/ ) {
                my @o_val = split( /\s+/, $o_val );
                $local_options->{$o_key} = \@o_val;
            }
            else {
                $local_options->{$o_key} = $o_val;
            }
        }
    }

    close $lh;

    my $options_count = grep !/^status$/, keys %$local_options;
    if ($options_count) { $local_options->{'status'} = 0; }

    return $local_options;
}

# parse group_vars config file
sub parse_group_vars {
    my ( $group_file, $group_info ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    if ( !-f $group_file ) { return $group_info; }
    $group_info->{'config_file'} = $group_file;

    # parse yml config file
    my $yaml_parser = undef;
    eval { $yaml_parser = YAML::Tiny->read("$group_info"); };
    if ($@) {
        $group_info->{'error'} = "$message_p: $@";
        return $group_info;
    }

    # get options from first document
    my $co = $yaml_parser->[0];

    foreach my $k ( keys %$co ) {
        $group_info->{$k} = $co->{$k};
    }

    return $group_info;
}

# create ssh key
# save it to ssh_dir
# save public key to /root/.ssh/authorized_keys
sub create_ssh_key {
    my ( $self, $ssh_dir, $inventory_hostname ) = @_;

    $inventory_hostname = Pool::esc_chars($inventory_hostname);

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data("$message_p: create ssh key for $inventory_hostname");

    # create ssh directory
    if ( !-d $ssh_dir ) {
        $logOutput->log_data("$message_p: create ssh_dir=$ssh_dir");
        mkdir $ssh_dir,
          0700
          or return Output->new(
            error   => 1,
            message => "$message_p: Could not create $ssh_dir"
          );
    }

    # create ssh files
    my $random_part = $self->generate_random;
    my $sshkey_sec  = catfile( $ssh_dir, "$random_part.bxkey" );
    my $sshkey_pub  = catfile( $ssh_dir, "$random_part.bxkey.pub" );
    unlink $sshkey_sec if ( -f $sshkey_sec );
    unlink $sshkey_pub if ( -f $sshkey_pub );
    my $sshkey_cmd =
qq|ssh-keygen -t rsa -N "" -f $sshkey_sec -C 'ANSIBLE_KEY_$inventory_hostname' >/dev/null 2>&1|;

    system($sshkey_cmd) == 0
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not create $sshkey_sec: $?",
      );
    $logOutput->log_data( "$message_p: create ssh_private=" . $sshkey_sec );

    # read public key
    open( my $sh, '<', $sshkey_pub )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannor read $sshkey_pub: $!",
      );
    my $sshkey_pub_str = <$sh>;
    close $sh;

    # save public key in /root/.ssh/authorized_keys
    my $sshkey_dir = '/root/.ssh';
    my $sshkey_auth = catfile( $sshkey_dir, 'authorized_keys' );
    if ( !-d $sshkey_dir ) {
        mkdir $sshkey_dir,
          0700
          or return Output->new(
            error   => 1,
            message => "$message_p: Could not create $sshkey_dir: $?",
          );
    }

    open( my $ah, '>>', $sshkey_auth )
      or return Output->new(
        error   => 1,
        message => "$message_p: Could not open $sshkey_auth: $!",
      );
    print $ah $sshkey_pub_str;
    close $ah;
    $logOutput->log_data(
        "$message_p: save ssh_public=" . $sshkey_sec . " to $sshkey_auth" );

    return Output->new(
        error => 0,
        data  => [ 'sshkey', $sshkey_sec, $sshkey_pub ],
    );
}

# get invetory information for pool
sub get_pool_status {
    my $self = shift;

    my $ansible_options = $self->ansible_options;
    my $bitrix_options  = $self->bitrix_options;

    # /main inventory file: /etc/ansible/hosts
    my $hosts_file = $ansible_options->{'hosts'};

    # get list of hosts and its roles
    my $pool_status = parse_hosts_file( $hosts_file, $bitrix_options );
    if ( $pool_status->{'status'} ) { return $pool_status; }    # error

    # get ssh key
    my $ansible_config = $ansible_options->{'main'};
    my $ssh_key        = ssh_key($ansible_config);
    $pool_status->{'ssh_key'} = $ssh_key;
    if ( $ssh_key->{'status'} ) {
        $pool_status->{'status'}         = 3;
        $pool_status->{'status_name'}    = $POOL_STATUS{3};
        $pool_status->{'status_message'} = $ssh_key->{'status_message'};
    }

    # get roles informations from personal host files
    foreach my $srv ( keys %{ $pool_status->{'params'} } ) {
        my $host_file = catfile( $ansible_options->{'host_vars'}, $srv );

        $pool_status->{'params'}->{$srv} =
          parse_host_vars( $host_file, $pool_status->{'params'}->{$srv}, );
    }

    return $pool_status;
}

# create new pool with default ansible configuration:
# create ssh-key and groups definition in config file
# INPUT:
# { inventory_hostname => <ident>,
#   interface          => <ident>,
#   roles              => [mgmt, mysql, web]
# }
sub create_pool {
    my ( $self, $host_options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data("$message_p: start process creation of pool");

    my $ansible_options = $self->ansible_options;
    my $local_file      = $ansible_options->{'client_conf'};
    my $pool_status     = $self->status;

    # get client information, in pool or not
    my $local_options = parse_local($local_file);

    # test pool status => some error occure
    if ( $pool_status->{'status'} == 255 ) {
        return Output->new(
            error   => 1,
            message => "$message_p: " . $pool_status->{'status_message'},
        );
    }

    # default variables for manager host
    if ( not defined $host_options->{'inventory_hostname'} ) {
        $host_options->{'inventory_hostname'} = hostname;
    }

    if ( not defined $host_options->{'interface'} ) {
        $host_options->{'interface'} = 'any';
    }

    if ( not defined $host_options->{'roles'} ) {
        $host_options->{'roles'} = [ 'mgmt', 'mysql', 'web', 'hosts' ];
    }

    # system error: open file or smth else
    if ( $local_options->{'status'} == 255 ) {
        return Output->new(
            error   => 1,
            message => $local_options->{'status_message'},
        );
    }

    # found client information, test it is client or manager
    if (   ( $local_options->{'status'} == 0 )
        && ( defined $local_options->{'groups'} ) )
    {
        if ( !( grep /^bitrix-mgmt$/, @{ $local_options->{'groups'} } ) ) {
            return Output->new(
                error   => 1,
                message => "$message_p: inventory_hostname="
                  . $host_options->{'inventory_hostname'}
                  . " is configured as a client; master_server="
                  . $local_options->{'master'},
            );
        }
    }

    # test host options and create additional
    my $net = bxNetworkNode->new(
        manager_hostname  => $host_options->{'inventory_hostname'},
        manager_interface => $host_options->{'interface'},
        debug             => $self->debug,
        logfile           => $self->logfile,
    );
    my $net_options = $net->create_network_options();
    if ( $net_options->is_error ) { return $net_options; }
    my $host_network = $net_options->get_data->[1];

    # update and create some variables
    $host_options->{'inventory_hostname'} = $host_network->{'ident'};
    $host_options->{'interface'}          = $host_network->{'interface'};
    $host_options->{'netaddr'}            = $host_network->{'netaddr'};
    $host_options->{'netname'}            = $host_network->{'fqdn'};

    # main interface replacement for situation with subinterfaces
    $host_options->{'main_interface'} = $host_options->{'interface'};
    $host_options->{'main_interface'} =~ s/^([^:]+):.+$/$1/;

    # create host_id and host_pass
    $host_options->{'host_id'} = $self->generate_host_id;
    $host_options->{'host_pass'} =
      $self->generate_host_password( $host_network->{'ident'} );

    # ansible inventory variables
    $host_options->{'ansible_connection'} = 'local';
    $host_options->{'ansible_ssh_host'}   = $host_network->{'netaddr'};

    $logOutput->log_data(
            "$message_p: manager options are inventory_hostname="
          . $host_options->{'inventory_hostname'}
          . " interface="
          . $host_options->{'interface'}
          . " netaddr="
          . $host_options->{'netaddr'} );

    ###### start creation process for server
    ## 1. create ssh key
    my $ssh_dir = $ansible_options->{'sshkeys'};
    my $ssh_key =
      $self->create_ssh_key( $ssh_dir, $host_options->{'inventory_hostname'} );
    if ( $ssh_key->is_error ) { return $ssh_key; }
    my $sshkey_sec = $ssh_key->get_data->[1];
    my $sshkey_pub = $ssh_key->get_data->[2];

    ## 2. replace ssh private key in the ansible configuration /etc/ansible/ansible.cfg
    my $ansible_main_config = $ansible_options->{'main'};
    my $new_options         = {
        private_key_file      => $sshkey_sec,
        display_skipped_hosts => 'True',
    };

    my $update_main_config =
      $self->update_config_file( $ansible_main_config, $new_options );
    if ( $update_main_config->is_error ) { return $update_main_config; }

    ## 3. create inventory hosts file: /etc/ansible/hosts
    my $create_hosts_file = $self->create_hosts_file($host_options);
    if ( $create_hosts_file->is_error ) { return $create_hosts_file; }

    ## 4. create inventory group file: /etc/ansible/group_vars/bitrix-*
    my $create_group_vars = $self->create_group_vars($host_options);
    if ( $create_group_vars->is_error ) { return $create_group_vars; }

    ## 5. create inventory host file: /etc/ansible/host_vars/$inventory_hostname
    my $create_host_vars = $self->create_host_vars($host_options);
    if ( $create_host_vars->is_error ) { return $create_host_vars; }

    ## 6. start common playbook which configure host settings: hostname, clock and etc.
    my $cmd_playbook = $ansible_options->{'playbook'};
    my $etc_playbook = catfile( $ansible_options->{'base'}, 'common.yml' );
    my $bxDaemon     = bxDaemon->new(
        task_cmd => qq($cmd_playbook  $etc_playbook),
        debug    => $self->debug,
        logfile  => $self->logfile,
    );
    my $startProcess = $bxDaemon->startProcess('common');

    ## 7. create nice looking information about steps:
    my $output_message = "Create manager configuration: ";
    $output_message .=
      " inventory_hostname=" . $host_options->{'inventory_hostname'};
    $output_message .= " interface=" . $host_options->{'interface'};
    $output_message .=
      " netaddress=" . $host_options->{'ansible_ssh_host'} . "\\n";
    $output_message .= " - created ssh provate key $sshkey_sec\\n";
    $output_message .= " - created ansible inventory hosts "
      . $ansible_options->{'hosts'} . "\\n";
    $output_message .=
      " - updated ansible config " . $ansible_options->{'main'} . "\\n";
    $output_message .= "All operations are complete\\n";

    return Output->new(
        error   => 0,
        message => $output_message,
        data    => [ 'sshkey', "$sshkey_sec" ],
    );
}

# add host to inventory
# save ssh key for root user on the host
# create default host configuration (inventory files)
sub add_host_to_inventory {
    my ( $self, $host_options ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $pool_status = $self->status;
    if ( $pool_status->{'status'} ) {
        return Output->new(
            error   => $pool_status->{'status'},
            message => $pool_status->{'status_message'},
        );
    }

    ## 1. create options if it is not defined, or defined incorrectly
    my $test_network_options = $self->test_network_options($host_options);
    if ( $test_network_options->is_error ) { return $test_network_options; }
    $host_options = $test_network_options->data->[1];

    ## 2. test input options
    # 1. localhost and 127.0.0.1 in hostname and address
    # 2. pool doesn't contain address and hostname
    my $test_host_inpool = $self->test_host_inpool($host_options);
    if ( $test_host_inpool->is_error ) { return $test_host_inpool; }

    # 3. create additional host options
    $host_options->{'host_id'} = $self->generate_host_id;
    $host_options->{'host_pass'} =
      $self->generate_host_password( $host_options->{'inventory_hostname'} );
    $host_options->{'ansible_ssh_host'} = $host_options->{'netaddr'};
    $host_options->{'netname'}          = $host_options->{'inventory_hostname'};
    $host_options->{'roles'}            = {};

    ## 4. copy ssh key to host
    if ( defined $host_options->{'root_password'} ) {
        my $sshkey_sec  = $pool_status->{'ssh_key'}->{'private'};
        my $SSHAuthUser = SSHAuthUser->new(
            sship   => $host_options->{'netaddr'},
            sshkey  => $sshkey_sec,
            oldpass => $host_options->{'root_password'},
        );
        my $copy_ssh_key = $SSHAuthUser->copy_ssh_key();
        if ( $copy_ssh_key->is_error ) { return $SSHAuthUser; }
        delete $host_options->{'root_password'};
    }

    ## 5. fill out all options for host
    my $add_host_to_hosts = $self->add_host_to_hosts($host_options);
    if ( $add_host_to_hosts->is_error ) { return $add_host_to_hosts; }

    ## 6. create inventory host file: /etc/ansible/host_vars/$inventory_hostname
    my $create_host_vars = $self->create_host_vars($host_options);
    if ( $create_host_vars->is_error ) { return $create_host_vars; }

    return Output->new(
        error   => 0,
        message => "$message_p: create new host in inventory",
    );
}

# get inventory information
# can be filtered by host option
sub get_inventory_info {
    my ( $self, $filters ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = 'Pool';

    # simple filters,
    # ex.
    #   inventory_hostname => server1
    #   ssh_host           => 1.1.1.1
    # special option:
    #   condition          => OR|AND|NOT (default AND)

    if ( not defined $filters ) {
        $filters = {};
    }

    # get pool status
    my $pool_status = $self->status;
    if ( $pool_status->{'status'} ) {
        return Output->new(
            error   => $pool_status->{'status'},
            message => $pool_status->{'status_message'}
        );
    }

    # filter output
    my $filters_count = grep !/^condition$/, keys %$filters;
    my $pool_filtered = undef;
    if ($filters_count) {
        my $filter_switcher =
          ( $filters->{'condition'} ) ? $filters->{'condition'} : 'AND';
        my $filter_hosts = 0;

        # process host, test it by filter
        foreach my $hi ( keys %{ $pool_status->{'params'} } ) {
            my $filter_match = 0;
            my $host_info    = $pool_status->{'params'}->{$hi};
            foreach my $fk ( grep !/^condition$/, keys %$filters ) {

                # plain text filters
                if ( $fk !~ /^roles$/ ) {
                    if ( $host_info->{$fk} =~ /^($filters->{$fk})$/ ) {
                        $filter_match++;
                    }

                    # filters by role, can contain list of roles
                }
                else {
                    if (
                        grep /^($filters->{$fk})$/,
                        keys %{ $host_info->{'roles'} }
                      )
                    {
                        $filter_match++;
                    }
                }
            }

            # all fileters must match for host
            if (   ( $filter_switcher =~ /^AND$/ )
                && ( $filter_match == $filters_count ) )
            {
                $pool_filtered->{$hi} = $host_info;
                $filter_hosts++;
            }

            # any filter must match for host
            if ( ( $filter_switcher =~ /^OR$/ ) && ( $filter_match > 0 ) ) {
                $pool_filtered->{$hi} = $host_info;
                $filter_hosts++;
            }

            # no one filter must mutch
            if ( ( $filter_switcher =~ /^NOT$/ ) && ( $filter_match == 0 ) ) {
                $pool_filtered->{$hi} = $host_info;
                $filter_hosts++;
            }
        }

        if ( !$filter_hosts ) {
            my $filter_text = "";
            foreach my $fk ( grep !/^condition$/, keys %$filters ) {
                $filter_text .= "$fk=" . $filters->{$fk} . " ";
            }
            $filter_text .= "condition=$filter_switcher";

            return Output->new(
                error   => 3,
                message => "Not found hosts with requested filter $filter_text",
            );
        }

    }
    else {
        $pool_filtered = $pool_status->{'params'};
    }

    return Output->new(
        error => 0,
        data  => [ 'hosts', $pool_filtered, ],
    );
}

# testing current cluster configuration:
#   if usage mysql cluster => exit
#   else                   => run ansible updater for php and mysql by remi rpms
sub update_php {
    my ( $self, $type, $inventory_host ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    if ( not defined $type ) {
        $type = "bx_php_upgrade";
    }

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $pool_status = $self->get_pool_status();

    #print Dumper($pool_status);

    # 1. testing that not mysql cluster is not configured
    my $pool_servers = $pool_status->{'params'};
    my $mysql_count  = 0;
    my @mysql_servers;
    foreach my $srv ( keys %$pool_servers ) {
        if ( defined $pool_servers->{$srv}->{'roles'}->{'mysql'} ) {
            $mysql_count++;
            push @mysql_servers, $srv;
        }
    }

    if ( ( $type eq "bx_php_upgrade" ) && ( $mysql_count > 1 ) ) {

        # phrase_bxInventory_1
        return Output->new(
            error   => 1,
            message => "Found multiple MySQL servers: "
              . join( ',', @mysql_servers )
              . ". Automatic update of the cluster configuration is disabled."
        );
    }

    # 2. start ansible process of updating mysql and php
    my $ansible_options = $self->ansible_options;
    my $cmd_playbook    = $ansible_options->{'playbook'};
    my ( $opts, $startProcess, $etc_playbook, $type_playbook );

    if ( $type =~ /^(bx_php_upgrade|bx_php_upgrade_php56)$/ ) {
        $etc_playbook =
          ( $type eq "bx_php_upgrade_php56" )
          ? catfile( $ansible_options->{'base'}, 'upgrade_php.yml' )
          : catfile( $ansible_options->{'base'}, 'upgrade_mysql_php.yml' );

    }
    elsif ( $type =~ /^(bx_php_upgrade_php7|bx_php_rollback_php7)$/ ) {
        $etc_playbook = catfile( $ansible_options->{'base'}, 'web.yml' );
        $opts =
            ( $type eq 'bx_php_upgrade_php7' )
          ? { manage_web => "upgrade_php", to_php_version => 70 }
          : { manage_web => "downgrade_php", to_php_version => 56 };
    }
    elsif ( $type =~ /^bx_php_upgrade_php(70|71|72|73|74|80|81|82)$/ ) {
        my $version = $1;
        $etc_playbook = catfile( $ansible_options->{'base'}, 'web.yml' );
        $opts = { manage_web => "upgrade_php", to_php_version => $version };
    }
    elsif ( $type =~ /^bx_php_rollback_php(70|71|72|73|74|80|81)$/ ) {
        my $version = $1;
        $etc_playbook = catfile( $ansible_options->{'base'}, 'web.yml' );
        $opts = { manage_web => "downgrade_php", to_php_version => $version };
    }
    if ( defined $inventory_host ) {
        $opts->{updated_hostname} = $inventory_host;
    }

    my $bxDaemon = bxDaemon->new(
        task_cmd => qq($cmd_playbook $etc_playbook),
        debug    => $self->debug,
        logfile  => $self->logfile,
    );
    if ( not defined $opts ) {
        $startProcess = $bxDaemon->startProcess($type);
    }
    else {
        $startProcess = $bxDaemon->startAnsibleProcess( $type, $opts );
    }

    return $startProcess;
}

sub update_mysql {
    my ( $self, $type, $inventory_host ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    if ( not defined $type ) {
        $type = "bx_upgrade_mysql";
    }

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $pool_status = $self->get_pool_status();

    #print Dumper($pool_status);

    # 2. start ansible process of updating mysql and php
    my $ansible_options = $self->ansible_options;
    my $cmd_playbook    = $ansible_options->{'playbook'};
    my ( $opts, $startProcess, $etc_playbook, $type_playbook );
    $etc_playbook = catfile( $ansible_options->{'base'}, 'mysql.yml' );
    if ( $type eq "bx_upgrade_mysql57" ) {

        $opts = { mysql_manage => "upgrade_mysql57" };
    }
    elsif ( $type eq "bx_upgrade_mysql80" ) {
        $opts = { mysql_manage => "upgrade_mysql80" };

    }
    if ( defined $inventory_host ) {
        $opts->{updated_hostname} = $inventory_host;
    }
    #print "$cmd_playbook $etc_playbook\n";

    my $bxDaemon = bxDaemon->new(
        task_cmd => qq($cmd_playbook $etc_playbook),
        debug    => $self->debug,
        logfile  => $self->logfile,
    );
    if ( not defined $opts ) {
        $startProcess = $bxDaemon->startProcess($type);
    }
    else {
        $startProcess = $bxDaemon->startAnsibleProcess( $type, $opts );
    }

    return $startProcess;
}

1;
