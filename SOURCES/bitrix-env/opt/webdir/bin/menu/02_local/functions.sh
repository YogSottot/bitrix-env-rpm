#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_process_script=$BIN_DIR/bx-process
bx_host_script=$BIN_DIR/wrapper_ansible_conf
bx_web_script=$BIN_DIR/bx-sites

submenu_dir=$BIN_DIR/menu/02_local

SYSCONFIG_DIR=/etc/sysconfig/network-scripts

# get_text variables
[[ -f $submenu_dir/functions.txt ]] && \
    . $submenu_dir/functions.txt

export CURRENT_HOSTNAME=$(hostname)

configure_hostname_local() {
    new_h="${1}"

    if [[ -z $new_h ]]; then
        return 1
    fi

    test_hostname $new_h || return $?

    get_os_type
    # CentOS Stream 9
    if [[ $OS_VERSION -eq 9 ]]; then
        hostnamectl set-hostname $new_h
    # CentOS 7
    elif [[ $OS_VERSION -eq 7 ]]; then
        hostnamectl set-hostname $new_h
    else
        sysconfig_network=/etc/sysconfig/network
        etc_hostname=/etc/hostname
        sed -i".bak" '/HOSTNAME=/d' $sysconfig_network
        echo "HOSTNAME=$new_h" >> $sysconfig_network

        print_color_text "$(get_text "$CH003" "$sysconfig_network")"

        echo $new_h > $etc_hostname
        print_color_text "$(get_text "$CH003" "$etc_hostname")"

        hostname $new_h
    fi
    print_color_text "$(get_text "$CH004" "$CURRENT_HOSTNAME" "$new_h")"
    return 0
}

configure_hostname_pool() {
    new_h="$1"
    cur_h="$2"

    # get ansible id for the server
    cur_id=$(get_server_id "$cur_h")
    cur_id_rtn=$?
    if [[ $cur_id_rtn -eq 1 ]]; then
        print_message "$CH100" "$(get_text "$CH005" "$cur_h")" "" any_key
        return 1
    elif [[ $cur_id_rtn -eq 2 ]]; then
        print_message "$CH100" "$(get_text "$CH006" "$cur_h")" "" any_key
        return 1
    fi

    # test new hostname, should not exist in the server pool.
    if_hostname_exists_in_the_pool "$new_h"
    if [[ $? -gt 0 ]]; then
        print_message "$CH100" "$(get_text "$CH007" "$new_h")" "" any_key
        return 1
    fi

    # bx_host_script
    cmd="$bx_host_script -a change_hostname --host $cur_id --hostname $new_h"
    if [[ $DEBUG -gt 0 ]]; then
        echo "cmd=$cmd"
    fi
    exec_pool_task "$cmd" "change hostname"
}

check_default_route() {
    HOST_ROUTE_EXIST=0
    HOST_ROUTE_INTERFACE=
    route_info=$(ip route list | grep default -w | grep -w $INT)

    if [[ -n "$route_info" ]]; then
        HOST_ROUTE_EXIST=1
        HOST_ROUTE_INTERFACE=$(echo "$route_info" | egrep -o 'dev\s+\S+' | awk '{print $2}')
    fi
}

get_network_info() {
    export HWADDR=$(ip addr show $INT | \
        egrep -o "link/ether\s+\S+" | awk '{print $2}')
    export IP=$(ip addr show $INT | \
        egrep -o "inet\s+\S+" | \
        awk '{print $2}' | awk -F'/' '{print $1}')

    if [[ $DEBUG -gt 0 ]]; then
        echo "HWADDR: $HWADDR"
        echo "    IP: $IP"
    fi
}

restart_network_daemon() {
    [[ -z $OS_VERSION ]] && get_os_type
    # CentOS Stream 9
    if [[ $OS_VERSION -eq 9 ]]; then
        NETD=NetworkManager
        systemctl restart ${NETD} >/dev/null 2>&1
        rtn=$?
    fi
    # CentOS 7
    if [[ $OS_VERSION -eq 7 ]]; then
        NETD=network
        NM_CONFIG=/etc/NetworkManager/conf.d/01-bitrix.conf
        NETWORK_CONFIG=$SYSCONFIG_DIR/ifcfg-$INT
        if [[ $(systemctl is-enabled NetworkManager.service | \
            grep -wc enabled) -gt 0 ]]; then
            echo "[main]"                   >  $NM_CONFIG
            echo "plugins=keyfile,ifcfg-rh" >> $NM_CONFIG
            echo "dns=none"                 >> $NM_CONFIG
            echo "NM_CONTROLLED=yes"        >> $NETWORK_CONFIG
            NETD=NetworkManager
        fi
        /etc/init.d/network restart >/dev/null 2>&1

        systemctl restart ${NETD} >/dev/null 2>&1
        rtn=$?
    fi
    print_color_text "$(get_text "$CH012" "$NETD" "$rtn")"
    return $rtn
}

