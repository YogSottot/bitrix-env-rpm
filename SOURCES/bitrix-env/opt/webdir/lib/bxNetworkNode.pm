# main class for manage in the ansible pool
#
package bxNetworkNode;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use Sys::Hostname;
use IO::Interface::Simple;
use bxNetwork;
use Pool;
use Output;

# network scheme fro localhost
has 'localhost_network' => (
  is => 'ro',
  lazy => 1,
  builder => 'get_localhost_network',
);

has 'manager_interface' => (
  is => 'ro',
  isa => 'Str',
  default => 'any',
);

has 'manager_ipaddress' => (
  is => 'ro',
  isa => 'Str',
  default => 'any',
);

has 'manager_hostname' => (
  is => 'ro',
  isa => 'Str',
  lazy => 1,
  builder => 'get_localhost_hostname',
);

has 'debug' => (
  is => 'ro',
  isa => 'Int',
  default => 0,
);

has 'logfile' => (
  is => 'ro',
  isa => 'Str',
  default => '/opt/webdir/logs/manager_network.debug',
);

# list all running interfaces on localhost
sub get_localhost_network {
  my $self = shift;
  
  my $message_p = (caller(0))[3];

  my %localhost_network = ();
  my $exclude_address = qq(127\.0\.0\.1);

  # get interfaces list
  my @interfaces = IO::Interface::Simple->interfaces;

  my $interfaces_count = 0;
  foreach my $int (sort @interfaces){
    if ($int->is_running && $int !~ /^lo/){
      if($int->address !~ /^($exclude_address)$/){
        $localhost_network{$int} = $int->address;
        $interfaces_count++;
      }
    }
  }

  return  [$interfaces_count, \%localhost_network],
}

# return hostname for localhost
# default hostname, but it can create it if used something incorrect (ex, localhost)
sub get_localhost_hostname {
  my $self = shift;

  my $hostname = hostname;
  my $generated_hostname = qw(localhost|localhost.localdomain|127.0.0.1);

  if ($hostname =~ /^($generated_hostname)$/){
    return "server1";
  }else{
    return $hostname;
  }
}

# replace localhost by generated hostname value
sub test_localhost_hostname{
  my $name = shift;

  my $generated_hostname = qw(localhost|localhost.localdomain|127.0.0.1);

  if ($name =~ /^($generated_hostname)$/){
    return "server1";
  }else{
    return $name;
  }
}

# test A record for hostname
# convert hostname to ip addressi ( if complete we have right hash with:
# short_name => { int => fqdn_name }
# it is primary settings for pool manager
sub hostname_to_ip {
  my $self = shift;
  my $hostname = $self->manager_hostname;

  # we new its generated name, doesn't check
  my $ip = '';
  if ($hostname !~ /^server1$/){
    my $net = bxNetwork->new(host=>$hostname);
    $ip  = $net->a_lookup($hostname);
  }

  return $ip;
}

# test PTR record for defined interface
# convert ip address to hostname, use this hostname
# short_name => { int => fqdn_name }
sub ip_to_hostname {
  my $self = shift;
  my $interface = $self->manager_interface;
  my $network   = $self->localhost_network;

  if($network->[0] == 0){
    return [undef, undef];
  }

  # use first one
  while ($interface =~ /^any$/){
    foreach my $int (sort keys %{$network->[1]}){
      $interface = $int;
    }
  }

  my $ip_address = $network->[1]->{$interface};
  my $net = bxNetwork->new(netaddr=>$ip_address);
  my $return = [$interface, undef];
  $return->[1] = $net->ptr_lookup($ip_address);

  return $return;
}

