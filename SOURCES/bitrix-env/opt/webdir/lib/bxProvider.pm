# provider options
#
package bxProvider;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Path qw(remove_tree rmtree mkpath);
use File::Spec::Functions;
use Data::Dumper;
use JSON;
use Output;
use Pool;
use Host;
use SSHAuthUser;
use bxDaemon;

# basic path for site
has 'base', 	is => 'ro', default => '/opt/webdir/providers';
has 'provider', is => 'ro', lazy => 1, builder => 'provider_options', predicate => 'has_options';
has 'name', 	is => 'ro', lazy => 1, builder => 'provider_name', predicate => 'has_name';
has 'debug', 	is => 'ro', isa => 'Int', default => 0;
has 'logfile', 	is => 'ro', isa => 'Str', default => '/opt/webdir/logs/providers.debug';

# bulid
sub BUILD {
  my $self = shift;

  die "Need to specify at least one of 'provider', 'name'!"
    unless $self->has_options || $self->has_name;
}

# execute plugin with defined option and return hash
sub executeProviderCmd {
  my ($exec, $opt) = @_;
  
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  # test available actions
  my $provider_execute = qq($exec $opt);
  my $provider_json = "";
  open(my $ph, "$provider_execute |")
    or die "Cannot execute $provider_execute: $!";
  while(my $line = <$ph>){
    $provider_json .= $line;
  }
  close $ph;
  
  if($provider_json =~ /^$/){ 
    return Output->new(
      error => 1,
      message => "$message_p: Command \`$provider_execute\` return empty string",
    );
  }

  my $json_to_hash = from_json($provider_json);
  if (exists $json_to_hash->{'error'}){
    return Output->new(
      error => $json_to_hash->{'error'},
      message => "cmd=\`$provider_execute\` return ".$json_to_hash->{'error_message'},
    )
  }
 
  return Output->new(
    error => 0,
    data => ['json', $json_to_hash],
  );
}

# save status info to task file
sub saveStatus{
  my ($file, $status, $message) = @_;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  open (my $fh, '>', $file)
    or return Output->new(
    error => 1,
    message => "$message_p: Cannot open $file: $!",
  );

  print $fh "$status: $message";

  close $fh;
}


# create name based on provider options
sub provider_name {
  my $self = shift;
  
  my $provider_options = $self->provider;

  return $provider_options->{'name'};
}

# get all provider option by it's name
sub provider_options {
  my $self = shift;
  
  my $provider_name = $self->name;
  my $provider_base = $self->base;

  my $provider_options = {
    name    => $provider_name,
    status  => 'not_exists',    # define exist or not directory with provider data
    config  => 'not_exists',    # defined exist config file or not
    files => {
      holder  => catfile($provider_base, $provider_name),
      config  => undef,           # config file for provider
      execute => undef,           # execute script
    },
    options => {                          # 
      help          => 0,             # print supported actions
      init          => 0,             # action that used when pool created, manager host setup
      configs       => 0,             # list host configuration name
      order         => 0,             # request for configuration that user choose
      order_status  => 0,             # status of request
    },
  };

  my $provider_execdir = catfile($provider_options->{'files'}->{'holder'}, 'bin');
  my $provider_confdir = catfile($provider_options->{'files'}->{'holder'}, 'etc');
  $provider_options->{'files'}->{'execute'} = catfile($provider_execdir, $provider_name);
  $provider_options->{'files'}->{'config'}  = catfile($provider_confdir, $provider_name.'.conf');


  if (! -x $provider_options->{'files'}->{'execute'}){ return $provider_options; }
  $provider_options->{'status'} = 'exists';
  if (-f $provider_options->{'files'}->{'config'}){
    $provider_options->{'config'} = 'exists';
  }
  
  # test available actions
  my $provider_answer = executeProviderCmd(
    $provider_options->{'files'}->{'execute'},
    'help',
  );
  
  if($provider_answer->is_error){ return $provider_options; }
  my $json_to_hash = $provider_answer->get_data->[1];
  if(defined $json_to_hash->{'options'}){
    foreach my $cmd (@{$json_to_hash->{'options'}}){
      if (defined $provider_options->{'options'}->{$cmd}){
        $provider_options->{'options'}->{$cmd} = 1;
      }
    }
  }

  if(defined $json_to_hash->{'status'}){
    $provider_options->{'status'} = $json_to_hash->{'status'};
  }
  return $provider_options;
}
# unpack archive to defined folder
sub unpack {
  my ($self, $folder, $archive) = @_;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  if(!$folder){ 
    return Output->new(
      error => 1,
      message => "$message_t: path/to/folder is mandatory option"
    );
  }

  if(!$archive){
    return Output->new(
      error => 1,
      message => "$message_t: path/to/archive is mandatory option"
    );
  }

  if(! -f $archive){ 
    return Output->new(
      error => 1,
      message => "$message_t: not found $archive"
    );
  }

  if (! -d $folder){
    mkdir $folder;
  }

  if ($archive =~ /\.(tar\.gz|tar\.bz2|zip)$/){
    my $archive_type = $1;
    my $unpack_cmd = '';
    if ($archive_type =~ /^tar\.gz$/){
      $unpack_cmd = qq(tar xzf $archive -C $folder);
    }elsif($archive_type =~ /^tar\.bz2$/){
      $unpack_cmd = qq(tar xzf $archive -C $folder);
    }elsif($archive_type =~ /^zip$/){
      $unpack_cmd = qq(unzip $archive -d $folder);
    }
    system("$unpack_cmd 1>/dev/null 2>&1") == 0 
      or return Output->new(
      error => 1,
      message => "$message_t: cmd=\`$unpack_cmd\` return error: $!"
    );
    return Output->new(
      error => 0,
      message => "$message_t: unpack $archive to $folder",
    );
  }else{
    return Output->new(
      error => 1,
      message => "$message_t: not supported archive (only support tar.gz, tar.bz2, zip)"
    );
  }
}

