# manage background daemons
#
package bxDaemon;
use strict;
use warnings;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use File::Path qw( remove_tree );
use Data::Dumper;
use Proc::Daemon;
use Output;
use Pool;
use bxInventory qw( save_to_yaml );

# main ansible config dir, all hosts and groups file definitions saved here
has 'log_dir',  is => 'ro', default => '/opt/webdir/logs';
has 'log_file', is => 'ro', default => 'bxDaemon.log';
has 'task_dir', is => 'ro', default => '/opt/webdir/temp';
has 'task_cmd', is => 'ro';
has 'debug',    is => 'ro', default => 1;

# create task dir
# it hold status and pid info
sub genProcessId {
    my $task_dir  = shift;
    my $task_type = shift;

    my @idchars    = ( 0 .. 9 );
    my $is_created = 0;
    my $task_id    = undef;
    my $task_path  = undef;

    while ( $is_created == 0 ) {
        $task_id = $task_type . '_'
          . join( '', map( $idchars[ rand($#idchars) ], ( 1 .. 10 ) ) );
        $task_path = catfile( $task_dir, $task_id );
        if ( !-d $task_path ) {
            mkdir $task_path;
            chmod 0700, $task_path;
            $is_created = 1;
        }
    }

    return [ $task_id, $task_path ];
}

# get error message from log
sub errorProcess {
    my $log_file = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my @return_messages;
    my $is_error = 0;
    my $is_task  = 0;
    my $msg      = "";
    open( my $fh, $log_file )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open status file: $!"
      );

    while (<$fh>) {
        s/^\s+//;
        s/\s+$//;

        if (/^TASK:/) {
            $is_task  = 1;
            $is_error = 0;
            $msg      = "";
        }

        if (/^failed:/) { $is_error = 1 }
        if (/^fatal:/)  { $is_error = 1 }
        if ( /["']?msg["']?:\s+(.+)$/ && $is_error ) { $msg = $1 }
        if ( !/^(msg|failed|TASK):/ && $msg && $is_error ) { $msg .= $_; }

        if ( /^$/ && $msg ) {
            push @return_messages, $msg;
            $msg      = "";
            $is_error = 0;
            $is_task  = 0;
        }
    }
    close $fh;

    return \@return_messages;
}

# info about process from log file
sub statusProcess {
    my $self    = shift;
    my $task_id = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $task_dir = catfile( $self->task_dir, $task_id );
    my $log_file = catfile( $task_dir,       "status" );
    my $pid_file = catfile( $task_dir,       "pid" );

    if ( !-f $log_file ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Not found status info about tasks"
        );
    }

    # info from filesystem
    my $modified = ( stat($log_file) )[9];
    my $created  = ( stat($log_file) )[10];

    # info from file
    my $taskData = {
        $task_id => {
            pid            => 0,
            status         => "running",
            modified       => $modified,
            created        => $created,
            last_action    => '',
            errors         => 0,
            error_on_hosts => [],
            error_messages => [],
            review         => {},
        }
    };

    my $task_finished = 0;
    my $task_errors   = 0;
    open( my $fh, $log_file )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open status file: $!"
      );
    while (<$fh>) {

        #print "|",$_,"|\n";
        if (/^GATHERING FACTS/) {
            $taskData->{$task_id}->{'last_action'} = "play|gathering facts";
        }

        # roles
        if (/^TASK:\s+\[(\S+)\s+\|\s+([^\]]+)\]/) {
            $taskData->{$task_id}->{'last_action'} = "$1\|$2";
        }

        # non-roles playbook
        # TASK: [add configuration options in mysql service for upgrade time]
        if (/^TASK:\s+\[([^\]\|]+)\]/) {

            #print "found: $1\n";
            $taskData->{$task_id}->{'last_action'} = "play|$1";
        }

        if (/^PLAY RECAP\s+/) {
            $taskData->{$task_id}->{'last_action'} = "play|complete";
            $task_finished = 1;
        }

        if ( $task_finished == 1 ) {

   # vm1                        : ok=21   changed=4    unreachable=0    failed=0
            if (
/^(\S+)\s+:\s+ok=(\d+)\s+changed=(\d+)\s+unreachable=(\d+)\s+failed=(\d+)/
              )
            {
                $taskData->{$task_id}->{'review'}->{$1} =
                  { ok => $2, changed => $3, unreachable => $4, failed => $5 };
                my $host        = $1;
                my $unreachable = $4;
                my $failed      = $5;
                if ( $failed > 0 || $unreachable > 0 ) {
                    $task_errors++;
                    push @{ $taskData->{$task_id}->{'error_on_hosts'} }, $host;
                }
            }
        }
    }
    close $fh;

    # return info
    if ( $task_finished == 1 && $task_errors == 0 ) {
        $taskData->{$task_id}->{'status'} = "finished";
    }
    if ( $task_finished == 1 && $task_errors > 0 ) {
        $taskData->{$task_id}->{'status'}         = "error";
        $taskData->{$task_id}->{'error_messages'} = errorProcess($log_file);
        $taskData->{$task_id}->{'errors'}         = $task_errors;
    }

   # if process is not exist in the system, but we not found info in sttaus file
    my $daemon = Proc::Daemon->new( pid_file => $pid_file );
    my $pid = $daemon->Status();
    if ( $pid == 0 && $taskData->{$task_id}->{'status'} =~ /^running$/ ) {
        $taskData->{$task_id}->{'status'} = "interrupt";
    }

    # collect information
    return Output->new(
        error => 0,
        data  => [ $message_t, $taskData ],
    );
}

# list all process with its statuses
sub listProcess {
    my $self      = shift;
    my $task_type = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    if ( not defined $task_type ) { $task_type = "all" }

    #print "$task_type\n";

    my $base_dir = $self->task_dir;

    # directory listing
    opendir( my $dh, $base_dir )
      or return Output->new(
        error   => 1,
        message => "$message_p: Not found process directory: $!"
      );

    # exclude . and .. directories
    my @files = grep { !/^\.\.?$/ } readdir $dh;
    closedir $dh;

    my %processData;

    foreach my $task_id (@files) {
        my $path = catfile( $base_dir, $task_id );

        # process only directoris
        next if ( !-d $path );

        # if defined type and it doesn't fit file
        #print $task_id,"\n";
        next if ( $task_type !~ /^all$/ and $task_id !~ /^$task_type/ );

        my $logProcess = statusProcess( $self, $task_id );
        if ( $logProcess->is_error ) { return $logProcess; }
        my $data = $logProcess->get_data;
        $processData{$task_id} = $data->[1]->{$task_id};
    }

    return Output->new( error => 0, data => [ $message_t, \%processData ] );
}

# start background process for defined cmd
sub startAnsibleProcess {
    my $self         = shift;
    my $task_type    = shift;
    my $task_options = shift;

    if ( not defined $task_type ) { $task_type = "bx-pool"; }

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $genProcessId = genProcessId( $self->task_dir, $task_type );
    my $task_id      = $genProcessId->[0];
    my $task_dir     = $genProcessId->[1];
    my $pid_file     = catfile( $task_dir, "pid" );
    my $log_file     = catfile( $task_dir, "status" );
    my $opt_file     = catfile( $task_dir, "opts.yml" );

    my $save_to_yaml = save_to_yaml( $task_options, $opt_file );
    if ( $save_to_yaml->is_error ) { return $save_to_yaml }

    my $task_cmd = $self->task_cmd . qq( -e 'ansible_playbook_file=$opt_file');

    #print "$task_cmd\n";

    my $daemon = Proc::Daemon->new(
        child_STDOUT => $log_file,
        child_STDERR => $log_file,
        pid_file     => $pid_file,
        exec_command => $task_cmd,
        work_dir     => $self->task_dir,
    );

    my $pid = $daemon->Init();

    if ($pid) {
        return Output->new(
            error => 0,
            data  => [
                $message_t,
                {
                    $task_id =>
                      { pid => $pid, status => "running", created => time },
                    "task_name" => $task_id
                }
            ],
        );
    }
    return Output->new(
        error   => 1,
        message => "$message_p: Cannot create background process"
    );

}

# start background process for defined cmd
sub startProcess {
    my $self      = shift;
    my $task_type = shift;
    if ( not defined $task_type ) { $task_type = "bx-pool"; }

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $genProcessId = genProcessId( $self->task_dir, $task_type );
    my $task_id      = $genProcessId->[0];
    my $task_dir     = $genProcessId->[1];
    my $pid_file     = catfile( $task_dir, "pid" );
    my $log_file     = catfile( $task_dir, "status" );
    my $cmd_file     = catfile( $task_dir, "cmd" );

    my $debug = $self->debug;
    if ($debug) {
        open( my $lh, ">" . $cmd_file )
          or return Output->new(
            error   => 1,
            message => "$message_p: Cannot open $cmd_file: $!",
          );
        my $print_cmd = $self->task_cmd;
        $print_cmd =~ s/password=\S+/password=XXXXXXXX/g;
        print $lh "INITIAL_CMD: " . $print_cmd;
        close $lh;
    }

    my $daemon = Proc::Daemon->new(
        child_STDOUT => $log_file,
        child_STDERR => $log_file,
        pid_file     => $pid_file,
        exec_command => $self->task_cmd,
        work_dir     => $self->task_dir,
    );

    my $pid = $daemon->Init();

    if ($pid) {
        return Output->new(
            error => 0,
            data  => [
                $message_t,
                {
                    $task_id =>
                      { pid => $pid, status => "running", created => time },
                    "task_name" => $task_id

                }
            ],
        );
    }
    return Output->new(
        error   => 1,
        message => "$message_p: Cannot create background process"
    );

}

# kill defined process
sub stopProcess {
    my $self    = shift;
    my $task_id = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $task_dir = catfile( $self->task_dir, $task_id );
    if ( !-d $task_dir ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Not found task info"
        );
    }

    my $pid_file = catfile( $task_dir, "pid" );
    my $log_file = catfile( $task_dir, "status" );
    my $created  = ( stat($pid_file) )[10];

    my $daemon = Proc::Daemon->new( pid_file => $pid_file );
    my $pid = $daemon->Status();

    if ($pid) {
        if ( $daemon->Kill_Daemon($pid_file) ) {
            return Output->new(
                error => 0,
                data  => [
                    $message_t,
                    {
                        $task_id => {
                            pid     => $pid,
                            status  => "interrupt",
                            created => $created
                        },
                        "task_name" => $task_id
                    }
                ]
            );
        }
        else {
            return Output->new(
                error => 1,
                message =>
                  "$message_p: Could not find $pid_file. Was it running?",
                data => [
                    $message_t,
                    {
                        $task_id => {
                            pid     => $pid,
                            status  => "stopped",
                            created => $created
                        },
                        "task_name" => $task_id
                    }
                ],
            );
        }
    }
    else {
        return Output->new(
            error   => 0,
            message => "$message_p: Process isn't running, nothing to stop",
            data    => [
                $message_t,
                {
                    $task_id =>
                      { pid => $pid, status => "stopped", created => $created }
                }
            ],
        );
    }
}

