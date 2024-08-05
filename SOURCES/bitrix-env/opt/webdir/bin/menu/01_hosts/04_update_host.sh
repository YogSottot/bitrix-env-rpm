#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

updated_host() {
    local act_host="$1"

    if [[ -z "$act_host" ]]; then
        print_message "$HM0200" "$HM0044" "" any_key
        return 1
    fi

    # test if defined host exist in server list (small check without name resolution)
    [[ -z "$POOL_SERVER_LIST" ]] && cache_pool_info
    local host_iden=$(echo "$POOL_SERVER_LIST" | \
        grep "\(^$act_host:\|:$act_host:\|=$act_host\)" | \
        awk -F':' '{print $1}')
    [[ $DEBUG -gt 0 ]] && echo "$POOL_SERVER_LIST"
    if [[ -z $host_iden ]]; then
        print_message "$HM0203" "$(get_text "$HM0012" "$act_host")" "" answer 'n'
        [[ $(echo "$answer" | grep -iwc "n") -gt 0 ]] && exit 1
        return 1
    fi
    print_message "$HM0055" "$HM0056" "" bx_type "bitrix"
    bx_type=$(echo "$bx_type" | tr '[:upper:]' '[:lower:]')

    if [[ $bx_type == "bitrix" ]]; then
        cmd_exec="$ansible_wrapper -a bx_update -H $host_iden"
    elif [[ $bx_type == "all" ]]; then
        cmd_exec="$ansible_wrapper -a bx_upgrade -H $host_iden"
    else
        print_message "$HM0200" "$(get_text "$HM0057" "$bx_type")" "" any_key
        return 1
    fi

    [[ $DEBUG -gt 0 ]] && echo "cmd=$cmd_exec"
    exec_pool_task "$cmd_exec" "update packages on host=$host_iden"
    return 0
}

# create host in the ansible config and copy ssh key on it
sub_menu() {
    host_logo="$HM0058"
    menu_00="$HM0042"
    menu_01="$HM0058"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $host_logo
        echo

        print_pool_info

        # is there some task which can interrupted by adding new host (iptables and so on)
        get_task_by_type '(common|monitor|mysql|update)' POOL_HOST_TASK_LOCK POOL_HOST_TASK_LIST
        print_task_by_type '(common|monitor|mysql|update)' "$POOL_HOST_TASK_LOCK" "$POOL_HOST_TASK_LIST"

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            local menu_list="$menu_00"
        else
            local menu_list="$menu_01\n\t\t $menu_00"
        fi
        print_menu

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            print_message "$HM0202" '' '' HOST_MENU_SELECT 0
        else
            print_message "$HM0043" '' '' HOST_MENU_SELECT
        fi
        # process selection
        case "$HOST_MENU_SELECT" in
            "0") exit ;;
            *) updated_host "$HOST_MENU_SELECT" ;;
        esac
        [[ $? -eq 0 ]] && POOL_SERVER_LIST=
        HOST_MENU_SELECT=
    done
}

sub_menu
