package Host;
use Moose;
use File::Basename qw( dirname basename );
use File::Spec::Functions;
use Data::Dumper;
use Output;
use JSON;
use Pool;
use bxInventory qw( get_from_yaml save_to_yaml );

has 'host', is => 'ro', isa => 'Str';
has 'ip', is => 'ro', isa => 'Str', lazy => 1, builder => 'get_ipaddress';
has 'debug', is => 'ro', lazy => 1, default => 0;
has 'logfile', is => 'ro', default => '/opt/webdir/logs/host_manage.debug';

# test if host with hostname in the pool
# 1 -> pool_not_created
# 2 -> host_not_in_pool
# 3 -> host_in_pool_not_in_group
# 0 -> host_in_pool
sub host_in_pool {
    my ( $self, $group, $hostname )  = @_;

    if ( not defined $hostname ) {
        $hostname = $self->host;
    }
    $hostname =~ s/^["']//;
    $hostname =~ s/["']$//;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my %returnMessage = (
        1 => 'pool_not_created',
        2 => 'host_not_in_pool',
        3 => 'host_in_pool_not_in_group',
        0 => 'host_in_group',
    );
    my $rt = 0;

    my $pool          = Pool->new();
    my $getConfigData = $pool->get_ansible_data;
    if ( $getConfigData->is_error > 0 ) {
        $rt = 1;
        if ($debug) { $logOutput->log_data("$message_p: pool is not created"); }
    }
    else {
        if ($debug) {
            $logOutput->log_data(
                "$message_p: pool exists, try found host $hostname");
        }

        # get all data for hosts in the pool
        my $configData     = $getConfigData->get_data;
        my $configHostData = $configData->[1]->{$hostname};

        # no host :(
        if ( !$configHostData ) {
            $rt = 2;
            if ($debug) {
                $logOutput->log_data(
                    "$message_p:  host $hostname not found in pool");
            }

            # host found
        }
        else {

            # if group set => we need check group
            if ( $group && $group !~ /^hosts$/ ) {
                my $host_groups =
                  grep( /^$group$/, keys %{ $configHostData->{'roles'} } );

                # roles not found = group not found
                if ( $host_groups == 0 ) {
                    if ($debug) {
                        $logOutput->log_data(
                            "$message_p:  host $hostname not found in $group");
                    }
                    $rt = 3;
                }
            }
        }
    }

    if ($debug) {
        $logOutput->log_data(
            "$message_p: search finished, " . $returnMessage{$rt} );
    }
    return Output->new( error => $rt, message => $returnMessage{$rt} );
}

sub onfly_host_test {
    my $self      = shift;
    my $shortname = shift;
    my $netaddr   = shift;

    my $ipaddr = $netaddr;
    if ( $netaddr !~ /^[\d\.]+$/ ) {
        my $bx_net = bxNetwork->new( netaddr => $netaddr, host => $shortname );
        $ipaddr = $bx_net->a_lookup($netaddr);
    }

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );
    if ($debug) { $logOutput->log_data("$message_p: start testing"); }

    my $pool      = Pool->new();
    my $conf_data = $pool->get_ansible_data();
    my $ans_data  = $pool->set_ansible_conf();
    if ( $conf_data->is_error ) { return $conf_data }
    my @servers = sort keys %{ $conf_data->get_data->[1] };

    if ($debug) {
        $logOutput->log_data( "$message_p: found " . join( ',', @servers ) );
    }

    my $cmd_exec    = $ans_data->{'ansible'};
    my $cmd_module  = 'bx_vat';
    my $cmd_library = $ans_data->{'library'};
    foreach my $server (@servers) {
        if ($debug) {
            $logOutput->log_data("$message_p:  process server $server");
        }
        my $cmd_run =
          qq($cmd_exec $server -m "$cmd_module" -M "$cmd_library" 2>/dev/null);
        open( my $rh, "$cmd_run |" ) or next;
        my $json_output = "";
        while (<$rh>) {
            if (/^$server\s*\|\s*(\S+)\s*\>\>\s*\{\s*/) {
                my $result = $1;
                if ( $result =~ /^success$/i ) {
                    $json_output = $json_output . "\{";
                    next;
                }
            }

            if ( $json_output !~ /^$/ ) {
                $json_output = $json_output . $_;
            }
        }
        close $rh;

        #print "|$json_output|\n";

        if ( $json_output !~ /^$/ ) {
            my $ansible_facts = from_json($json_output);
            my $server_info   = $ansible_facts->{'ansible_facts'};

            for my $addr_info ( grep /^addr/, keys %$server_info ) {
                my $addr_ip = $server_info->{$addr_info};
                if ( $addr_ip =~ /^$ipaddr$/ ) {
                    my $int = $addr_info;
                    $int =~ s/^addr_//;
                    return Output->new(
                        error => 1,
                        message =>
"$message_t: $server already in the pool (ip=$addr_ip interface=$int)",
                    );
                }
            }
        }
    }

    return Output->new(
        error   => 0,
        message => "$message_t: $ipaddr not found"
    );
}

# get info from ansible config
sub get_ipaddress {
    my $self = shift;

    my $hostname = $self->host;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $test_host = $self->host_in_pool;
    my $ipaddres  = '';

    if ($debug) {
        $logOutput->log_data("$message_p: try found netaddress for $hostname");
    }

    # pool is not created = imossible, but :)
    if ( $test_host->is_error == 1 ) {
        if ($debug) {
            $logOutput->log_data(
                "$message_p: test host in the pool return error");
        }
        return $hostname;

        # host not in the pool: get address from DNS server
    }
    elsif ( $test_host->is_error == 2 or $test_host->is_error == 3 ) {

        my $bx_n = bxNetwork->new( host => $hostname );
        my $bx_net_info = $bx_n->network_info;
        if ( $bx_net_info->is_error ) {
            if ($debug) {
                $logOutput->log_data(
                    "$message_p: search netaddress by hostname return error");
            }
            return $hostname;
        }

        $ipaddres = $bx_net_info->get_data->[1]->{'netaddr'};
        if ($debug) {
            $logOutput->log_data(
                "$message_p: host=$hostname netaddr=$ipaddres");
        }

        # get address from pool configuration
    }
    else {
        my $bx_pool = Pool->new();
        my $bx_data = $bx_pool->get_ansible_data;
        my $bx_conf = $bx_data->get_data;
        $ipaddres = $bx_conf->[1]->{$hostname}->{'ip'};
        if ($debug) {
            $logOutput->log_data(
                "$message_p: host=$hostname netaddr=$ipaddres");
        }
    }

    #print $ipaddres,"\n";
    return $ipaddres;
}

sub get_bx_dbs {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $hostname = Pool::esc_chars( $self->host );

    my $pool        = Pool->new();
    my $ansData     = $pool->set_ansible_conf();
    my $cmd_play    = $ansData->{'ansible'};
    my $cmd_module  = 'bx_db';
    my $cmd_library = $ansData->{'library'};

    my $cmd_run = qq($cmd_play $hostname -m "$cmd_module" -M "$cmd_library");
    open( my $rh, "$cmd_run |" )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot run $cmd_module on $hostname",
      );

    my $json_output = "";
    while (<$rh>) {
        if (/^$hostname\s*\|\s*(\S+)\s*\>\>\s*\{\s*/) {
            my $result = $1;
            if ( $result =~ /^success$/i ) {
                $json_output = $json_output . "\{";
                next;
            }
            else {
                return Output->new(
                    error   => 1,
                    message => "$message_p: \`$cmd_run\` return $result",
                );
            }
        }

        if ( $json_output !~ /^$/ ) {
            $json_output = $json_output . $_;
        }
    }
    close $rh;

    my $ansible_facts = from_json($json_output);
    my $server_info   = $ansible_facts->{'ansible_facts'};
    return Output->new(
        error => 0,
        data  => [ 'dbs_list', { $hostname => $server_info } ],
    );
}

sub get_bx_info {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $hostname = Pool::esc_chars( $self->host );

    my $pool        = Pool->new();
    my $ansData     = $pool->set_ansible_conf();
    my $cmd_play    = $ansData->{'ansible'};
    my $cmd_module  = 'bx_vat';
    my $cmd_library = $ansData->{'library'};

    my $cmd_run =
      qq($cmd_play $hostname -m "$cmd_module" -M "$cmd_library" 2>&1);

      #print "$cmd_run\n";
    open( my $rh, "$cmd_run |" )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot run $cmd_module on $hostname",
      );

    my $json_output = "";
    my $erro_output = "";
    while (<$rh>) {
        if (   /^$hostname\s*\|\s*(\S+)\s*\>\>\s*\{\s*/
            or /^$hostname\s*\|\s*(\S+)\s*=\>(.*)$/ )
        {
            my $result = $1;
            my $opt = ($2) ? $2 : "";
            $opt =~ s/^\s+//;
            $opt =~ s/\s+$//;
            if ( $result =~ /^success$/i ) {
                $json_output = $json_output . "\{";
                next;

                # vm03 | FAILED => SSH Error: ssh:
            }
            else {
                return Output->new(
                    error   => 1,
                    message => "$message_p: $opt",
                );
            }
        }
        elsif (/^No hosts matched$/) {
            return Output->new(
                error   => 1,
                message => "$message_p: Not found $hostname in the pool",
            );
        }

        if ( $json_output !~ /^$/ ) {
            $json_output = $json_output . $_;
        }
    }
    close $rh;

    my $ansible_facts = from_json($json_output);
    my $server_info   = $ansible_facts->{'ansible_facts'};
    return Output->new(
        error => 0,
        data  => [ 'bx_variables', { $hostname => $server_info } ],
    );
}

# update data in the host vars file
sub update_host_vars {
    my $self    = shift;
    my $options = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    # test if host exists
    my $host = $self->host;

    #print "1. test hot in pool\n";
    my $host_status = $self->host_in_pool();

    #print Dumper($host_status);
    if ( $host_status->is_error ) {
        return $host_status;
    }

    if ( not defined $options ) {
        return Output->new(
            error   => 1,
            message => "$message_p: Need defined hash with options list"
        );
    }

    # get pool information
    my $bx_pool        = Pool->new();
    my $an_data        = $bx_pool->ansible_conf;
    my $host_vars_path = catfile( $an_data->{'host_vars'}, $host );
    my $host_vars_temp = $host_vars_path . ".temp";
    my $host_vars_live = ( -f $host_vars_path ) ? 1 : 0;


    my $inventory_data;
    if ($host_vars_live){
        my $get_inventory = get_from_yaml($host_vars_path);
        if ( $get_inventory->is_error ) { 
            return $get_inventory;
        }
        $inventory_data = $get_inventory->data->[1];
 
    }


    ##print "2. create updated and deleted options hash\n";
    # return structure
    my $updates = 0;
    my $deletes = 0;
    foreach my $k ( keys %$options ) {
        next if ($k =~ /^(group|state|hostname)$/);
        #print "$k => $options->{$k}\n";

        # key=value
        if (defined $options->{$k}){
            if (defined $inventory_data->{$k}){
                if ($inventory_data->{$k} ne $options->{$k}){
                    $inventory_data->{$k} = $options->{$k};
                    $updates++;
                }
            }
            else {
                $inventory_data->{$k} = $options->{$k};
                $updates++;
            }
        }
        # key
        else {
            if (defined $inventory_data->{$k}){
                delete $inventory_data->{$k};
                $deletes++;
            }
        }
    }

    # update values or create new
    my $save_inventory = save_to_yaml($inventory_data, $host_vars_temp);
    if ( $save_inventory->is_error ) { 
        return $save_inventory;
    }

    # rewrite origin file
    unlink $host_vars_path if ($host_vars_live);
    rename $host_vars_temp, $host_vars_path;
    chmod 0640, $host_vars_path;

    return Output->new(
        error => 0,
        message => "$message_p: " 
            . "File=$host_vars_path is modified; updates=$updates deletes=$deletes",
        data => ["$message_p", 
            {updates => $updates, deletes => $deletes, file => $host_vars_path}]
    );
}

# add host to group, if group not defined add host to pool
sub add_to_group {
    my ( $self, $group, $is_update ) = @_;

    if ( not defined $is_update ) {
        $is_update = 0;
    }

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $hostname = $self->host;
    my $ipaddres = $self->ip;


    my $mess = ( defined $group ) ? "$group" : "hosts";
    if ($debug) {
        $logOutput->log_data("$message_p: start add host $hostname to $mess");
    }

    # create hostname if request by IP
    if ( $mess =~ /^hosts$/ && $hostname =~ /^$ipaddres$/ ) {

        # get localhost hostname and ip address
        my $bx_n = bxNetwork->new( netaddr => $hostname );
        my $bx_net_info = $bx_n->network_info;
        if ( $bx_net_info->is_error ) { return $bx_net_info; }
        $hostname = $bx_net_info->get_data->[1]->{'host'};
        $ipaddres = $bx_net_info->get_data->[1]->{'netaddr'};
        if ($debug) {
            $logOutput->log_data(
                "$message_p:  update hostname=$hostname netaddr=$ipaddres");
        }
    }

    my $status = $self->host_in_pool( $group, $hostname );

    ## 0 => host exists in defined group
    if ( !$status->is_error ) {
        if ($debug) {
            $logOutput->log_data("$message_p: host $hostname in $mess");
        }
        return Output->new(
            error   => 0,
            message => "$message_p: $hostname already in $mess",
        );
    }
    ## 1 => pool is not created
    if ( $status->is_error == 1 ) {
        if ($debug) { $logOutput->log_data("$message_p: pool is not created"); }
        return $status;
    }


    my $pool    = Pool->new();
    my $ansData = $pool->set_ansible_conf();
    my $bxData  = $pool->set_bitrix_conf();
    my $cfgData = $pool->get_ansible_data();
    my $mStatus = $pool->monitorStatus()->get_data()->[1]->{monitoring_status};

    #print Dumper($cfgData);
    my $section_prefix = $bxData->{'aHostsPrefix'};

    # create updated_groups
    my %updated_groups;
    if ( defined $group ) {
        $updated_groups{$group} = 0;
    }

    # 2 => host not in main group hosts ( update $group and hosts)
    if ( $status->is_error == 2 ) {
        $updated_groups{ $bxData->{'aHostsDefault'} } = 0;
        if ($debug) {
            $logOutput->log_data(
                "$message_p:  need add $hostname to hosts group");
        }
    }

    # add host to group(s):
    my $ans_hosts_path = $ansData->{'hosts'};
    my $ans_hosts_temp = $ans_hosts_path . ".tmp";

    open( my $hh, $ans_hosts_path )
      or return Output->new(
        error   => 2,
        message => "$message_p: Cannot open $ans_hosts_path: $!"
      );
    open( my $th, ">$ans_hosts_temp" )
      or return Output->new(
        error   => 2,
        message => "$message_p: Cannot open $ans_hosts_temp: $!"
      );

    # create temporary file with new data
    while (<$hh>) {
        s/^\s+//;
        s/\s+$//;
        print $th $_, "\n";

        if (/^\[$section_prefix\-([^\]]+)\]$/) {
            my $found = $1;
            if ( grep /^$found$/, keys %updated_groups ) {
                print $th "$hostname ansible_ssh_host=$ipaddres\n";
                $updated_groups{$found} = 1;
                if ($debug) {
                    $logOutput->log_data("$message_p:   add host to $found");
                }
            }
        }
    }

    close $hh;
    close $th;

    # test if all updates done
    foreach my $k ( keys %updated_groups ) {
        if ( $updated_groups{$k} == 0 ) {
            if ($debug) {
                $logOutput->log_data("$message_p: not updated $k. exit");
            }
            return Output->new(
                error   => 1,
                message => "$message_p: Cannot update group $k",
            );
        }
    }

    # create backup for current config and replace it by temporary file
    if ( $is_update == 0 ) {
        unlink $ans_hosts_path;
        rename $ans_hosts_temp, $ans_hosts_path;

        # run common playbook
        # set network, time
        my $cmd_play = $ansData->{'playbook'};
        my $cmd_conf = catfile( $ansData->{'base'}, "common.yml" );
        my $cmd_type = "common";
        if ( defined $mStatus && $mStatus eq "enable" ) {
            $cmd_conf = catfile( $ansData->{'base'}, "monitor.yml" );
            $cmd_type = "monitor";
        }

        # run as daemon in background
        my $dh = bxDaemon->new( task_cmd => qq($cmd_play  $cmd_conf) );
        if ($debug) {
            $logOutput->log_data(
                "$message_p: start common task for new $hostname");
        }
        my $created_process = $dh->startProcess($cmd_type)->get_data()->[1];
        my ($task_id) = grep {!/^task_name$/} keys %$created_process;
        my $task_pid = $created_process->{$task_id}->{pid};
        my $task_status = $created_process->{$task_id}->{status};


        return Output->new(
            error   => 0,
            message => "$message_p: succefully added $hostname to group(s)",
            data    => [ 'hosts_file', $ans_hosts_path, [$task_id, $task_pid, $task_status] ]
        );
    }
    else {
        if ($debug) {
            $logOutput->log_data(
                "$message_p: succefully added $hostname to group(s)");
        }
        return Output->new(
            error   => 0,
            message => "$message_p: succefully added $hostname to group(s)",
            data    => [ 'hosts_file', $ans_hosts_temp ]
        );
    }
}

