#!/bin/bash
# send info with new network settings on client
# script used like ifup-local, we will create symblic link on it
export LANG=en_US.UTF-8
export TERM=linux
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
VERBOSE=0
BASE_DIR=/opt/webdir
LOGS_DIR=$BASE_DIR/logs
TEMP_DIR=$BASE_DIR/temp

. $BASE_DIR/bin/bitrix_utils.sh || exit 1

LOGS_FILE=$LOGS_DIR/update_network.log
CLIENT_CONFIG=/etc/ansible/ansible-roles
bx_network_script=$BASE_DIR/bin/bx-node

# change issue message (that used in login screen)
update_issue(){
    /opt/webdir/bin/bx_motd > /etc/issue.new 2>/dev/null
    mv -f /etc/issue.new /etc/issue
}

update_interface_in_pool(){
    # get current host ip address
    # ex.
    # /opt/webdir/bin/bx-node -a ip -i eth1
    _ip_data=$($bx_network_script -a ip -i $CLIENT_INT)
    _ip_err=$(echo "$_ip_data" | grep '^error:'   | sed -e "s/^error://")
    _ip_msg=$(echo "$_ip_data" | grep '^message:'   | sed -e "s/^message://")
    if [[ -n "$_ip_msg" ]]; then
        print_log "$_ip_msg" $LOGS_FILE
        exit 1
    fi

    _ip_addr=$(echo "$_ip_data" | grep '^info:pool_interfaces:netaddr' | \
        awk -F':' '{print $4}' | sed -e 's/^\s\+//;s/\s\+$//')
    if [[ -z "$_ip_addr" ]]; then
        print_log "Cannot defined IP address for $CLIENT_INT" $LOGS_FILE
        exit 1
    fi

    # test current ip address and saved ip address if daoesn't mutch send new to remote server
    [[ "$_ip_addr" == "$CLIENT_IP" ]] && exit 0

    # update master settings
    if [[ ( $IS_MASTER -eq 1 ) ]]; then 
        UPDATE_SEND=0
        update_master_settings "$_ip_addr" "$CLIENT_ID"
        if [[ $UPDATE_SEND -eq 1 ]]; then
            print_log "Update master server new network info" $LOGS_FILE
            exit 0
        fi
        exit 1
    # update client settings
    else
        UPDATE_SEND=0
        while [[ $UPDATE_SEND -eq 0 ]]; do
            update_client_settings "$_ip_addr"
            [[ $UPDATE_SEND -eq 0 ]] && sleep 60
        done

        if [[ $UPDATE_SEND -eq 1 ]]; then
            print_log "Send master server new network info" $LOGS_FILE
            exit 0
        else
            print_log "Error while send to master server client network interface info" $LOGS_FILE
            exit 1
        fi
    fi
}

update_system_settings(){

    [[ $IN_POOL -eq 0 ]] && exit 1
    if [[ ( ! -f /etc/cron.d/bx_network_updater ) || \
        ( $(grep -c "/opt/webdir/bin/update_network.sh" \
            /etc/cron.d/bx_network_updater) -eq 0 ) ]]; then
        echo "*/5 * * * * root /opt/webdir/bin/update_network.sh $CLIENT_INT" >> \
            /etc/cron.d/bx_network_updater
        print_log "Update /etc/cron.d/bx_network_updater file" $LOGS_FILE
    fi

    if [[ $(grep -c "/opt/webdir/bin/update_network.sh" /etc/rc.local) -eq 0 ]];then
        echo "/opt/webdir/bin/update_network.sh $CLIENT_INT" >> /etc/rc.local
        print_log "Add /opt/webdir/bin/update_network.sh to /etc/rc.local" $LOGS_FILE
    fi
    exit 0

}
# exit if not client
[[ ! -f $CLIENT_CONFIG ]] && exit 0
INTERFACE=$1			# interface name, while ifup system get it to the script


# get client info from config file
# variables CLIENT_ID, CLIENT_PASSWD, CLIENT_INT, CLIENT_IP
#           MASTER_IP, MASTER_NAME
get_client_settings

if [[ -z $INTERFACE ]]; then
    update_system_settings
else
    # update settings in /etc/issue
    update_issue

    # not pool interface
    [[ "$INTERFACE" != "$CLIENT_INT" ]] && exit 0 

    # there are no pool or this host is master
    [[ ( $IN_POOL -eq 0 ) ]] && exit 0

    # test current setings and update pool
    update_interface_in_pool
fi

