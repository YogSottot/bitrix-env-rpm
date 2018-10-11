#!/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

delete_host() {
    local deleted_host="$1"
    if [[ -z "$deleted_host" ]]; then
        print_message "$HM0200" "$HM0044" "" any_key
        return 1
    fi

    # test if defined host exist in server list (small check without name resolution)
    [[ -z "$POOL_SERVER_LIST" ]] && cache_pool_info
    local host_iden=$(echo "$POOL_SERVER_LIST" | \
        grep "\(^$deleted_host:\|:$deleted_host:\|=$deleted_host\)" | \
        awk -F':' '{print $1}')
    if [[ $DEBUG -gt 0 ]]; then
        echo "deleted_host=\`$deleted_host\`"
        echo "host_iden=\`$host_iden\`"
    fi



    if [[ -z "$host_iden" ]]; then
        # connection not found => purge (only ansible configuration cleanup)
        local disconn_host_iden=$(echo "$POOL_UNU_SERVER_LIST" | \
            grep "\(^$deleted_host:\|:$deleted_host\)" | \
            awk -F':' '{print $1}')
        if [[ -z "$disconn_host_iden" ]]; then
            print_message "$(get_text "$HM0012" "$deleted_host")$HM0203" \
                "" "" answer 'n'
            [[ $(echo "$answer" | grep -iwc "n") -gt 0 ]] && exit 1
            return 1
        fi
        local disconn_host_addr=$(echo "$POOL_UNU_SERVER_LIST" | \
            grep "^$disconn_host_iden" | \
            awk -F':' '{print $2}')
        print_color_text "$(get_text "$HM0045" "$deleted_host")" red

        print_message "$HM0046 (N|y): " \
            "$HM0047" "" answer 'n'
        [[ $(echo "$answer" | grep -iwc "n") -gt 0 ]] && return 1
        forget_server "$disconn_host_iden" "$disconn_host_addr"
        forget_server_rtn=$?
        if [[ $forget_server_rtn -gt 0 ]]; then
            print_message "$HM0200" \
                "$HM0048 $FORGET_MSG" \
                "" any_key
            return 1
        fi
        print_message "$HM0201" \
            "$(get_text "$HM0049" "$deleted_host")" \
            "" any_key
        return 0
    fi

    local host_addr=$(echo "$POOL_SERVER_LIST" | grep "^$host_iden" | \
        awk -F':' '{print $2}')
    local host_roles=$(echo "$POOL_SERVER_LIST" | grep "^$host_iden" | \
        awk -F':' '{print $3}')
    if [[ $DEBUG -gt 0 ]]; then
        echo "host_addr=$host_addr"
        echo "host_roles=$host_roles"
    fi

   # connection existen => can delete settings on removed host
    if [[ -n "$host_roles" ]]; then
        print_message "$HM0200" \
            "$(get_text "$HM0050" "$deleted_host" "$host_roles")" "" any_key
        return 1
    fi

    print_message "$HM0046 (N|y): " "$HM0051" \
        "" answer 'n'
    [[ $(echo "$answer" | grep -iwc "n") -gt 0 ]] && return 1
    purge_server "$host_iden" "$host_addr"
    purge_server_rtn=$?
    if [[ $purge_server_rtn -gt 0 ]]; then
        print_message "$HM0200" \
            "$HM0048 $DELETE_MSG" \
            "" any_key
        return 1
    fi
    print_message "$HM0201" \
        "$(get_text "$HM0049" "$deleted_host")" \
        "" any_key
    return 0
}

# create host in the ansible config and copy ssh key on it
sub_menu() {
    host_logo="$HM0052"
    menu_00="$HM0042"
    menu_01="   $HM0052"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_pool_info
        
        # is there some task which can interrupted by adding new host (iptables and so on)
        get_task_by_type '(common|monitor|mysql)' POOL_HOST_TASK_LOCK POOL_HOST_TASK_LIST
        print_task_by_type '(common|monitor|mysql)' "$POOL_HOST_TASK_LOCK" "$POOL_HOST_TASK_LIST"

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_00"
        else
            menu_list="\n\t$menu_00\n\t$menu_01"
        fi
        print_menu

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            print_message "$HM0202" '' '' HOST_MENU_SELECT 0
        else
            print_message "$HM0043" \
                '' '' HOST_MENU_SELECT
        fi
        # process selection
        case "$HOST_MENU_SELECT" in
            "0") exit ;;
            *) delete_host "$HOST_MENU_SELECT" ;;
        esac
        [[ $? -eq 0 ]] && POOL_SERVER_LIST=
        HOST_MENU_SELECT=
    done
}
sub_menu