# create initial directories for provider and copy its files
sub installProvider {
  my ($self, $archive) = @_;
  
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;
  my $provider_base    = $self->base;

  if ($provider_options->{'status'} !~ /^not_exists$/){
    return Output->new(
      error => 1,
      message => "$message_t: Provider $provider_name already exist on the host"
    );
  }
  # create directories
  foreach my $d (
    $provider_base, 
    $provider_options->{'files'}->{'holder'}, 
    dirname($provider_options->{'files'}->{'execute'}),
    dirname($provider_options->{'files'}->{'config'}),
  ){
    if(! -d $d){ 
      mkdir $d; 
      if($debug){ $logOutput->log_data("$message_p: mkdir $d"); }
    }
  }

  if ($archive){
    my $unpack_archive = $self->unpack($provider_options->{'files'}->{'holder'}, $archive);
    if ($unpack_archive->is_error){ return $unpack_archive; }
    if($debug){ $logOutput->log_data("$message_p: unpack $archive to ".$provider_options->{'files'}->{'holder'}); }
  }
  
  my $chown_cmd = qq(chown -R bitrix.bitrix $provider_options->{'files'}->{'holder'});
  system($chown_cmd) == 0
    or return Output->new(
    error => 1,
    message => "$message_t: Cannot change access on ".$provider_options->{'files'}->{'holder'},
  );

  return Output->new(
    error => 0,
    message => "$message_t: Provider data created, you can found it in ".$provider_options->{'files'}->{'holder'},
  );
}

# delete folder for provider
sub uninstallProvider {
  my ($self) = @_;
  
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;

  if ($provider_options->{'status'} =~ /^not_exists$/){
    return Output->new(
      error => 1,
      message => "$message_t: Provider $provider_name not exist on the host"
    );
  }
  my $provider_directory =  $provider_options->{'files'}->{'holder'}; 
  remove_tree( $provider_options, {error => \my $err} );
  if (@$err) {
    my $error_message = "";
    for my $diag (@$err) {
      my ($file, $message) = %$diag;
      if ($file eq '') {
        $error_message .= "general error: $message\n";
      }else{
        $error_message .= "problem unlinking $file: $message\n";
      }
    }
    return Output->new(
      error => 1,
      message => "$message_t: $error_message"
    );
  }

  return Output->new(
    error => 0,
    message => "$message_t: Provider data deleted from ".$provider_options->{'files'}->{'holder'},
  );
}

# get provider status
sub optionsProvider {
  my ($self) = @_;
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;

  if ($provider_options->{'status'} =~ /^not_exists$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name not exist on the host"
    );
  }

  my $output = { $provider_name => $provider_options };
  
  return Output->new(
    error => 0,
    data  => ["provider_options", $output],
  );
}

# get provider status
sub configsProvider {
  my ($self) = @_;
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;

  if ($provider_options->{'status'} =~ /^(not_exists|disabled)$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name $1 on the host"
    );
  }

  if($provider_options->{'options'}->{'configs'} == 0){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't support configs option"
    );
  }

  # test available actions
  my $provider_answer = executeProviderCmd(
    $provider_options->{'files'}->{'execute'},
    'configs',
  );
 
  if($provider_answer->is_error){ return $provider_answer; }
  my $provider_configs = $provider_answer->get_data->[1];

  return Output->new(
    error => 0,
    data  => ["provider_configs", {$provider_name => $provider_configs}],
  );
}