configure_network_in_pool() {
    # run ansible task
    get_client_settings
    get_network_info
    if [[ $DEBUG -gt 0 ]]; then
        echo "INPOOL: $IN_POOL"
        echo "IP:     $IP"
        echo "CIP:    $CURRENT_IP"
    fi

    if [[ ( $IN_POOL -gt 0 ) && ( -n $IP ) && ( $CURRENT_IP != "$IP" ) ]]; then
        # get ansible id for the server
        cur_id=$(get_server_id "$CURRENT_HOSTNAME")
        cur_id_rtn=$?
        if [[ $cur_id_rtn -eq 1 ]]; then
            print_message "$CH100" "$(get_text "$CH005" "$CURRENT_HOSTNAME")" "" any_key
            return 1
        elif [[ $cur_id_rtn -eq 2 ]]; then
            print_message "$CH100" "$(get_text "$CH006" "$cur_h")" "" any_key
            return 1
        fi

        # bx_host_script
        cmd="$bx_host_script -a change_ip --hostname $cur_id --ip $IP"
        if [[ $DEBUG -gt 0 ]]; then
            echo "cmd=$cmd"
        fi
        exec_pool_task "$cmd" "change ip"
    fi
}

configure_network_by_dhcp() {
    [[ -z $OS_VERSION ]] && get_os_type
    # CentOS Stream 9
    if [[ $OS_VERSION -eq 9 ]]; then
        INT="${1}"

        get_network_info
        export CURRENT_IP=$IP
        DEFAULT_NOTICE='(y|N)'
        DEFAULT_ANSWER='n'
        if [[ -z $CURRENT_IP ]]; then
            DEFAULT_NOTICE='(Y|n)'
            DEFAULT_ANSWER='y'
        fi

        print_message "$CH101 $DEFAULT_NOTICE: " "" "" ans_saved "$DEFAULT_ANSWER"
        if [[ $(echo "$ans_saved" | grep -iwc "n" ) -gt 0 ]]; then
            return 1
        fi

        nmcli connection modify $INT ipv4.method auto >/dev/null 2>&1
        nmcli connection reload >/dev/null 2>&1
        nmcli connection down $INT >/dev/null 2>&1
        nmcli connection up $INT >/dev/null 2>&1

        nohup $PROGPATH/restart_network_daemon.sh $IP $INT &>/dev/null &

        get_network_info
        if [[ ( -n $IP ) ]]; then
            print_message "$CH100" "$(get_text "$CH014" "$INT")" "" any_key
        else
            print_message "$CH100" "$CH015" "" any_key
        fi
    fi
    # CentOS 7
    if [[ $OS_VERSION -eq 7 ]]; then
        INT="${1}"
        NETWORK_CONFIG=$SYSCONFIG_DIR/ifcfg-$INT
        RESOLVE_CONFIG=/etc/resolv.conf

        get_network_info
        export CURRENT_IP=$IP
        DEFAULT_NOTICE='(y|N)'
        DEFAULT_ANSWER='n'
        if [[ -z $CURRENT_IP ]]; then
            DEFAULT_NOTICE='(Y|n)'
            DEFAULT_ANSWER='y'
        fi

        print_message "$CH101 $DEFAULT_NOTICE: " "" "" ans_saved "$DEFAULT_ANSWER"
        if [[ $(echo "$ans_saved" | grep -iwc "n" ) -gt 0 ]]; then
            return 1
        fi
        echo "# $INT"           >  $NETWORK_CONFIG
        echo "HWADDR=$HWADDR"   >> $NETWORK_CONFIG
        echo "DEVICE=$INT"      >> $NETWORK_CONFIG
        echo "BOOTPROTO=dhcp"   >> $NETWORK_CONFIG
        echo "ONBOOT=yes"       >> $NETWORK_CONFIG
        echo "TYPE=Ethernet"    >> $NETWORK_CONFIG

        print_color_text "$(get_text "$CH013" "$NETWORK_CONFIG")"

        nohup $PROGPATH/restart_network_daemon.sh $IP $INT &>/dev/null &

        get_network_info
        if [[ ( -n $IP ) ]]; then
            print_message "$CH100" "$(get_text "$CH014" "$INT")" "" any_key
        else
            print_message "$CH100" "$CH015" "" any_key
        fi
    fi
}