# delete host from group, if group not defined - delete from all pool groups
# 1 => 'pool_not_created',
# 2 => 'host_not_in_pool',
# 3 => 'host_in_pool_not_in_group',
# 0 => 'host_in_group',
sub del_from_group {
    my $self  = shift;
    my $group = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $hostname = $self->host;

    # test if host in the pool
    my $status = $self->host_in_pool($group);
    my $mess = ( defined $group ) ? "$group" : "hosts";
    if ( $status->is_error ) {
        return Output->new(
            error   => 0,
            message => "$message_p: $hostname not found in group $mess"
        );
    }

    # get pool configuration
    my $bx_pool   = Pool->new();
    my $ans_conf  = $bx_pool->set_ansible_conf();
    my $bx_conf   = $bx_pool->set_bitrix_conf();
    my $pool_conf = $bx_pool->get_ansible_data();
    if ( $pool_conf->is_error ) { return $pool_conf; }

    # test if host hold roles
    my $host_conf  = $pool_conf->get_data->[1]->{$hostname};
    my @host_roles = sort keys %{ $host_conf->{'roles'} };
    my $host_roles = @host_roles;
    if ( $mess =~ /^hosts$/ && $host_roles > 0 ) {
        return Output->new(
            error => 1,
            message =>
              "$message_t: Cannot delete host $hostname, it hold next roles: "
              . join( ', ', @host_roles )
        );
    }

    # group names options
    my $section_prefix  = $bx_conf->{'aHostsPrefix'};
    my $section_default = $bx_conf->{'aHostsDefault'};

    # ansible playbook settings
    my $cmd_play = $ans_conf->{'playbook'};
    my $cmd_conf = catfile( $ans_conf->{'base'}, "common.yml" );

    # remove ssh options from server is main group
    if ( $mess =~ /^hosts$/ ) {
        my $cmd_opt = "common_server=$hostname common_manage=remove";
        my $cmd_run = qq($cmd_play $cmd_conf -e "$cmd_opt" 1>/dev/null 2>&1);
        system($cmd_run) == 0
          or return Output->new(
            error => 1,
            message =>
              "$message_p: Cannot remove ssh options from host $hostname",
          );
    }

    # delete host from group
    my $ans_hosts_path = $ans_conf->{'hosts'};
    my $ans_hosts_temp = $ans_hosts_path . ".tmp";
    open( my $hh, $ans_hosts_path )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $ans_hosts_path: $!"
      );
    open( my $th, ">$ans_hosts_temp" )
      or return Output->new(
        error   => 1,
        message => "$message_p: Cannot open $ans_hosts_temp: $!"
      );

    # create temporary file with new data
    # if group defined = > delete only from this group
    # else delete from all group in the pool
    my $pool_config_changed = 0;
    my $section_name        = "";
    my $is_deleted_section  = 0;
    while (<$hh>) {
        chomp;
        s/^\s+//;
        s/\s+$//;
        my $str = $_;

        # section pool is found
        if ( $str =~ /^\[$section_prefix-([^\]]+)\]/ ) {
            $section_name       = $1;
            $is_deleted_section = 1;    # default delete

            # change opinion about the removal
            if (   $group
                && $group !~ /^$section_default$/
                && $section_name !~ /^$group$/ )
            {
                $is_deleted_section = 0;
            }
        }

        # option found
        if ( /^$hostname\s+(.+)$/ && $is_deleted_section == 1 ) {
            $pool_config_changed++;
            next;
        }

        print $th $_, "\n";
    }

    close $hh;
    close $th;
    if ( $pool_config_changed == 0 ) {
        return Output->new(
            error   => 3,
            message => "$message_p: Cannot delete host from the group $mess"
        );
    }

    # backup and rename
    rename $ans_hosts_path, $ans_hosts_path . ".bak";
    rename $ans_hosts_temp, $ans_hosts_path;

    # update security option on hosts that left in the pool
    my $dh = bxDaemon->new( task_cmd => qq($cmd_play  $cmd_conf) );
    my $created_process = $dh->startProcess('common');

    return Output->new(
        error   => 0,
        message => "$message_p: successful deleted host $hostname from pool"
    );

}