# order config from provider
sub order2Provider {
  my ($self,$config_id) = @_;
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  if(not defined $config_id){
    return Output->new(
      error => 1,
      message => "$message_p: You must provide config_id for order"
    );
  }

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;
  my $provider_tasks   = catfile($provider_options->{'files'}->{'holder'},'tasks');

  if ($provider_options->{'status'} =~ /^(not_exists|disabled)$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name $1 on the host"
    );
  }

  if($provider_options->{'options'}->{'order'} == 0){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't support order option"
    );
  }

  # test available actions
  my $provider_answer = executeProviderCmd(
    $provider_options->{'files'}->{'execute'},
    "order $config_id",
  );
 
  if($provider_answer->is_error){ return $provider_answer; }
  if(! -d $provider_tasks){
    mkpath($provider_tasks,0,0770);
  }
  my $provider_order = $provider_answer->get_data->[1];
  my $task_id = $provider_order->{'task_id'};
  if($task_id =~ /^$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't return task_id"
    );
  }
  my $task_file = catfile($provider_tasks, $task_id);
  open (my $th, '>', $task_file) 
    or return Output->new(
    error => 1,
    message => "$message_p: Cannot save $task_file: $!"
  );
  close $th;

  return Output->new(
    error => 0,
    data  => ["provider_order", {$provider_name => $provider_order}],
  );
}

