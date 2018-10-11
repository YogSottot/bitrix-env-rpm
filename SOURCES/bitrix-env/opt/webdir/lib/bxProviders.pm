# provider options
#
package bxProviders;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Path qw(remove_tree rmtree mkpath);
use File::Spec::Functions;
use Data::Dumper;
use Output;
use bxProvider;

# basic path for site
has 'base', 	is => 'ro', default => '/opt/webdir/providers';
has 'debug', 	is => 'ro', isa => 'Int', default => 0;
has 'logfile', 	is => 'ro', isa => 'Str', default => '/opt/webdir/logs/providers.debug';

# provider's names that installed  on the server
sub listProviders{
  my ($self, $status) = @_;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  # return data about provider in disabled or enabled statuses
  if(not defined $status){ 
    $status = "enabled"
  }

  # returned values
  my $output = {};


  opendir(my $ph, $self->base)
    or return Output->new(
    error => 1,
    message => "$message_t: Cannot open dircetory ".$self->base.": $!",
  );

  while(my $name  = readdir($ph)){
    next if ($name =~ /^\.\.?$/);
    my $fn = catfile($self->base, $name);
    if (-d $fn){
      my $provider = bxProvider->new(
        name => $name,
        debug => $self->debug
      );

      my $provider_opt = $provider->optionsProvider();
      if ($provider_opt->is_error){
        $output->{$name} = {
          error => $provider_opt->is_error,
          message => $provider_opt->get_message,
        }
      }else{
        $output->{$name} = { status => $provider_opt->get_data->[1]->{$name}->{'status'} };
      }
    }
  }

  closedir $ph;
  return Output->new(
    error => 0,
    data  => ["providers", $output],
  );
}

# provider's names that installed  on the server
sub listOrders4Providers{
  my ($self, $status) = @_;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  # return data about provider in disabled or enabled statuses
  if(not defined $status){ 
    $status = "enabled"
  }

  # returned values
  my $output = {};


  opendir(my $ph, $self->base)
    or return Output->new(
    error => 1,
    message => "$message_t: Cannot open directory ".$self->base.": $!",
  );

  while(my $name  = readdir($ph)){
    next if ($name =~ /^\.\.?$/);
    my $fn = catfile($self->base, $name);
    if (-d $fn){
      my $provider = bxProvider->new(
        name => $name,
        debug => $self->debug
      );

      my $provider_opt = $provider->listOrders4Provider();
      if ($provider_opt->is_error){
        #$output->{$name} = {
        #error => $provider_opt->is_error,
        #  message => $provider_opt->get_message,
        #}
        next;
      }else{
        $output->{$name} = $provider_opt->get_data->[1]->{$name};
      }
    }
  }
  return Output->new(
    error => 0,
    data  => ["provider_order_list", $output],
  );
}


1;
