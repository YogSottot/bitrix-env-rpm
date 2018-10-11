# manage mysql instance
#
package bxMysql;
use strict;
use warnings;
use Moose;
use Moose::Exporter;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use DBI;
use Output;
use Pool;
use bxDaemon;
use bxSites;
use bxInventory qw( get_from_yaml generate_password generate_tmp);

# basic path for site
has 'config', is => 'ro', default => '/etc/ansible/group_vars/bitrix-mysql.yml';
has 'options',
  is      => 'rw',
  lazy    => 1,
  builder => 'parseConfig';    # union cmd options and config options
has 'cmd', is => 'ro';                   # cmd options for mysql group
has 'debug', is => 'ro', default => 0;
has 'logfile', is => 'ro', default => '/opt/webdir/logs/bxMysql.debug';

our $CACHE_DIR = '/opt/webdir/tmp';

## get options from ConfigFile
# if opt found in cmd than use it, else use from config
# /etc/ansible/group_vars/bitrix-mysql:
sub parseConfig {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $cmdOpt    = $self->cmd;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    my $mysql_options = {
        master_server    => undef,
        mysql_last_id    => 1,
        mysql_host       => 'localhost',
        mysql_port       => 3306,
        mysql_socket     => '/var/lib/mysqld/mysqld.sock',
        cluster_login    => 'bx_clusteruser',
        cluster_password => undef,
        replica_login    => 'bx_repluser',
        replica_password => undef,
    };

    # parse ansible inventory file
    my $rtn = get_from_yaml( $self->config );
    if ( $rtn->is_error ) {
        die $rtn->message;
    }
    my $opts = $rtn->data->[1];
    foreach my $k ( keys %$mysql_options ) {
        if ( ( defined $opts->{$k} ) && ( $opts->{$k} !~ /^\s*$/ ) ) {
            $mysql_options->{$k} = $opts->{$k};
        }
    }

    # parse command line opts
    $logOutput->log_data("$message_p: parse cmd options");
    foreach my $key ( keys %$mysql_options ) {
        if ( defined $cmdOpt->{$key} && not defined $mysql_options->{$key} ) {
            $mysql_options->{$key} = $cmdOpt->{$key};
            $mysql_options->{$key} =~ s/^['"]//;
            $mysql_options->{$key} =~ s/['"]$//;
            $logOutput->log_data( "$message_p:  replace opt by cmd line $key="
                  . $cmdOpt->{$key} );
        }
    }

    # return
    $logOutput->log_data(
        "$message_p: finished processing config=" . $self->config );
    return $mysql_options;
}

## get server options
sub serverOptions {
    my ( $self, $server_name ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    # return value
    my $server_options = {
        type => '',
        id   => '',
        ip   => '',
    };

    # get all host info
    my $po = Pool->new();
    my $get_host_ident = $po->get_inventory_hostname($server_name);
    return $get_host_ident if ($get_host_ident->is_error);
    my $host_ident = $get_host_ident->data->[1];

    #print "hostname: $server_name\n";
    my $host_info = $po->get_ansible_data($host_ident);
    if ( $host_info->is_error ) { return $host_info }
    my $host_data   = $host_info->get_data;
    my $server_hash = $host_data->[1];

    # output only mysql option
    if ( grep /^mysql$/, keys %{ $server_hash->{$host_ident}->{'roles'} } ) {
        $server_options->{type} =
          $server_hash->{$host_ident}->{'roles'}->{'mysql'}->{'type'};
        $server_options->{id} =
          $server_hash->{$host_ident}->{'roles'}->{'mysql'}->{'id'};
        $server_options->{'mysql'} = 1;
    }else{

        $server_options->{'mysql'} = 0;
    }

    $server_options->{'ip'} = $server_hash->{$host_ident}->{'ip'};
    $server_options->{bx_netaddr} = $server_hash->{$host_ident}->{host_vars}->{bx_netaddr};

    return Output->new(
        error => 0,
        data  => [ $message_t, { $host_ident => $server_options } ]
    );
}

## get current mysql servers list
sub serverList {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $po           = Pool->new();
    my $get_mysql_servers = $po->get_inventory_hostname_at_group('mysql');
    return $get_mysql_servers if ($get_mysql_servers->is_error);
    my $mysql_servers = $get_mysql_servers->data->[1];
    foreach my $srv (keys %$mysql_servers){
        $mysql_servers->{$srv}->{id} = $mysql_servers->{$srv}->{roles}->{mysql}->{id};
        $mysql_servers->{$srv}->{type} = $mysql_servers->{$srv}->{roles}->{mysql}->{type};
        $mysql_servers->{$srv}->{bx_netaddr} = $mysql_servers->{$srv}->{host_vars}->{bx_netaddr};
        delete $mysql_servers->{$srv}->{roles};
        delete $mysql_servers->{$srv}->{host_vars};
    }

    if ($debug) {
        $logOutput->log_data(
            "$message_p: finished processing for mysql servers");
    }
    return Output->new( 
        error => 0, 
        data => [ $message_t, $mysql_servers ] );
}

sub mysql_cluster_options {
    my ( $self ) = @_;


    my $mysql_options = $self->options;

    # test mysql options - generate passwords
    foreach my $key ( keys %$mysql_options ) {
        if ( $key =~ /^(cluster|replica)_password$/ ) {
            # generate passwords
            if ( not defined $mysql_options->{$key} ) {
                my $pass = generate_password();
                my $tmp = generate_tmp($key, $CACHE_DIR);
                open (my $h, ">", $tmp)
                    or die "Cannot open temporary file=$tmp: $!";
                print $h $pass;
                close $h;
                $mysql_options->{$key."_file"} = $tmp;
            }
            # old version push password like plain text, new one like a file
            # make differences
            else {
                if ( -f $mysql_options->{$key} ){
                    $mysql_options->{$key.'_file'} = $mysql_options->{$key};
                }else{
                    my $tmp = generate_tmp($key, $CACHE_DIR);
                    open (my $h, ">", $tmp)
                        or die "Cannot open temporary file=$tmp: $!";
                    print $h $mysql_options->{$key};
                    close $h;
                    $mysql_options->{$key."_file"} = $tmp;
                }
            }
            delete $mysql_options->{$key};
        }
        elsif ( $key =~ /^(mysql_host|mysql_port|mysql_socket)$/ ){
            delete  $mysql_options->{$key};
        }
    }

    return $mysql_options;
}

## create mysql slave
# input:
# hostname in pool - host ip address
# *password options mandatory, but can be defined inf config file
sub slave {
    my ( $self, $server_name ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    # test host options
    my $get_host_options = $self->serverOptions($server_name);
    return $get_host_options if ($get_host_options->is_error);
    my $host_options = $get_host_options->data->[1];
    my ($host_ident) = keys %$host_options;
    if ($host_options->{$host_ident}->{mysql}){
        return Output->new(
            error => 1,
            message => "$message_p: $server_name already configured as "
            . $host_options->{$host_ident}->{type}
            . "mysql server",
        )
    }

    # test sites; scale and cluster modules + number kernels sites
    my $bxSites           = bxSites->new();
    my $testClusterConfig = $bxSites->testClusterConfig();
    my $test_data         = $testClusterConfig->get_data->[1];
    if (   ( $test_data->{'test_kernels'} > 1 )
        || ( $test_data->{'test_without_scale'} > 0 )
        || ( $test_data->{'test_without_cluster'} > 0 ) )
    {
        return Output->new(
            error => 1,
            message =>
"$message_p: Found conditions when mysql-cluster configuration is disabled",
        );
    }

    # test if password options exists
    my $mysql_options = $self->mysql_cluster_options;
    $mysql_options->{'group'} = 'mysql';

    # create ansible task options
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "mysql.yml" );
    $mysql_options->{mysql_manage} = "add";
    $mysql_options->{slave_server} = $host_ident;
    
    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'mysql', $mysql_options );

    return $created_process;
}

sub remove {
    my ( $self, $server_name ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    # test host options
    my $get_host_options = $self->serverOptions($server_name);
    return $get_host_options if ($get_host_options->is_error);
    my $host_options = $get_host_options->data->[1];
    my ($host_ident) = keys %$host_options;
    if ($host_options->{$host_ident}->{mysql} && 
        $host_options->{$host_ident}->{type} eq 'master'){
        return Output->new(
            error => 1,
            message => "$message_p: $server_name is "
            . $host_options->{$host_ident}->{type}
            . "mysql server; Cannot remove it.",
        )
    }elsif (!$host_options->{$host_ident}->{mysql}){
        return Output->new(
            error => 1,
            message => "$message_p: $server_name isn't mysql server ",
        )
    }

    # create ansible task options
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "mysql.yml" );
    my $mysql_options->{mysql_manage} = "remove";
    $mysql_options->{slave_server} = $host_ident;
    
    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'mysql', $mysql_options );

    return $created_process;
}

sub master {
    my ( $self, $server_name ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    # test host options
    my $get_host_options = $self->serverOptions($server_name);
    return $get_host_options if ($get_host_options->is_error);
    my $host_options = $get_host_options->data->[1];
    my ($host_ident) = keys %$host_options;
    if ($host_options->{$host_ident}->{mysql} && 
        $host_options->{$host_ident}->{type} eq 'master'){
        return Output->new(
            error => 1,
            message => "$message_p: $server_name is "
            . $host_options->{$host_ident}->{type}
            . "mysql server; Nothing to do.",
        )
    }elsif (!$host_options->{$host_ident}->{mysql}){
        return Output->new(
            error => 1,
            message => "$message_p: $server_name isn't mysql server ",
        )
    }

    # create ansible task options
    my $po       = Pool->new();
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "mysql.yml" );
    my $mysql_options->{mysql_manage} = "master";
    $mysql_options->{slave_server} = $host_ident;
    $mysql_options->{serverid} = $host_options->{$host_ident}->{id};
    
    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'mysql', $mysql_options );

    return $created_process;
}