sub removeHostFromPool {
    my $self  = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;
    my $debug     = $self->debug;
    my $logOutput = Output->new( error => 0, logfile => $self->logfile );

    my $hostname = $self->host;

    # test if host in the pool
    my $status = $self->host_in_pool();
    if ( $status->is_error ) {
        return Output->new(
            error   => 0,
            message => "$message_p: $hostname not found in the pool."
        );
    }

    # get pool configuration
    my $bx_pool   = Pool->new();
    my $ans_conf  = $bx_pool->set_ansible_conf();
    my $pool_conf = $bx_pool->get_ansible_data();
    if ( $pool_conf->is_error ) { return $pool_conf; }

    # test if host hold roles
    my $host_conf  = $pool_conf->get_data->[1]->{$hostname};
    my @host_roles = sort keys %{ $host_conf->{'roles'} };
    my $host_roles = @host_roles;
    if ( $host_roles > 0 ) {
        return Output->new(
            error => 1,
            message =>
              "$message_t: Cannot delete host $hostname, it hold next roles: "
              . join( ', ', @host_roles )
        );
    }

    # ansible playbook settings
    my $cmd_play = $ans_conf->{'playbook'};
    my $cmd_conf = catfile( $ans_conf->{'base'}, "common.yml" );

    # clean up ssh configuration, ansible variables and etc,
    my $opts = {
        common_server => $hostname,
        common_manage => 'remove',
    };
    my $dh = bxDaemon->new(
        debug    => $self->debug,
        task_cmd => qq($cmd_play $cmd_conf)
    );
    my $created_process = $dh->startAnsibleProcess( "remove_$hostname", $opts  );
    return $created_process;
 
}