sub order_status2Provider {
  my ($self,$task_id) = @_;
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  if(not defined $task_id){
    return Output->new(
      error => 1,
      message => "$message_p: You must provide task_id for status request"
    );
  }

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;
  my $provider_tasks   = catfile($provider_options->{'files'}->{'holder'},'tasks');

  if ($provider_options->{'status'} =~ /^(not_exists|disabled)$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name $1 on the host"
    );
  }

  if($provider_options->{'options'}->{'order_status'} == 0){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't support order_status option"
    );
  }

  # test available actions
  my $provider_answer = executeProviderCmd(
    $provider_options->{'files'}->{'execute'},
    "order_status $task_id",
  );
 
  # save error to task info
  if($provider_answer->is_error){ return $provider_answer; }
  my $provider_order_status = $provider_answer->get_data->[1];
  my $status = $provider_order_status->{'status'};
  if($status =~ /^$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't return status for task_id=$task_id"
    );
  }

  # test if we already try to add host to the pool
  my $task_file = catfile($provider_tasks, $task_id);
  if (-f $task_file){
    open (my $th, '<', $task_file)
      or return Output->new(
      error => 1,
      message => "Cannot open $task_file: $!",
    );

    my $server_status = "";
    while(my $line = <$th>){
      $server_status .= $line;
    }
    close $th;
  
    if ($server_status =~ /^error:\s*(.+)$/){
      $provider_order_status->{'status'} = "error";
      $provider_order_status->{'message'}= "$1";
      $provider_order_status->{'error'}  = 1;
    }elsif($server_status =~ /^complete/){
      $provider_order_status->{'status'} = "complete";
    }
  }

  return Output->new(
    error => 0,
    data  => ["provider_order", {$provider_name => $provider_order_status}],
  );
}
# test task_id and start adding server to the pool
sub order_to_hostProvider {
  my ($self,$task_id) = @_;
  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  if(not defined $task_id){
    return Output->new(
      error => 1,
      message => "$message_p: You must provide task_id for status request"
    );
  }

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;
  my $provider_tasks   = catfile($provider_options->{'files'}->{'holder'},'tasks');

  if ($provider_options->{'status'} =~ /^(not_exists|disabled)$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name $1 on the host"
    );
  }

  if($provider_options->{'options'}->{'order_status'} == 0){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't support order_status option"
    );
  }

  # test available actions
  my $provider_answer = executeProviderCmd(
    $provider_options->{'files'}->{'execute'},
    "order_status $task_id",
  );
 
  # save error to task info
  if($provider_answer->is_error){ return $provider_answer; }
  my $provider_order_status = $provider_answer->get_data->[1];
  my $status = $provider_order_status->{'status'};
  if($status =~ /^$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't return status for task_id=$task_id"
    );
  }
  # if remote server return that server is ready for client
  if ($status =~ /^finished$/){
    my $server_address  = $provider_order_status->{'server'};
    my $server_password = ($provider_order_status->{'server_password'})?
      $provider_order_status->{'server_password'}: "";
    # use task_file, to avoid re-adding server to the pool
    my $task_file = catfile($provider_tasks, $task_id);
    my $server_status = "";
    
    # it is an impossible situation, but suddenly
    if(! -f $task_file){
      return Output->new(
        error => 1,
        message =>  "$message_p: Not found saved task_id=$task_id on this server",
      );
    }

    # test if user already add server to the pool
    open(my $th, '<', $task_file)
      or return Output->new(
      error => 1,
      message => "$message_p: Cannot open file=$task_file:$!"
    );

    while(my $line = <$th>){
      $server_status .= $line;
    }
    close $th;

    # test if task already complete
    if ($server_status =~ /^(complete|error)/){
      return Output->new(
        error => 1,
        message => "$message_p: task_id=$task_id already $server_status",
      );
    # we still did not do anything to add to the server pool
    }elsif($server_status =~ /^$/){
      
      #1. copy ssh key to host, if defined server_password
      if($server_password !~ /^$/){
        # get ssh key from pool configuration
        my $po = Pool->new(debug=>$debug);
        my $get_ssh_key = $po->get_ssh_key();
        if ($get_ssh_key->is_error){
          my $ss = saveStatus($task_file, "error", $get_ssh_key->get_message());
          return $get_ssh_key;
        }

        # copy ssh key to the server
        my $ssh = SSHAuthUser->new(
          sship   => $server_address,
          sshkey  => $get_ssh_key->get_data->[1],
          oldpass => $server_password,
        );
        my $copy_ssh_key = $ssh->copy_ssh_key();
        if ($copy_ssh_key->is_error){ 
          my $ss = saveStatus($task_file, "error", $copy_ssh_key->get_message());
          return $copy_ssh_key; 
        }
      }

      # add host to ansible group file and create host configuration file
      my $host = Host->new(host => $server_address, ip => $server_address);
      my $createHost = $host->createHost();
      if ($createHost->is_error){
        my $ss = saveStatus($task_file, "error", $createHost->get_message());
        return $createHost
      }

      # save information that host added to group and order complete totally
      my $ss = saveStatus($task_file, "complete", "Server=$server_address is added to the pool");

      return Output->new(
        error => 0,
        message => "Server=$server_address is added to the pool",
      );

    }

  # status == in_process
  }elsif($status == "in_progress"){
    return Output->new(
      error => 0,
      data  => ["provider_order", {$provider_name => $provider_order_status}]
    )
  }else{
    return Output->new(
      error => 1,
      message => "Unknown status=$status for $provider_name",
    );
  }

}
# get list of all tasks that order servers|VPS
sub listOrders4Provider {
  my $self = shift;

  my $message_p = (caller(0))[3];
  my $message_t = __PACKAGE__;

  my $debug  = $self->debug;
  my $logOutput = Output->new(error => 0, logfile => $self->logfile);

  my $provider_options = $self->provider;
  my $provider_name    = $self->name;
  my $provider_tasks   = catfile($provider_options->{'files'}->{'holder'},'tasks');

  if ($provider_options->{'status'} =~ /^(not_exists|disabled)$/){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name $1 on the host"
    );
  }

  if($provider_options->{'options'}->{'order_status'} == 0){
    return Output->new(
      error => 1,
      message => "$message_p: Provider $provider_name doesn't support order_status option"
    );
  }

  opendir(my $td, $provider_tasks)
    or return Output->new(
    error => 1,
    message => "$message_t: Cannot open dircetory ".$provider_tasks.": $!",
  );


  my $output;
  while(my $task_id = readdir($td)){
    next if ($task_id =~ /^\.\.?$/);
    my $fn = catfile($provider_tasks, $task_id);
    my $task_modify = (stat($fn))[9];
    if ( -f $fn){
      my $task_status = $self->order_status2Provider($task_id);
      if ($task_status->is_error){
        $output->{$provider_name}->{$task_id} = {
          error => $task_status->is_error,
          message => $task_status->get_message,
          mtime => $task_modify,
        };
      }else{
        my $task_data = $task_status->get_data->[1]->{$provider_name};
        my $task_stat = $task_data->{'status'};
        my $task_err  = ($task_data->{'error'})? $task_data->{'error'}: 0;
        my $task_msg  = ($task_data->{'message'})? $task_data->{'message'}: "";
    
        $output->{$provider_name}->{$task_id} = {
          error   => $task_err,
          message => $task_msg,
          status  => $task_stat,
          mtime   => $task_modify,
        };
      }
    }
  }

  return Output->new(
    error => 0,
    data  => ["provider_order_list", $output],
  );
}

1;
