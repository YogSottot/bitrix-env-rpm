#
package SSHAuthUser;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use Sys::Hostname;
use Output;
use Pool;

has 'sship', is => 'ro', isa => 'Str';
has 'sshport', is => 'ro', isa => 'Int', lazy => 1, default => 22;
has 'sshkey', is => 'ro', isa => 'Str';
has 'sshlogin', is => 'ro', isa => 'Str', default => 'root';
has 'oldpass',  is => 'ro', isa => 'Str';
has 'newpass',  is => 'ro', isa => 'Str';
has 'ext_ssh_keycopy', is => 'ro', isa => 'Str', lazy => 1, default => '/opt/webdir/bin/ssh_keycopy';
has 'ext_ssh_passchg', is => 'ro', isa => 'Str', lazy => 1, default => '/opt/webdir/bin/ssh_chpasswd';
has 'ext_ssh_keycopy_log', is => 'ro', isa => 'Str', lazy => 1, default => '/opt/webdir/logs/ssh_keycopy.log';
has 'ext_ssh_passchg_log', is => 'ro', isa => 'Str', lazy => 1, default => '/opt/webdir/logs/ssh_chpasswd.log';

sub copy_ssh_key {
  my $self = shift;

  my $ipaddres = Pool::esc_chars($self->sship);
  my $port     = Pool::esc_chars($self->sshport);
  my $login    = Pool::esc_chars($self->sshlogin);
  my $pass     = Pool::esc_chars($self->oldpass);
  my $key      = Pool::esc_chars($self->sshkey);
  my $ssh_cmd  = $self->ext_ssh_keycopy;
  my $ssh_log  = $self->ext_ssh_keycopy_log;
  
  # if user define private key => get pub for it
  if ( $key !~ /\.pub$/ ){ $key .= '.pub'; } 

  # external copy command ( in future do it by perl mod Expect )
  my $expect_script = qq(expect $ssh_cmd $ipaddres $port $login $key $pass >/dev/null 2>&1 );
  #print qq($expect_script\n);
  my $wait_code = system( $expect_script );
  my $exit_code = $wait_code >> 8;

  if ( $exit_code > 0 ){
    if ( $exit_code == 103 or $exit_code == 101 ){ 
      return Output->new(
          error => 1, 
          message => "User must change password, error=$exit_code: please view log file $ssh_log" );
    }elsif ( $exit_code == 104 ){
      return Output->new(
          error => 2,  
          message => "User enter incorrect password");
    }else{
        return Output->new( 
            error => 2, 
            message => "The error occurred, error=$exit_code: please view log file $ssh_log");
    }
  }
  return Output->new(
      error => 0, 
      message => "The ssh key copied to the server $ipaddres" );
};

sub change_user_pass {
  my $self = shift;

  my $ipaddres = Pool::esc_chars($self->sship);
  my $port     = Pool::esc_chars($self->sshport);
  my $login    = Pool::esc_chars($self->sshlogin);
  my $oldpass  = Pool::esc_chars($self->oldpass);
  my $newpass  = Pool::esc_chars($self->newpass);
  my $ssh_cmd  = $self->ext_ssh_passchg;
  my $ssh_log  = $self->ext_ssh_passchg_log;

  # external change password command ( in future do it by perl mod Expect )
  my $expect_script = qq(expect $ssh_cmd $ipaddres $port $login $oldpass $newpass);
  #print $expect_script,"\n";
  my $wait_code = system( $expect_script );
  my $exit_code = $wait_code >> 8;

  if ( $exit_code > 0 ){
    if ( $exit_code == 204 ){
      return Output->new( 
          error => 1,  
          message => "Password is not pass check by password policy on the $ipaddres");
    }
    return Output->new(error => 2, 
        message => "The error occurred, error=$exit_code: please view log file $ssh_log");
  }

  return Output->new(
      error => 0, 
      message => "The password is changed for $login on the server $ipaddres" );
}

1;