# return
# network_name => { int => ip_address|fqdn }
sub create_network_options {
  my $self                = shift;

  my $message_p = (caller(0))[3];

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);


  my $interface = $self->manager_interface; # interface that used for pool, == any in default
  my $hostname  = $self->manager_hostname;  # hostname, create hostname if not passed
  if ($debug){
    $logOutput->log_data(
      "$message_p: input options interface=$interface hostname=$hostname"
    );
  }
  $hostname  = test_localhost_hostname($hostname);
  my $local_net = $self->localhost_network; # return { int => ip_address }
  if ($local_net->[0] == 0){
    if ($debug){
      $logOutput->log_data(
        "$message_p: not found running interfaces on host $hostname"
      );
    }
    return Output->new(
      error => 1,
      message => "$message_p: not found running interfaces on host $hostname",
    );
  }
  
  # test if input interface is correct
  my $is_correct_interface = 0;   # interface that user defined exist on the server
  if ($interface !~ /^any$/){
    $is_correct_interface = grep /^$interface$/, (keys %{$local_net->[1]} );
    if ($debug){
      $logOutput->log_data(
        "$message_p: not found running interface=$interface on host $hostname"
      );
    }
 
    if ($is_correct_interface == 0){
      return Output->new(
        error => 1,
        message => "$message_p: not found running interface=$interface on host $hostname",
      );
    }
  }

  # 1. try to convert hostname to ip_address
  my $ip_address = $self->hostname_to_ip;
  if($ip_address !~ /^$/){
    if ($debug){
      $logOutput->log_data(
        "$message_p: found A record for hostname=$hostname; test ipaddress=$ip_address"
      );
    }
 
    # test all intrefaces or one
    my $is_local_interface = 0;     # local interface contain ip address for hostname
    my $is_the_input_intreface = 0; # interface that contain ip address it user defined for pool

    my $ip_address_int = "";
    # test if server contain ip address  for hostname
    foreach my $int (keys %{$local_net->[1]}){
      if ($local_net->[1]->{$int} =~ /^$ip_address$/){
        # input interfaces is owner for ip address
        if($interface !~ /^any$/ && $int =~ /^$interface$/){
          $is_local_interface = 1;
          $is_the_input_intreface = 1;
          $ip_address_int = $int;
        # input interface is not owner for ip address
        }elsif($interface !~ /^any$/ && $int !~ /^$interface$/){
          $is_local_interface = 1;
          $ip_address_int = $int;
        # input interface is owner for ip address and user doesn't define prefered eth for pool
        }elsif($interface =~ /^any$/){
          $is_local_interface = 1;
          $is_the_input_intreface = 1;
          $ip_address_int = $int;
        }
      }
    }
    if ($debug){
      $logOutput->log_data(
        "$message_p: is_local_interface=$is_local_interface is_the_input_intreface=$is_the_input_intreface ip_address_int=$ip_address_int"
      );
    }
    my $ident = $hostname;
    #$ident =~ s/^([^\.]+)\..+$/$1/;
    # use the same interface that hold DNS name
    if ($is_local_interface == 1 && $is_the_input_intreface == 1){
      if ($debug){
        $logOutput->log_data(
          "$message_p: return A: \{$ident => \{$ip_address_int => $hostname\}\}"
        );
      }
 
      return Output->new(
        error => 0,
        data  => ['pool_manager', { 
		        ident     => $ident, 
            interface => $ip_address_int, 
            netaddr   => $local_net->[1]->{$ip_address_int},
            fqdn      => $hostname,
            type      => 'A' 
          }
        ],
      );
    # use user defined intreface, but it doesn't have ip address with dns name
    }elsif($is_local_interface ==1 && $is_the_input_intreface == 0){
      if ($debug){
        $logOutput->log_data(
          "$message_p: return SIMPLE: \{$ident => \{$interface => ".$local_net->[1]->{$interface}."\}\}"
        );
      }
 
      return Output->new(
        error => 0,
        data  => ['pool_manager', { 
          ident     => $ident, 
          interface => $interface, 
          netaddr   => $local_net->[1]->{$interface},
          fqdn      => $hostname,
          type      => 'SIMPLE' 
        }],
      );
    }else{
      if ($debug){
        $logOutput->log_data(
          "$message_p: ip=$ip_address not belong to localhost"
        );
      }
 
      return Output->new(
        error => 1,
        message => "$message_p: ip=$ip_address not belong to localhost; hostname=$hostname name can not be used, can cause errors in the configuration",
      );
    }
  }

  # cant't translate hostname to ip address
  # try use ip address
  my $dns_name = $self->ip_to_hostname;
  # PTR record is found, use it name for pool configuration
  if ($dns_name->[1] !~ /^$/){
    my $ident = $dns_name->[1];
    #$ident =~ s/^([^\.]+)\..+$/$1/;
    if ($debug){
      $logOutput->log_data(
        "$message_p: found PTR record for interface dns_name=".$dns_name->[1]
      );
      $logOutput->log_data(
        "$message_p: return A \{$ident => \{".$dns_name->[0]." => ".$dns_name->[1]."\}\}"
      );
    }
 
    return Output->new(
      error => 0,
      data => ['pool_manager',{ 
          ident     => $ident, 
          interface => $dns_name->[0], 
          netaddr   => $local_net->[1]->{$dns_name->[0]},
          fqdn      => $dns_name->[1], 
          type      =>'PTR'
        }
      ],
    );
  # PTR record not found use ip address of interface and input hostname(generated somtimes)
  }else{
    my $ident = $hostname;
    #$ident =~ s/^([^\.]+)\..+$/$1/;
    if ($debug){
      $logOutput->log_data(
        "$message_p: return SIMPLE \{$ident => \{".$dns_name->[0]." => ".$local_net->[1]->{$dns_name->[0]}."\}\}"
      );
    }
    return Output->new(
      error => 0,
      data => ['pool_manager', {
        ident     => $ident, 
        interface => $dns_name->[0], 
        netaddr   => $local_net->[1]->{$dns_name->[0]},
        fqdn      => $ident,
        type      =>'SIMPLE'
      }],
    );
  }
}

