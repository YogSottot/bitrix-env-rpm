#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_mysql_script=$BIN_DIR/bx-mysql
bx_process_script=$BIN_DIR/bx-process
bx_host_script=$BIN_DIR/wrapper_ansible_conf
mysql_menu=$BIN_DIR/menu/03_mysql
ansible_mysql_group=/etc/ansible/group_vars/bitrix-mysql.yml

# get_text variables
[[ -f $mysql_menu/functions.txt  ]] && \
        . $mysql_menu/functions.txt

# get status for mysql servers
# return:
# MYSQL_SERVERS
# MYSQL_SLAVES_CNT - number of mysql slave servers
get_mysql_servers_status() {
    MYSQL_SERVERS=
    MYSQL_SLAVES_CNT=0
    # get info from ansible configuration
    local info=$($bx_host_script)
    local erro=$(echo "$info" | grep '^error:' | sed -e "s/^error://")
    local mesg=$(echo "$info" | grep '^message:' | sed -e "s/^message://")
    if [[ -n $erro ]]; then
        print_message "$MY0001 $MY0200" "$mesg" "" any_key
        exit
    fi

    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $info;do
        my_server_info=
        #host:vm03.ksh.bx:172.17.10.103::1506683890_lWjWsPfqFA:vm03
        #host:vm04.ksh.bx:172.17.10.104:mysql_master_1,web:1506682197_xPU3HyAUIu:vm04.ksh.bx
        host_ident=$(echo "$line" | awk -F':' '{print $2}')
        ipaddr=$(echo "$line" | awk -F':' '{print $3}')
        groups=$(echo "$line" | awk -F':' '{print $4}')
        hostname=$(echo "$line" | awk -F':' '{print $6}')

        my_group=$(echo "$groups" | egrep -o "mysql_(master|slave)_[0-9]+")
        if [[ -n $my_group ]]; then
            my_server_id=$(echo "$my_group" | awk -F'_' '{print $3}')
            my_server_type=$(echo "$my_group" | awk -F'_' '{print $2}')
        else
            my_server_id=
            my_server_type=
        fi

        # get additional mysql info
        my_server_version=unknown
        my_server_rootpw=N
        my_server_rootcfg=N
        my_server_package=unknown
        my_server_status=unknown

        # get info from running host and its service
        local h_info=$($bx_host_script -a bx_info --host $host_ident)
        local h_erro=$(echo "$h_info" | grep '^error:' | sed -e "s/^error://")
        if [[ -z $h_erro ]]; then
            my_server_version=$(echo "$h_info" | awk -F':' '{print $7}')
            my_server_package=$(echo "$h_info" | awk -F':' '{print $9}')
            my_server_rootpw_f=$(echo "$h_info" | awk -F':' '{print $10}')
            my_server_rootcfg_f=$(echo "$h_info" | awk -F':' '{print $11}')
            [[ $my_server_rootcfg_f == "/root/.my.cnf" ]] && my_server_rootcfg=Y
            [[ $my_server_rootpw_f == "set" ]] && my_server_rootpw=Y
            my_server_status=$(echo "$h_info" | awk -F':' '{print $12}')
        fi
        my_server_info="$host_ident:$ipaddr:$my_server_id:$my_server_type"
        my_server_info="$my_server_info:$my_server_package:$my_server_version:$my_server_status"
        my_server_info="$my_server_info:$my_server_rootpw:$my_server_rootcfg"
        my_server_info="$my_server_info:$hostname"

        # update variables
        [[ $my_server_type ==  "slave" ]] && MYSQL_SLAVES_CNT=$(( $MYSQL_SLAVES_CNT+1 ))
        MYSQL_SERVERS="${MYSQL_SERVERS}${my_server_info}
"
    done
    IFS=$IFS_BAK
    IFS_BAK=
}

