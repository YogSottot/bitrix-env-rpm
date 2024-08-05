#
package bxNetwork;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use Sys::Hostname;
use Net::DNS;
use Output;
use JSON;
use Pool;

# short hostname, defualt bxserverID
has 'host' => (
  is => 'rw', 
  isa => 'Str', 
  lazy => 1, 
  builder => 'get_host_by_netaddr',
  predicate => 'has_host',
);

# ip address or fqdn
has 'netaddr' => (
  is => 'rw', 
  isa => 'Str', 
  lazy => 1, 
  builder => 'get_netaddr_by_host',
  predicate => 'has_netaddr',
);

has 'interface' => (
  is => 'ro',
  isa => 'Str',
);

has 'debug' => (
  is => 'ro',
  isa => 'Int',
  default => 0,
);

has 'logfile' => (
  is => 'ro',
  isa => 'Str',
  default => '/opt/webdir/logs/pool_network.debug',
);

# bulid 
sub BUILD {
  my $self = shift;

  die "Need to specify at least one of 'netaddr', 'host'!" 
    unless $self->has_netaddr || $self->has_host;
}

# create default bxserverID name
sub create_default_name {
  my $self = shift;
  my $standart_name = "server";
  my $last_id = 0;

  my $pool = Pool->new();
  my $get_servers = $pool->get_ansible_data();
  # pool is created
  if ($get_servers->is_error == 0){
    my $data_servers = $get_servers->get_data->[1];
    foreach my $srv_name (keys %$data_servers){
      if ($srv_name =~ /^$standart_name(\d+)$/){
        my $id = $1;
        if ($last_id < $id){ $last_id = $id; }
      }
    }
  }

  $last_id = $last_id+1;
  return $standart_name.$last_id;
}

# dnsname to ip address
sub a_lookup {
  my $self = shift;
  my $dnsname = shift;

  my $res = Net::DNS::Resolver->new(recurse => 0, debug => $self->debug);
  $res->udp_timeout(10);
  $res->force_v4(1);
  my $query = $res->search($dnsname, 'A');
  my $ip = '';
  # found
  if ($query){
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "A";
      $ip = $rr->address;
    }
  }

  return $ip;
}

# BUILDER
# ip address to dnsname
sub ptr_lookup {
  my $self = shift;
  my $ip   = shift;

  my $res = Net::DNS::Resolver->new(recurse => 0, debug => $self->debug);
  $res->udp_timeout(10);
  $res->force_v4(1);
  my $query = $res->search($ip,'PTR');
  
  my $dnsname = '';
  # found
  if ($query){
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "PTR";
      if ( $rr->ptrdname =~ /^[\w\d\-\_\.]+\.(com|ru|de|org|ua|private|test|bx|lan)$/i ){
        if($self->debug){
          printf "%-15s: %s\n",("Found PTR", $rr->ptrdname);
        }
        $dnsname = $rr->ptrdname;
      }
    }
  }

  return $dnsname;
}

# BUILDER
# get netaddr by hostname
sub get_netaddr_by_host {
  my $self = shift;

  my $host = $self->host;
  my $debug  = $self->debug; 
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);
  my $netaddr = $self->a_lookup($host);
  if ($debug) { $logOutput->log_data($netaddr); }

  return $netaddr;
}

sub get_host_by_netaddr {
  my $self = shift;

  my $netaddr = $self->netaddr;
  my $host = '';
  # ip
  if ( $netaddr =~ /^[0-9\.]+$/ ){
    $host = $self->ptr_lookup($netaddr);
    if ( $host =~ /^$/ ){
      $host = $self->create_default_name;
    }
  }else{
    # first part of DNS name
    $host = $netaddr;
    $host =~ s/^([^\.]+)\..+$/$1/;
  }

  return $host;
}

# create network info for localhost
sub create_localhost {
  my $self = shift;

  my $message_p = (caller(0))[3];
 
  # return values
  my %h_info = (
    'host'      => '',
    'netaddr'   => '',
    'type'      => 'ip',
    'interface' => '',
  );

  # get localhost network options
  $h_info{'host'} = hostname;
  if ($self->debug){ printf "%-15s: %s\n",($message_p, "Hostname: ".$h_info{'host'}); }

  my @interfaces = IO::Interface::Simple->interfaces;
  
  # if user defined interface that used in the pool
  if (defined $self->interface){
    @interfaces = grep /^$self->interface$/, @interfaces;
  }

  my $running_int = '';
  foreach my $int (sort @interfaces){
    
    if ($running_int =~ /^$/ && $int->is_running && $int !~ /^lo/ ){
      if ($int->address !~ /^127\.0\.0\.1$/){
        $running_int = $int;
        $h_info{'netaddr'} = $int->address;
        $h_info{'interface'} = $int;

        if ($self->debug){ 
          printf "%-15s: %s\n",($message_p, "Interface: $int, Address: ". $h_info{'netaddr'}); 
        }
      }
    }
  }

  # exclude next names, creating default values
  my $lregexp = '^(localhost|localhost\.localdomain|127\.0\.0\.1|)$';

  # if we create hostname localy, use it ip address
  if ($h_info{'host'} =~ /$lregexp/){
    
    $h_info{'host'} = $self->create_default_name;
    if ($self->debug){ 
      printf "%-15s: %s\n",($message_p, "Generate hostname: ". $h_info{'host'}); 
    }
 
  # if hostname was set
  }else{
    
    # check if ip address fits to hostname
    my $ipaddres_by_dns = $self->a_lookup($h_info{'host'});
    if ($self->debug){ 
      printf "%-15s: %s\n",($message_p, "Nslookup: ". $ipaddres_by_dns); 
    }
 
    
    # if hostname is resolved, ip_address is not empty
    if ($ipaddres_by_dns !~ /^$/){
     
      # address the same, use hostname like netaddr
      if ($h_info{'netaddr'} =~ /^$ipaddres_by_dns$/){

        $h_info{'type'} = 'fqdn';
        $h_info{'netaddr'} = $h_info{'host'};
        $h_info{'host'} =~ s/^([^\.]+)\..+$/$1/;
        if ($self->debug){ 
          printf "%-15s: %s\n",($message_p, "Name correct use it: ". $h_info{'host'}); 
        }
 
      }
    }
  }

  # creat short name
  $h_info{'host'} =~ s/^([^\.]+)\..+$/$1/;

  #print Dumper(\%h_info);
  return \%h_info;
}

