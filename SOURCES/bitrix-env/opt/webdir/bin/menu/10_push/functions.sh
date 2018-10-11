BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_process_script=$BIN_DIR/bx-process
bx_host_script=$BIN_DIR/wrapper_ansible_conf
bx_web_script=$BIN_DIR/bx-sites

submenu_dir=$BIN_DIR/menu/10_push
push_menu=$submenu_dir
ansible_web_group=/etc/ansible/group_vars/bitrix-web.yml

mysql_menu_dir=$BIN_DIR/menu/03_mysql
mysql_menu_fnc=$mysql_menu_dir/functions.sh
. $mysql_menu_fnc || exit 1

# get_text variables
[[ -f $push_menu/functions.txt ]] && \
    . $push_menu/functions.txt

# get status for web servers
# return
# PUSH_SERVERS - list of web servers
# PUSH_SERVERS_CNT - number of push server 
get_push_servers_status(){
    PUSH_SERVERS=
    PUSH_SERVERS_CNT=0
    NODE_PUSH_SERVER=
    NGX_PUSH_SERVER=

    # get info from ansible configuration
    local info=$($bx_host_script)
    local erro=$(echo "$info" | grep '^error:' | sed -e "s/^error://")
    local mesg=$(echo "$info" | grep '^message:' | sed -e "s/^message://")
    if [[ -n $erro ]]; then
        print_message \
            "Failed to get web servers status. Press ENTER for exit:" \
            "$mesg" "" any_key
        exit
    fi

    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $info; do
        hostname=$(echo "$line" | awk -F':' '{print $2}')
        ipaddr=$(echo "$line" | awk -F':' '{print $3}')
        groups=$(echo "$line" | awk -F':' '{print $4}')

        if [[ $(echo "$groups" | grep -wc "push") -gt 0 ]]; then
            NODE_PUSH_SERVER="$hostname"
        fi
        if [[ $(echo "$groups" | grep -wc "mgmt") -gt 0 ]]; then
            NGX_PUSH_SERVER="$hostname"
        fi
    done
    # NginxStreamModule is enabled by default and we don't have sign for it
    [[ -n $NODE_PUSH_SERVER ]] && \
        NGX_PUSH_SERVER=

    for line in $info; do
        hostname=$(echo "$line" | awk -F':' '{print $2}')
        ipaddr=$(echo "$line" | awk -F':' '{print $3}')
        groups=$(echo "$line" | awk -F':' '{print $4}')

        if [[ ( -n $NODE_PUSH_SERVER ) && ( $hostname == "$NODE_PUSH_SERVER" ) ]]; then
            PUSH_VERSION=$($bx_host_script -a bx_info -H $hostname -o json | \
               egrep -o '"push_server_major_version":"[0-9]+"' | awk -F'"' '{print $4}' )
            PUSH_SERVERS=$PUSH_SERVERS"
NodeJS-PushServer:$hostname:$ipaddr:$PUSH_VERSION"
            continue
        fi

        if [[ ( -z $NODE_PUSH_SERVER ) && ( $hostname == "$NGX_PUSH_SERVER" ) ]];then
            PUSH_SERVERS=$PUSH_SERVERS"
Nginx-PushStreamModule:$hostname:$ipaddr"
            continue
        fi

        PUSH_SERVERS=$PUSH_SERVERS"
Not-Used:$hostname:$ipaddr"

    done

    IFS=$IFS_BAK
    IFS_BAK=
    if [[ -n $NODE_PUSH_SERVER ]]; then
        PUSH_SERVERS_CNT=1
    fi
}

cache_push_servers_status(){
    PUSH_SERVERS=
    PUSH_SERVERS_CACHE=$CACHE_DIR/push_servers_status.cache             # cache file
    PUSH_SERVERS_CACHE_LT=3600                                         # live time for cache file in seconds

    test_cache_file $PUSH_SERVERS_CACHE $PUSH_SERVERS_CACHE_LT
    if [[ $? -gt 0 ]]; then
        get_push_servers_status
        echo "$PUSH_SERVERS" > $PUSH_SERVERS_CACHE
    else
        PUSH_SERVERS=$(cat $PUSH_SERVERS_CACHE)
        PUSH_SERVERS_CNT=$(echo "$PUSH_SERVERS" | grep -c "^NodeJS-PushServer:")
        NODE_PUSH_SERVER=$(echo "$PUSH_SERVERS" | grep "^NodeJS-PushServer:" | \
            awk -F':' '{print $2}')
        NGX_PUSH_SERVER=$(echo "$PUSH_SERVERS" | grep "^Nginx-PushStreamModule:" | \
            awk -F':' '{print $2}')
        if [[ -n "$NODE_PUSH_SERVER" ]]; then
            PUSH_VERSION=$(echo "$PUSH_SERVERS" | grep "^NodeJS-PushServer:" | \
            awk -F':' '{print $4}')
        fi
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "PUSH_SERVERS=$PUSH_SERVERS"
        echo "PUSH_SERVERS_CNT=$PUSH_SERVERS_CNT"
        echo "PUSH_VERSION=$PUSH_VERSION"
    fi
}


print_push_servers_status(){
    local exclude=$1            # exclude servers by hostname
    local push_only=${2:-0}     # show only push servers

    cache_push_servers_status
    PUSH_SERVERS_FILTERED="$PUSH_SERVERS"
    
    PUSH_SERVERS_FILTERED_CNT=0
    [[ $push_only -gt 0 ]] && \
        PUSH_SERVERS_FILTERED=$(echo "$PUSH_SERVERS" | \
         grep "^\(Nginx-PushStreamModule\|NodeJS-PushServer\):")

    if [[ -n $exclude ]]; then
        PUSH_SERVERS_FILTERED=$(echo "$PUSH_SERVERS_FILTERED" | grep -v "^$" | egrep -v ":$exclude:")
    fi
    PUSH_SERVERS_FILTERED_CNT=$(echo "$PUSH_SERVERS_FILTERED" | grep -vc "^$" )
   
    if [[ $PUSH_SERVERS_FILTERED_CNT -eq 0 ]]; then
        echo "No matching servers were found."
        [[ -n $exclude ]] &&  echo "Exclude: $exclude"   
        [[ $push_only -gt 0 ]] && echo "Show only push-server."
        echo
        return 1
    fi

    echo "Found $PUSH_SERVERS_FILTERED_CNT servers"
    [[ -n $exclude  ]] && echo "Exclude: $exclude"

    echo $MENU_SPACER
    printf "%-17s | %20s| %s\n" \
        "Hostname" "IP" "Type"
    echo $MENU_SPACER

    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $PUSH_SERVERS_FILTERED; do
        echo "$line" | \
            awk -F':' '{printf "%-17s | %20s| %s\n", \
            $2, $3, $1}'
    done
    IFS=$IFS_BAK
    IFS_BAK=
        
    echo $MENU_SPACER
    echo
}