# update mysql settings on servers
sub update {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $logOutput = Output->new(
        error   => 0,
        logfile => $self->logfile,
        debug   => $self->debug
    );

    $logOutput->log_data("$message_p: start update mysqls in the pool");

    # test if password options exists
    my $mysql_options = $self->mysql_cluster_options;
    $mysql_options->{'group'} = 'mysql';
    $mysql_options->{mysql_manage} = 'update';

    # create ansible task options
    my $po      = Pool->new();
    my $ansData = $po->ansible_conf;

    # update group configuration by value that user defined
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "mysql.yml" );

    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'mysql', $mysql_options );
    return $created_process;
}

sub password {
    my ( $self, $server_name, $mysql_manage ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );
    my $cmd       = $self->cmd;
    
    # get all host info
    my $po = Pool->new();
    my $get_host_ident = $po->get_inventory_hostname($server_name);
    return $get_host_ident if ($get_host_ident->is_error);
    my $host_ident = $get_host_ident->data->[1];
  
    ( $cmd->{password_file} )
      or return Output->new(
        error    => 1,
        messages => "$message_p: password_file is mandatory option"
      );

    $logOutput->log_data("$message_p: $mysql_manage on server=$server_name");

    # test if server name doesn't exist in configuration
    my $get_server_opt = serverOptions( $self, $host_ident );
    if ( $get_server_opt->is_error ) { return $get_server_opt }
    if ($debug) { $logOutput->log_data("$message_p: get server options"); }

# create ansible task options
# ansible-playbook  /etc/ansible/mysql.yml -vvv -e "replica_password=XXXXXXXX cluster_password=XXXXXXXXX "
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "mysql.yml" );
    my $cmd_opts = {
        'mysql_manage'  => $mysql_manage,
        'slave_server'  => $host_ident,
        'password_file' => $cmd->{password_file},
    };

    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'mysql', $cmd_opts );

    return $created_process;
}

sub manage {
    my ( $self, $server_name, $mysql_manage ) = @_;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );
    my $cmd       = $self->cmd;

    my $po = Pool->new();
    my $get_host_ident = $po->get_inventory_hostname($server_name);
    return $get_host_ident if ($get_host_ident->is_error);
    my $host_ident = $get_host_ident->data->[1];
 
    $logOutput->log_data("$message_p: $mysql_manage on server=$server_name");

    # test if server name doesn't exist in configuration
    my $get_server_opt = serverOptions( $self, $host_ident );
    if ( $get_server_opt->is_error ) { return $get_server_opt }
    if ($debug) { $logOutput->log_data("$message_p: get server options"); }

# create ansible task options
# ansible-playbook  /etc/ansible/mysql.yml -vvv -e "replica_password=XXXXXXXX cluster_password=XXXXXXXXX "
    my $ansData  = $po->ansible_conf;
    my $cmd_play = $ansData->{'playbook'};
    my $cmd_conf = catfile( $ansData->{'base'}, "mysql.yml" );
    my $cmd_opts = {
        'mysql_manage' => $mysql_manage,
        'slave_server' => $host_ident,
    };

    # run as daemon in background
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( 'mysql', $cmd_opts );

    return $created_process;
}

1;