# create host in the pool
sub createHost {
    my $self = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    my $debug      = $self->debug;
    my $logOutput  = Output->new( error => 0, logfile => $self->logfile );
    my $err_regexp = '(localhost|127\.0\.0\.\d+|localhost.localdomain)';

    my $hostname = $self->host;
    my $ipaddres = $self->ip;
    if (not defined $hostname){
        return Output->new(
            error => 1,
            message => "Cannot use empty hostname"
        )
    }

    if ($debug) {
        $logOutput->log_data(
"$message_p: start created host hostname=$hostname netaddr=$ipaddres"
        );
    }

    # if user try add host=127.0.0.1 => ERROR
    if ( $hostname =~ /^$err_regexp$/ || $ipaddres =~ /^$err_regexp$/ ) {
        if ($debug) {
            $logOutput->log_data(
"$message_p: cannot add to pool hostname=$hostname netaddr=$ipaddres"
            );
        }

        return Output->new(
            error   => 1,
            message => "$message_p: cannot use $hostname for add",
        );
    }

    # generate host options
    my $po        = Pool->new();
    my $host_id   = $po->generate_host_id;
    my $host_pass = $po->generate_host_password($hostname);
    my $options   = {
        group       => 'hosts',
        host_id     => $host_id,
        host_pass   => $host_pass,
        bx_hostname => $hostname,
        bx_netaddr  => $ipaddres,
        bx_connect  => 'ipv4',
        bx_netname  => $hostname,
    };
    #print Dumper($options);

    # if user input the same netaddress and hostname
    # case1: hostname=example.org and ipaddress=example.org
    # case2: hostname=1.2.3.4 ipaddres=1.2.3.4
    if ( $hostname =~ /^$ipaddres$/ ) {

        # case1: example.org
        if ( $hostname !~ /^[\d\.]+$/ ) {

            # get ipaddress
            my $bx_n = bxNetwork->new( netaddr => $ipaddres );
            $options->{'bx_netaddr'} = $bx_n->a_lookup($hostname);
            if ( $options->{'bx_netaddr'} =~ /^$/ ) {
                return Output->new(
                    error   => 1,
                    message => "$message_p: $hostname is not a valid DNS name",
                );
            }
            $options->{'bx_connect'} = 'fqdn';

        # case2: 1.2.3.4 - we must defined correct hostname and ident for host
        }
        else {
            my $bx_n = bxNetwork->new( netaddr => $ipaddres );
            my $bx_net_info = $bx_n->network_info;
            if ( $bx_net_info->is_error ) { return $bx_net_info; }
            my $bx_net_data = $bx_net_info->get_data->[1];
            my $type        = $bx_net_data->{'type'};

            if ( $type =~ /^fqdn$/ ) {
                $options->{'bx_hostname'} = $bx_net_data->{'netaddr'};
                $options->{'bx_netname'}  = $bx_net_data->{'netaddr'};
            }
            else {
                $options->{'bx_hostname'} = $bx_net_data->{'host'};
                $options->{'bx_netname'}  = $bx_net_data->{'host'};
            }
            if ($debug) {
                $logOutput->log_data(
                    "$message_p: change hostname=$hostname to "
                      . $options->{'bx_netname'} );
            }
        }

        # hostname=example ip=example.org
        # or
        # hostname example ip=1.2.3.4
    }
    else {

        #$options->{'bx_hostname'} =~ s/^([^\.]+)\..+/$1/;
        # test fqdn name: example.org
        if ( $ipaddres !~ /^[\d\.]+$/ ) {
            my $bx_n = bxNetwork->new( netaddr => $ipaddres );
            $options->{'bx_netaddr'} = $bx_n->a_lookup($ipaddres);

            if ( $options->{'bx_netaddr'} =~ /^$/ ) {
                return Output->new(
                    error   => 1,
                    message => "$message_p: $ipaddres is not a valid DNS name",
                );
            }
            $options->{'bx_connect'} = 'fqdn';
            $options->{'bx_netname'} = $ipaddres;
        }
    }

    my $new_host = Host->new(
        host => $options->{'bx_hostname'},
        ip   => $options->{'bx_netaddr'}
    );

    # test instance by its working option (not saved in the config files)
    #my $test_all_host_ints = $new_host->onfly_host_test($hostname, $ipaddres);
    #if ($test_all_host_ints->is_error){ return $test_all_host_ints };

    # add host to group if one defined
    my $group_mod    = "no";
    my $update_group = $new_host->add_to_group( $options->{'group'} );
    if ($debug) { $logOutput->log_data("$message_p: add host to group hosts"); }
    my $update_group_data = $update_group->get_data();
    my $task_id = "";
    my $task_pid = 0;
    my $task_status = "";
    if (defined $update_group_data->[2]){
        $task_id = $update_group_data->[2]->[0];
        $task_pid = $update_group_data->[2]->[1];
        $task_status = $update_group_data->[2]->[2];
    }

    if ( $update_group->is_error ) {
        return $update_group;
    }

    $group_mod = "yes";

    #print Dumper($new_host);
    my $host_mod    = "no";
    my $update_host = $new_host->update_host_vars($options);

    #print Dumper($update_host);
    if ( $update_host->is_error ) {
        return $update_host;
    }
    if ($debug) { $logOutput->log_data("$message_p: update host vars"); }
    $host_mod = "yes";

    return Output->new(
        error => 0,
        message =>
            "$message_p: modification was successful,"
            . " host_vars=$host_mod, hosts=$group_mod"
            . " task_id=$task_id task_pid=$task_pid task_status=$task_status",
        data => [ $message_p, { hosts => $group_mod, host_vars => $host_mod } ]
    );
}