configure_network_by_hand() {
    [[ -z $OS_VERSION ]] && get_os_type
    # CentOS Stream 9
    if [[ $OS_VERSION -eq 9 ]]; then
        INT="${1}"

        get_network_info
        export CURRENT_IP=$IP
        DEFAULT_NOTICE='(y|N)'
        DEFAULT_ANSWER='n'
        if [[ -z $CURRENT_IP ]]; then
            DEFAULT_NOTICE='(Y|n)'
            DEFAULT_ANSWER='y'
        fi

        print_message "$CH016" "" "" address
        #print_message "$CH017" "" "" broadcast
        #print_message "$CH018" "" "" netmask

        # nmcli has no params like broadcast, netmask always 24
        netmask="24"

        IF_ROUTE_CONFIGURE=1
        [[ ( $HOST_ROUTE_EXIST -gt 0 ) && ( "$HOST_ROUTE_INTERFACE" != "$INT" ) ]] && IF_ROUTE_CONFIGURE=0
        if [[ $IF_ROUTE_CONFIGURE -eq 1 ]]; then
            print_message "$CH019" "" "" gateway
        fi
        print_message "$CH020" "" "" ans_dns "y"
        if [[ $(echo "$ans_dns" | grep -wci "y") -gt 0 ]]; then
            print_message "$CH021" "" "" dns
        fi

        echo "$MENU_SPACER"
        print_color_text "$(get_text "$CH022" $INT)"
        echo "$MENU_SPACER"

        printf "%-20s: %s\n" "IP Address"       "$address"
        #printf "%-20s: %s\n" "Broadcast"        "$broadcast"
        printf "%-20s: %s\n" "Network Mask"     "$netmask"
        printf "%-20s: %s\n" "Default Gateway"  "$gateway"
        printf "%-20s: %s\n" "DNS Server"       "$dns"

        print_color_text "$CH0092" red

        print_message "$CH101 $DEFAULT_NOTICE: " "" "" ans_saved "$DEFAULT_ANSWER"
        if [[ $(echo "$ans_saved" | grep -iwc "n" ) -gt 0 ]]; then
            return 1
        fi

        if [[ $DEBUG -gt 0 ]]; then
            echo "nmcli: display devices"
            nmcli device
            echo ""
        fi
        # set ipv4 address
        nmcli connection modify $INT ipv4.addresses $address/$netmask >/dev/null 2>&1
        # set gateway
        nmcli connection modify $INT ipv4.gateway $gateway >/dev/null 2>&1
        # set dns - for multiple dns, specify with space separated "10.0.0.10 10.0.0.11 10.0.0.12"
        nmcli connection modify $INT ipv4.dns $dns >/dev/null 2>&1
        # set dns search base (your domain name - for multiple one, specify with space separated "rr.bx zz.bb")
        # nmcli connection modify $INT ipv4.dns-search example.com
        # set manual for static setting
        nmcli connection modify $INT ipv4.method manual >/dev/null 2>&1
        # restart the interface to reload settings
        nmcli connection reload >/dev/null 2>&1
        nmcli connection down $INT >/dev/null 2>&1
        nmcli connection up $INT >/dev/null 2>&1
        if [[ $DEBUG -gt 0 ]]; then
            echo "nmcli: show dev status"
            nmcli dev status
            echo ""
            echo "nmcli: show $INT settings"
            nmcli device show $INT
            echo ""
            echo "ip: show settings"
            ip a
            echo ""
        fi

        nohup $PROGPATH/restart_network_daemon.sh $IP $INT &>/dev/null &

        if [[ ( -n $IP ) ]]; then
            print_message "$CH100" "$(get_text "$CH014" "$INT")" "" any_key
        else
            print_message "$CH100" "$CH015" "" any_key
        fi
    fi
    # CentOS 7
    if [[ $OS_VERSION -eq 7 ]]; then
        INT="${1}"
        NETWORK_CONFIG=$SYSCONFIG_DIR/ifcfg-$INT
        RESOLVE_CONFIG=/etc/resolv.conf

        get_network_info
        export CURRENT_IP=$IP

        DEFAULT_NOTICE='(y|N)'
        DEFAULT_ANSWER='n'
        if [[ -z $CURRENT_IP ]]; then
            DEFAULT_NOTICE='(Y|n)'
            DEFAULT_ANSWER='y'
        fi

        print_message "$CH016" "" "" address
        print_message "$CH017" "" "" broadcast
        print_message "$CH018" "" "" netmask

        IF_ROUTE_CONFIGURE=1
        [[ ( $HOST_ROUTE_EXIST -gt 0 ) && ( "$HOST_ROUTE_INTERFACE" != "$INT" ) ]] && IF_ROUTE_CONFIGURE=0
        if [[ $IF_ROUTE_CONFIGURE -eq 1 ]]; then
            print_message "$CH019" "" "" gateway
        fi
        print_message "$CH020" "" "" ans_dns "y"
        if [[ $(echo "$ans_dns" | grep -wci "y") -gt 0 ]]; then
            print_message "$CH021" "" "" dns
        fi

        echo "$MENU_SPACER"
        print_color_text "$(get_text "$CH022" $INT)"
        echo "$MENU_SPACER"

        printf "%-20s: %s\n" "IP Address"       "$address"
        printf "%-20s: %s\n" "Broadcast"        "$broadcast"
        printf "%-20s: %s\n" "Default Gateway"  "$gateway"
        printf "%-20s: %s\n" "Network Mask"     "$netmask"
        printf "%-20s: %s\n" "DNS Server"       "$dns"

        print_color_text "$CH0092" red

        print_message "$CH101 $DEFAULT_NOTICE: " "" "" ans_saved "$DEFAULT_ANSWER"
        if [[ $(echo "$ans_saved" | grep -iwc "n" ) -gt 0 ]]; then
            return 1
        fi

        echo "# $INT"               > $NETWORK_CONFIG
        echo "HWADDR=$HWADDR"       >> $NETWORK_CONFIG
        echo "DEVICE=$INT"          >> $NETWORK_CONFIG
        echo "BOOTPROTO=static"     >> $NETWORK_CONFIG
        echo "ONBOOT=yes"           >> $NETWORK_CONFIG
        echo "TYPE=Ethernet"        >> $NETWORK_CONFIG
        echo "IPADDR=$address"      >> $NETWORK_CONFIG
        echo "NETMASK=$netmask"     >> $NETWORK_CONFIG
        echo "BROADCAST=$broadcast" >> $NETWORK_CONFIG
        if [[ -n $gateway ]]; then
            echo "GATEWAY=$gateway" >> $NETWORK_CONFIG
        fi
        print_color_text "$(get_text "$CH013" "$NETWORK_CONFIG")"

        if [[ -n $dns ]]; then
            sed -i".bak" '/nameserver/d' $RESOLVE_CONFIG
            id=1
            for name in $dns; do
                echo "nameserver $name" >> $RESOLVE_CONFIG
                echo "DNS$id=$name" >> $NETWORK_CONFIG
                id=$(($id + 1))
            done
            print_color_text "$(get_text "$CH013" "$RESOLVE_CONFIG")"
        fi

        nohup $PROGPATH/restart_network_daemon.sh $IP $INT &>/dev/null &

        if [[ ( -n $IP ) ]]; then
            print_message "$CH100" "$(get_text "$CH014" "$INT")" "" any_key
        else
            print_message "$CH100" "$CH015" "" any_key
        fi
    fi
}

configure_network() {
    local conf_type="${1:-manual}"
    local conf_int="$2"

    if [[ ( $conf_type != "manual" ) && ( $conf_type != "dhcp" ) ]]; then
        print_message "$CH100" "$(get_text "$CH023" "$conf_type")" "" any_key
        return 1
    fi

    if [[ -z "$conf_int" ]]; then
        print_message "$CH100" "$CH011" "" any_key
        return 1
    fi

    [[ -z $HOST_NETWORK_INFO ]] && get_local_network
    if [[ $(echo "$HOST_NETWORK_INFO" | grep -c "#$conf_int#") -eq 0 ]]; then
        print_message "$CH100" "$(get_text "$CH024" "$conf_int")" "" any_key
        return 1
    fi

    [[ $conf_type == "manual" ]] && configure_network_by_hand $conf_int
    [[ $conf_type == "dhcp" ]] && configure_network_by_dhcp $conf_int
}