# hostinfo
# test netaddr and host attributtes
sub network_info {
  my $self = shift;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  # return values
  my %h_info = (
    'host'    => $self->host,
    'netaddr' => $self->netaddr,
    'type'    => 'fqdn',
  );
  if ($self->debug){ 
    printf "%-15s: %s\n",($message_p, "Host: ". $h_info{'host'}); 
    printf "%-15s: %s\n",($message_p, "IP: ". $h_info{'netaddr'}); 

  }
 
  # own method for localhost
  my $lregexp = '^(localhost|localhost\.localdomain|127\.0\.0\.1)$';

  if ( $h_info{'host'} =~ /$lregexp/ || $h_info{'netaddr'} =~ /$lregexp/ ){
    if ($self->debug){ 
      printf "%-15s: %s\n",($message_p, "Detected $lregexp for ". $h_info{'host'}); 
    }
     
    my $create_localhost_info = $self->create_localhost;
    %h_info = %{$create_localhost_info};

  }else{
    # get ip add by hostname ( from saved file )
    if ( $h_info{'netaddr'} =~ /^$/ ){
      return Output->new(
        error => 1,
        message => "Cannot defined ip address for hostname ".$h_info{'host'},
      );
    }
    # this is impossible, but all things are possible
    if ( $h_info{'host'} =~ /^$/ ){
      return Output->new(
        error => 1,
        message => "Cannot defined hostname for network addrress ".$h_info{'netaddr'},
      );
    }

    # if defined ip and cannot define name for host (generate it)
    if ( $h_info{'netaddr'} =~ /^[0-9\.]+$/ ){
      # if short name is ip address create new one
      if ( $h_info{'host'} =~ /^$h_info{'netaddr'}$/ ){
        $h_info{'host'} = $self->create_default_name;
      
      # test host info and ip 
      }else{
        # test if A record is the same with hostname
        my $test_ip = $self->a_lookup($h_info{'host'});

        if ( $test_ip =~ $h_info{'netaddr'} ){

          $h_info{'netaddr'} = $h_info{'host'};
          $h_info{'type'} = 'fqdn';
        }else{
          $h_info{'type'} = 'ip';
        }
      }
    }else{
      if ( $h_info{'host'} =~ /^$h_info{'netaddr'}$/ ){
        my $test_ip = $self->a_lookup($h_info{'host'});
        # test if we can get ip by netaddres
        if ( $test_ip !~ /^$/ ){
          $h_info{'type'} = 'fqdn';
        }else{
          return Output->new(
            error => 1,
            message => "Cannot get IP for network addrress ".$h_info{'netaddr'},
          );
        }
      }else{
        my $host_ip = $self->a_lookup($h_info{'host'});
        my $netaddr_ip = $self->a_lookup($h_info{'netaddr'});

        if ($netaddr_ip =~ /^$/){
          return Output->new(
            error => 1,
            message => "Cannot get IP for network addrress ".$h_info{'netaddr'},
          );
        }

        if ($host_ip =~ /^$/){
          $h_info{'host'} = $h_info{'netaddr'};
          $h_info{'type'} = 'fqdn';
        }else{
          if ( $host_ip =~ /^$netaddr_ip$/ ){
            $h_info{'host'} = $h_info{'netaddr'};
            $h_info{'type'} = 'fqdn';
          }else{
            return Output->new(
              error => 1,
              message => "IP address for ".$h_info{'host'}." doesn't match ip network name ".$h_info{'netaddr'},
            );
          }
        }
      }
    }
  }

  # define type from netaddr
  if ( $h_info{'netaddr'} =~ /^[0-9\.]+$/ ){
    $h_info{'type'} = 'ip';
  }

  $h_info{'host'} =~ s/^([^\.]+)\..+$/$1/;

  return Output->new(
    error => 0,
    data => ['host_network', \%h_info],
  );
};

1;