cache_mysql_servers_status() {
    MYSQL_SERVERS=
    MYSQL_SLAVES_CNT=0
    MYSQL_SERVERS_CACHE=$CACHE_DIR/mysql_servers_status.cache             # cache file
    MYSQL_SERVERS_CACHE_LT=3600                                         # live time for cache file in seconds

    test_cache_file $MYSQL_SERVERS_CACHE $MYSQL_SERVERS_CACHE_LT
    if [[ $? -gt 0 ]]; then
        get_mysql_servers_status
        echo "$MYSQL_SERVERS" > $MYSQL_SERVERS_CACHE
    else
        MYSQL_SERVERS=$(cat $MYSQL_SERVERS_CACHE)
        MYSQL_SLAVES_CNT=$(echo "$MYSQL_SERVERS" | grep -c ":slave:")
    fi
}

# print information abount mysql servers for menu
print_mysql_servers_status() {
    local exclude=$1            # exclude servers by this type of service: slave or master
    local mysql_only="${2:-1}"  # show only mysql servers

    cache_mysql_servers_status
    [[ $mysql_only -gt 0 ]] &&
        MYSQL_SERVERS=$(echo "$MYSQL_SERVERS" | grep ":\(slave\|master\):")

    if [[ -n $exclude ]]; then
        MYSQL_SERVERS_CNT=$(echo "$MYSQL_SERVERS" | grep -v "^$" | egrep -cv ":$exclude:")
    else
        MYSQL_SERVERS_CNT=$(echo "$MYSQL_SERVERS" | grep -vc "^$")
    fi

    if [[ $MYSQL_SERVERS_CNT -eq 0 ]]; then
        echo "$MY0002"
        [[ -n $exclude ]] &&  echo "$(get_text "$MY0003" "$exclude")"
        echo
        return 1
    fi

    echo "$(get_text "$MY0004" "$MYSQL_SERVERS_CNT")"
    [[ -n $exclude ]] && echo "$(get_text "$MY0003" "$exclude")"
    echo $MENU_SPACER
    # vm03.ksh.bx:172.17.10.103:::Percona-Server-server:5.7.18:active:Y:Y:vm03
    # vm04.ksh.bx:172.17.10.104:1:master:Percona-Server-server:5.7.18:active:Y:Y:vm04.ksh.bx
    printf "%-3s | %-17s | %20s| %6s | %20s | %6s | %2s | %2s | %s\n" "ID" "Hostname" "IP" "Type" "Package" "Ver." "P" "C" "Status"
    echo $MENU_SPACER

    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $MYSQL_SERVERS; do
        if [[ -n $exclude ]]; then
            [[ $(echo "$line" | egrep -c ":$exclude:") -gt 0 ]] && continue
        fi
        echo "$line" | \
            awk -F':' '{printf "%-3s | %-17s | %20s| %6s | %20s | %6s | %2s | %2s | %s\n", $3, $10, $2, $4, $5, $6, $8, $9, $7}'
    done
    echo $MENU_SPACER
    echo "$MY0005"
    IFS=$IFS_BAK
    IFS_BAK=
}

