# manage memcached instance
#
package bxMC;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use DBI;
use Output;
use Pool;
use Host;
use bxDaemon;

# basic path for site
has 'config', is => 'ro', default => '/etc/ansible/group_vars/bitrix-memcached.yml';
has 'group', is => 'ro', default => 'memcached';
has 'debug', is => 'rw', default => '0';

# get default options from group
sub groupOptions{
  my $self = shift;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $config = $self->config;

  my $group_options = {
    memcached_port => 11211,
    memcached_size =>  64,
  };

  if (! -f $config){
    return Output->new(
      error => 0,
      data  => [$message_t, $group_options]
    );
  }

  open(my $ch, $config) or 
    return Output->new(error => 1, message => "$message_p: Cannot open $config: !");

  while(<$ch>){
    s/^\s+//; s/\s+$//;
    if (/^([^#:\s]+)\s*:\s*(\S+)$/){
      my $key = $1;
      my $val = $2;
      $val =~ s/^['"]//;
      $val =~ s/['"]$//;
      if (grep /^$key$/, keys %$group_options){
        $group_options->{$key} = $val;
      }
    }
  }
  close $ch;

  return Output->new(
    error => 0,
    data  => [$message_t, $group_options]
  );
}

## get server options 
sub serverOptions{
  my ( $self, $server_name ) = @_;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  # get default group options or options from config
  my $group = $self->group;
  my $get_group_options = $self->groupOptions();
  if ($get_group_options->is_error){
    return $get_group_options;
  }
  my $server_options_info = $get_group_options->get_data;
  my $server_options = $server_options_info->[1];
  #print Dumper($server_options);

  # get all host info
  my $po = Pool->new();
  my $host_info = $po->get_ansible_data($server_name);
  if ( $host_info->is_error ) { return $host_info };
  my $host_data = $host_info->get_data;
  my $server_hash = $host_data->[1];
  
  # parse only memcached info
  # if requst by IP address => we get name
  if ( $server_name =~ /^[\.\d]+$/ ){
    ( $server_name ) = keys %$server_hash;
  }

  # output only memcached option
  if ( grep /^$group$/, keys %{$server_hash->{$server_name}->{'roles'}} ){
    my $mc_port = $server_hash->{$server_name}->{'roles'}->{$group}->{'memcached_port'};
    my $mc_size = $server_hash->{$server_name}->{'roles'}->{$group}->{'memcached_size'};
    if ($mc_port){
      $server_options->{'memcached_port'} = $mc_port;
    }
    if ($mc_size){
      $server_options->{'memcached_size'} = $mc_size;
    }
  }else{
    return Output->new(
      error => 1,
      message => "$message_p: $server_name not in the $group group",
    );
  }

  $server_options->{'ip'} = $server_hash->{$server_name}->{'ip'};

  return Output->new(error=>0, data => [$message_t, {$server_name => $server_options}]);
}

## get current memcached servers list
sub serverList{
  my $self = shift;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;
  my $group = $self->group;

  my $po = Pool->new();
  my $ansible_conf = $po->ansible_conf;
  my $hosts_file = $ansible_conf->{'hosts'};

  my @servers;
  my $section_name = 'bitrix-'.$group;
  my $section_found = 0;
  # parse config and found server list
  open ( my $hh, $hosts_file ) 
    or return Output->new(error => 1, message => "$message_p: Cannot open $hosts_file: $!");
  
  while (<$hh>){
    s/^\s+//; s/\s+$//;
    next if ( /^#/ );
    next if ( /^$/ );
    
    # section found
    if ( /^\[([^\]]+)\]$/ ){ 
      my $s = $1;
      $section_found = 0;
      if ( $s =~ /^$section_name$/ ){
        $section_found = 1;
      }
    }

    # host definition found
    if ( $section_found == 1 &&  /^([^\]\[\s]+)\s+(.+)$/ ){ push @servers, $1; };
  }
  close $hh;

  my $servers_cnt = @servers;
  if ($servers_cnt == 0){
    return Output->new(
      error => 1,
      message => "$message_p: not found memcached servers",
    );
  }

  my $return_data;
  # get options for servers
  foreach my $srv ( @servers ){
    my $get_srv = serverOptions($self, $srv);
    if ( $get_srv->is_error ){ return $get_srv; };
    my $get_srv_data = $get_srv->get_data;
    $return_data->{$srv} = $get_srv_data->[1]->{$srv};
  }

  return Output->new(error=>0, data=>[$message_t, $return_data]);
}

## create memcached service on the server
# input: 
# hostname in pool - host ip address
# *password options mandatory, but can be defined inf config file
sub createMC{
  my ( $self, $server_name ) = @_;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;
  my $group = $self->group;

  ( $server_name ) or 
    return Output->new(error=>1, message=>"$message_p: server_name is is mandatory");
  # test server in the pool
  my $host = Host->new( host =>$server_name );
  my $is_host_in_pool = $host->host_in_pool();
  if ($is_host_in_pool->is_error){
    return Output->new(
      error => 1,
      message => "$message_p: $server_name not in the pool");
  }

  # create ansible task options
  my $po  = Pool->new();
  my $ansData = $po->ansible_conf;
  my $cmd_play = $ansData->{'playbook'};
  my $cmd_conf = catfile($ansData->{'base'},"$group.yml");
  my $cmd_opts = {'memcached_mange' => 'create', 'memcached_server' => $server_name};

  # run as daemon in background
  my $dh = bxDaemon->new( 
    debug => $self->debug,
    task_cmd => qq($cmd_play $cmd_conf) 
  );
  my $created_process = $dh->startAnsibleProcess($group, $cmd_opts);

  return $created_process;  
}

## remove memcached service from server
# input: 
# hostname in pool - host ip address
# *password options mandatory, but can be defined inf config file
sub removeMC{
  my ( $self, $server_name ) = @_;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;
  my $group = $self->group;

  ( $server_name ) or 
    return Output->new(error=>1, message=>"$message_p: server_name is is mandatory");
  # test server in the pool
  my $host = Host->new( host =>$server_name );
  my $is_host_in_pool = $host->host_in_pool($group);
  if ($is_host_in_pool->is_error){
    return Output->new(
      error => 1,
      message => "$message_p: $server_name not in the $group group");
  }

  # create ansible task options
  my $po = Pool->new();
  my $ansData = $po->ansible_conf;
  my $cmd_play = $ansData->{'playbook'};
  my $cmd_conf = catfile($ansData->{'base'},"$group.yml");
  my $cmd_opts = {'memcached_mange' => 'remove', 'memcached_server' => $server_name};

  # run as daemon in background
  my $dh = bxDaemon->new( 
    debug => $self->debug,
    task_cmd => qq($cmd_play $cmd_conf) 
  );
  my $created_process = $dh->startAnsibleProcess($group, $cmd_opts);

  return $created_process;  
}

# update memcached settings on servers
sub updateMC{
  my $self = shift;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $group = $self->group;

  # create ansible task options
  my $po = Pool->new();
  my $ansData = $po->ansible_conf;

  my $cmd_play = $ansData->{'playbook'};
  my $cmd_conf = catfile($ansData->{'base'},"$group.yml");
  my $cmd_opts = {'memcached_mange' => 'update'};

  # run as daemon in background
  my $dh = bxDaemon->new( 
    debug => $self->debug,
    task_cmd => qq($cmd_play $cmd_conf) 
  );
  my $created_process = $dh->startAnsibleProcess('memcached', $cmd_opts);

  return $created_process;  
}

1;
