BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_process_script=$BIN_DIR/bx-process
bx_host_script=$BIN_DIR/wrapper_ansible_conf
bx_web_script=$BIN_DIR/bx-sites

submenu_dir=$BIN_DIR/menu/08_web
web_menu=$submenu_dir
ansible_web_group=/etc/ansible/group_vars/bitrix-web.yml

mysql_menu_dir=$BIN_DIR/menu/03_mysql
mysql_menu_fnc=$mysql_menu_dir/functions.sh
. $mysql_menu_fnc || exit 1

# get_text variables
[[ -f $web_menu/functions.txt    ]] && \
    . $web_menu/functions.txt


# get status for web servers
# return
# WEB_SERVERS -list of web servers
get_web_servers_status(){
    WEB_SERVERS=
    WEB_SERVERS_CNT=0

    # get info from ansible configuration
    local info=$($bx_host_script)
    local erro=$(echo "$info" | grep '^error:' | sed -e "s/^error://")
    local mesg=$(echo "$info" | grep '^message:' | sed -e "s/^message://")
    if [[ -n $erro ]]; then
        print_message \
            "$WEB0001 $WEB0200" \
            "$mesg" "" any_key
        exit
    fi

    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $info; do
        web_server_info=
        hostname=$(echo "$line" | awk -F':' '{print $2}')
        ipaddr=$(echo "$line" | awk -F':' '{print $3}')
        groups=$(echo "$line" | awk -F':' '{print $4}')

        web_instance=
        
        if [[ $(echo "$groups" | grep -wc "web") -gt 0 ]]; then
            web_instance=spare
            [[ $(echo "$groups" | grep -wc "mgmt") -gt 0 ]] && \
                web_instance=main
        fi
        
        # get additional info
        my_server_rootpw=N
        my_server_rootcfg=N
        my_server_status=unknown
        os_version=unknown
        php_version=unknown
    
        # get info from running host and its service
        local h_info=$($bx_host_script -a bx_info --host $hostname)
        local h_erro=$(echo "$h_info" | grep '^error:' | sed -e "s/^error://")
        if [[ -z $h_erro ]]; then
            php_version=$(echo "$h_info" | awk -F':' '{print $8}')
            my_server_rootpw_f=$(echo "$h_info" | awk -F':' '{print $10}')
            my_server_rootcfg_f=$(echo "$h_info" | awk -F':' '{print $11}')
            [[ $my_server_rootcfg_f == "/root/.my.cnf" ]] && \
                my_server_rootcfg=Y
            [[ $my_server_rootpw_f == "set" ]] && \
                my_server_rootpw=Y
            my_server_status=$(echo "$h_info" | awk -F':' '{print $12}')
            os_version=$(echo "$h_info" | awk -F':' '{print $13}')
        fi
        web_server_info="$hostname:$ipaddr:$web_instance"
        web_server_info="$web_server_info:$os_version:$php_version"
        web_server_info="$web_server_info:$my_server_rootcfg:$my_server_rootpw:$my_server_status"

        WEB_SERVERS="${WEB_SERVERS}${web_server_info}
" 

        [[ -n $web_instance ]] && WEB_SERVERS_CNT=$(($WEB_SERVERS_CNT+1))

    done
    IFS=$IFS_BAK
    IFS_BAK=
}

cache_web_servers_status(){
    WEB_SERVERS=
    WEB_SERVERS_CACHE=$CACHE_DIR/web_servers_status.cache             # cache file
    WEB_SERVERS_CACHE_LT=3600                                         # live time for cache file in seconds

    test_cache_file $WEB_SERVERS_CACHE $WEB_SERVERS_CACHE_LT
    if [[ $? -gt 0 ]]; then
        get_web_servers_status
        echo "$WEB_SERVERS" > $WEB_SERVERS_CACHE
    else
        WEB_SERVERS=$(cat $WEB_SERVERS_CACHE)
        WEB_SERVERS_CNT=$(echo "$WEB_SERVERS" | grep -c ":\(spare\|main\):")
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "WEB_SERVERS=$WEB_SERVERS"
        echo "WEB_SERVERS_CNT=$WEB_SERVERS_CNT"
    fi
}