sub clearHistory {
    my $self  = shift;
    my $older = shift;    # delete task infor that older than
    my $type  = shift;    # delete task with defined type

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $get_process = $self->listProcess();
    if ( $get_process->is_error ) {
        return $get_process;
    }

    my $older_time = time - $older * 86400;

    my %deleted_task  = ();
    my $deleted_count = 0;
    my $data_process  = $get_process->get_data->[1];
    foreach my $task_id ( keys %$data_process ) {
        my $modified = $data_process->{$task_id}->{'modified'};
        if ( $modified < $older_time ) {
            my $task_portrait_dir = catfile( $self->task_dir, $task_id );

            my $is_deleted = 1;
            if ( defined $type && $task_id !~ /^${type}_/ ) { $is_deleted = 0; }
            if ( $is_deleted == 1 ) {
                remove_tree($task_portrait_dir);
                $deleted_task{$task_id} = $data_process->{$task_id};
                $deleted_count++;
            }
        }
    }

    #print Dumper($data_process);
    if ( $deleted_count > 0 ) {
        return Output->new(
            error   => 0,
            message => "$message_p: deleted info about $deleted_count task",
            data    => [ $message_t, \%deleted_task ],
        );
    }
    else {
        return Output->new(
            error   => 0,
            message => "$message_p: not found tasks for removing",
        );
    }
}

1;