# convert ip address to interface
sub ip_to_interface {
  my $self = shift;
  my $ip_address = shift;
  my $message_p = (caller(0))[3];

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);
  if (!$ip_address){
    return Output->new(
      error => 1,
      message => "$message_p: ip_address is mandatory",
    );
  }

  my $interface = $self->manager_interface; # interface that used for pool, == any in default
 
  if($debug){
    $logOutput->log_data(
      "$message_p: try found interface for ip=$ip_address"
    );
  }
  my $local_net = $self->localhost_network; # return { int => ip_address }
  if ($local_net->[0] == 0){
    if ($debug){
      $logOutput->log_data(
        "$message_p: not found running interfaces on host"
      );
    }
    return Output->new(
      error => 1,
      message => "$message_p: not found running interfaces on host",
    );
  }
  

  foreach my $int (keys %{$local_net->[1]}){
    if ($local_net->[1]->{$int} =~ /^$ip_address$/){
      if ($debug){
        $logOutput->log_data(
        "$message_p: found interface=$int for ip_address=$ip_address" 
        );
      }

      return Output->new(
        error => 0,
        data => ['pool_interface_revert',{netaddr=>$ip_address, interface => $int}],
      );
    }
  }

  return Output->new(
    error => 1,
    message => "$message_p: Not found ip address on localhost"
  );
 
};

# list interfaces on localhost
sub list_interfaces {
  my $self = shift;
  my $message_p = (caller(0))[3];

  my $local_net = $self->localhost_network; # return { int => ip_address }
  if ($local_net->[0] == 0){
    return Output->new(
      error => 1,
      message => "$message_p: not found running interfaces on host",
    );
  }

  return Output->new(
    error => 0,
    data => ['pool_interfaces',$local_net->[1]]
  );
}

sub interface_to_ip {
  my $self = shift;
  my $interface = shift;
  my $message_p = (caller(0))[3];

  my $local_net = $self->localhost_network; # return { int => ip_address }
  #print Dumper($local_net);
  if (not defined $local_net->[1]->{$interface}){
    return Output->new(
      error => 1,
      message => "$message_p: not found running interface=$interface on host",
    );
  }

  return Output->new(
    error => 0,
    data => ['pool_interfaces',{ interface => $interface, netaddr => $local_net->[1]->{$interface}}]
  );
}


1;