# update host info by defined options
sub updateHost {
    my $self    = shift;
    my $options = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    # test if host exists
    my $host = $self->host;

    # add host to group if one defined
    my $group_mod = "no";
    if ( defined $options->{'group'} ) {
        my $update_group = $self->add_to_group( $options->{'group'} );
        if ( $update_group->is_error ) {
            return $update_group;
        }
        $group_mod = "yes";
    }

    # update additional variables if it defined
    #print Dumper($options);
    my $plus_option = grep( !/^(state|group|hostname)$/, keys %$options );
    my $host_mod = "no";
    if ( $plus_option > 0 ) {
        my $update_host = $self->update_host_vars($options);
        if ( $update_host->is_error ) {
            return $update_host;
        }
        $host_mod = "yes";
    }

    return Output->new(
        error => 0,
        message =>
"$message_p: modification was successful, host_vars=$host_mod, hosts=$group_mod",
        data => [ $message_p, { hosts => $group_mod, host_vars => $host_mod } ]
    );
}

# delete host from group
sub deleteHost {
    my $self    = shift;
    my $options = shift;

    my $message_p = ( caller(0) )[3];
    my $message_t = __PACKAGE__;

    # test if host exists
    my $group_mod = "no";
    if ( defined $options->{'group'} ) {
        my $update_group = $self->del_from_group( $options->{'group'} );
        if ( $update_group->is_error ) {
            return $update_group;
        }
        $group_mod = "yes";
    }

    # update additional variables if it defined
    my $plus_option = grep( !/^(state|group|hostname)$/, keys %$options );
    my $host_mod = "no";
    if ( $plus_option > 0 ) {
        my $update_host = $self->update_host_vars($options);
        if ( $update_host->is_error ) {
            return $update_host;
        }
        $host_mod = "yes";
    }

    return Output->new(
        error => 0,
        message =>
"$message_p: modification was successful, host_vars=$host_mod, hosts=$group_mod",
        data => [ $message_p, { hosts => $group_mod, host_vars => $host_mod } ]
    );
}

1;