print_web_servers_status(){
    local exclude=$1            # exclude servers by this type of service: spare or main
    local web_only=${2:-1}      # show only web servers

    cache_web_servers_status
    [[ $web_only -gt 0 ]] && \
        WEB_SERVERS=$(echo "$WEB_SERVERS" | grep ":\(spare\|main\):")

    if [[ -n $exclude ]]; then
        WEB_FILTERED_SERVERS_CNT=$(echo "$WEB_SERVERS" | grep -v "^$" | egrep -cv ":$exclude:")
    else
        WEB_FILTERED_SERVERS_CNT=$(echo "$WEB_SERVERS" | grep -vc "^$")
    fi

   
    if [[ $WEB_FILTERED_SERVERS_CNT -eq 0 ]]; then
        echo "$WEB0002"
        [[ -n $exclude ]] &&  echo "$WEB0003 $exclude"   
        echo
        return 1
    fi

    echo "$(get_text "$WEB0004" "$WEB_FILTERED_SERVERS_CNT")"
    [[ -n $exclude  ]] && echo "$WEB0003 $exclude"

    echo $MENU_SPACER
    printf "%-17s | %20s| %6s | %4s | %8s | %2s | %2s | %s\n" \
        "Hostname" "IP" "Type" "OS" "PHP" "P" "C" "MySQL"
    echo $MENU_SPACER

    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $WEB_SERVERS; do
        if [[ -n $exclude  ]]; then
            [[ $(echo "$line" | egrep -c ":$exclude:") -gt 0  ]] && continue
        fi
        echo "$line" | \
            awk -F':' '{printf "%-17s | %20s| %6s | %4s | %8s | %2s | %2s | %s\n", \
            $1, $2, $3, $4, $5, $6, $7, $8}'
    done
    IFS=$IFS_BAK
    IFS_BAK=
        
    echo $MENU_SPACER
    echo
    echo "$WEB0005"
    echo "$WEB0006"
    echo
}

# test web cluster options
# 1. site modules (include test_site_options STOP_ALL_CONDITIONS)
# 2. not found bitrix-env updates for master server (include test last update on master server)
# 3. found root password on master mysql server
# set global variable:
# WEB_CLUSTER_TYPE to 
# csync  - if the pool contains csync2 configuration
# lsync  - in all other cases 
check_web_options(){
    # test site options
    test_sites_config
    if [[ $STOP_ALL_CONDITIONS -gt 0 ]]; then
        print_color_text \
            "$WEB0007" red
        return 1
    fi

    # test bitrix-env last update
    test_bitrix_update
    if [[ $? -gt 0 ]]; then
        print_color_text "$WEB0008" red
        print_color_text "$WEB0009" blue
        return 2
    fi

    # test mysql servers
    cache_mysql_servers_status
    [[ $DEBUG -gt 0 ]] && echo "MYSQL=$MYSQL_SERVERS"
    MASTER_NAME=$(echo "$MYSQL_SERVERS" | grep ":master:" | \
        awk -F':' '{print $1}')
    MASTER_ROOT_PASSWD=$(echo "$MYSQL_SERVERS" | grep ":master:" | \
        awk -F':' '{print $8}')
    MASTER_CLIENT_CNF=$(echo "$MYSQL_SERVERS" | grep ":master:" | \
        awk -F':' '{print $9}')
    if [[ $MASTER_ROOT_PASSWD != "Y" ]]; then
        print_color_text "$WEB0010 $MASTER_NAME"
        print_color_text "$WEB0011" blue
        return 10
    fi
    
    if [[ $MASTER_CLIENT_CNF != "Y" ]]; then
        print_color_text "$WEB0012 $MASTER_NAME"
        print_color_text "$WEB0011" blue
        return 11
    fi

    # test csync or lsyncd
    WEB_CLUSTER_TYPE=$(cat $ansible_web_group | grep -v "^$\|^#" | \
        egrep '^fstype: ' | awk -F':' '{print $2}' | sed -e "s/\s\+//g")
    if [[ -z $WEB_CLUSTER_TYPE ]]; then
        WEB_CLUSTER_STATUS=$(cat $ansible_web_group | grep -v "^$\|^#" | \
            egrep '^cluster_web_configure: ' | \
            awk -F':' '{print $2}' | sed -e "s/\s\+//g")
        if [[ $WEB_CLUSTER_STATUS == "enable" ]]; then
            WEB_CLUSTER_TYPE=csync
        else
            WEB_CLUSTER_TYPE=lsync
        fi
    fi

    WEB_CLUSTER_WEB_SERVER=$(cat $ansible_web_group | grep -v "^$\|^#" | \
        egrep '^new_web_server: ' | awk -F':' '{print $2}' | sed -e "s/\s\+//g")

    # LAST syncronyzation for sites
    WEB_SYNC_TM=$(cat $ansible_web_group | grep -v '^$\|^#' | \
        egrep '^web_sync_tm: ' | awk -F':' '{print $2}' | sed -e "s/\s\+//g")

}