# test mysql options
# 1. Same major version for MySQL services
# 2. Root password is configured and client mysql config exists
# 3. All MySQL services are running
# include test_site_options STOP_ALL_CONDITIONS 
# include test last update on master server
check_mysql_options() {
    local tested_server="${1}"

    
    # test site options
    test_sites_config
    if [[ $STOP_ALL_CONDITIONS -gt 0 ]]; then
        print_color_text "$MY0006" red
        return 1
    fi

    # test bitrix-env last update
    test_bitrix_update
    if [[ $? -gt 0 ]]; then
        print_color_text "$MY0007" red
        print_color_text "$MY0008" blue
        return 2
    fi

    # get sever list
    cache_mysql_servers_status

    # get master server options
    local master_version=$(echo "$MYSQL_SERVERS" | grep ":master:" | \
        awk -F':' '{print $6}' | awk -F'.' '{printf "%d.%d", $1, $2}')

    # get list servers with problems
    MY_NOT_ACTIVE=
    MY_PASSWORD_EMPTY=
    MY_CONFIG_EMPTY=
    MY_DIFFERENT_VERSION=
 
    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $MYSQL_SERVERS; do
        host_ident=$(echo "$line" | awk -F':' '{print $1}')
        hostname=$(echo "$line" | awk -F':' '{print $10}')
        
        # check only servers which can be used in playbook
        if [[ $(echo "$line" | grep -c ":\(slave\|master\):") -eq 0 ]]; then
            if [[ -n "$tested_server" ]]; then
                isUsed=0
                [[ $hostname == "$tested_server" ]] && isUsed=1
                [[ $host_ident == "$tested_server"  ]] && isUsed=1
                [[ $isUsed -eq 0 ]] && continue
            else
                continue
            fi
            my_type=
        else
            my_type=$(echo "$line" | awk -F':' '{print $4}')
        fi

        my_version=$(echo "$line" |  awk -F':' '{print $6}' | awk -F'.' '{printf "%d.%d", $1, $2}')
        my_password=$(echo "$line" | awk -F':' '{print $8}')
        my_conf=$(echo "$line" | awk -F':' '{print $9}')
        my_status=$(echo "$line" | awk -F':' '{print $7}')

        [[ ( $my_status == "active" ) && ( $my_version != "$master_version" ) ]] && MY_DIFFERENT_VERSION="${MY_DIFFERENT_VERSION}${hostname}\n"
        [[ ( $my_status == "active" ) && ( $my_password == "N" ) ]] && MY_PASSWORD_EMPTY="${MY_PASSWORD_EMPTY}${hostname}\n"
        [[ ( $my_status == "active" ) && ( $my_conf == "N" ) ]] && MY_CONFIG_EMPTY="${MY_CONFIG_EMPTY}${hostname}\n"
        [[ $my_status != "active" ]] && MY_NOT_ACTIVE="${MY_NOT_ACTIVE}${hostname}\n"
    done
    IFS=$IFS_BAK
    IFS_BAK=
    
    # get numbers
    MY_DIFFERENT_VERSION_CNT=$(echo -e "$MY_DIFFERENT_VERSION" | grep -vc '^$')
    MY_PASSWORD_EMPTY_CNT=$(echo -e "$MY_PASSWORD_EMPTY" | grep -vc '^$')
    MY_CONFIG_EMPTY_CNT=$(echo -e "$MY_CONFIG_EMPTY" | grep -vc '^$')
    MY_NOT_ACTIVE_CNT=$(echo -e "$MY_NOT_ACTIVE" | grep -vc '^$')

    if [[ $MY_PASSWORD_EMPTY_CNT -gt 0 ]]; then
        print_color_text "$MY0009" red
        echo -e "$MY_PASSWORD_EMPTY"
        print_color_text "$MY0010" blue
        print_message "$MY0200"  "" "" any_key
        return 10
    fi

    if [[ $MY_CONFIG_EMPTY_CNT -gt 0 ]]; then
        print_color_text "$MY0011" red
        echo -e "$MY_CONFIG_EMPTY"
        print_color_text "$MY0010" blue
        print_message "$MY0200"  "" "" any_key
        return 10
    fi

    if [[ $MY_NOT_ACTIVE_CNT -gt 0 ]]; then
        print_color_text "$MY0012" red
        echo -e "$MY_NOT_ACTIVE"
        print_color_text "$MY0013" blue
        print_message "$MY0200"  "" "" any_key
        return 11
    fi

    if [[ $MY_DIFFERENT_VERSION_CNT -gt 0 ]]; then
        print_color_text "$MY0014" red
        echo -e "$MY_DIFFERENT_VERSION"
        print_color_text "$MY0015" blue
        print_message "$MY0200" "" "" any_key
        return 12
    fi
}
