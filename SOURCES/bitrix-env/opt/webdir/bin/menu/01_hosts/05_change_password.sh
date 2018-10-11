#!/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

change_bitrix_password() {
    local act_host="${1}"
    local act_user="${2:-bitrix}"

    if [[ -z "$act_host" ]]; then
        print_message "$HM0200" \
            "$HM0044" "" any_key
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
    ask_password_info "$act_user" "new_password"
    ask_password_rtn=$?
    [[ $ask_password_rtn -gt 0 ]] && exit 1

    print_message "$(get_text "$HM0059" "$act_user" "$host_iden") (y|N): " \
        "" "" _confirm 'n'
    if [[ $( echo "$_confirm" | grep -wci 'y' ) -gt 0 ]]; then
        cmd="$ansible_wrapper -a bx_passwd -H $host_iden"
        cmd=$cmd" -u $act_user -P $(printf "%q" "$new_password")"
        [[ $DEBUG -gt 0 ]] && echo "$cmd"
        exec_pool_task "$cmd" \
            "change $act_user password on host=$host_iden"
    fi
    return 0
}

sub_menu() {
    host_logo="$HM0060"
    menu_00="$HM0042"
    menu_01="   $HM0060"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_pool_info

        # is there some task which can interrupted by adding new host (iptables and so on)
        get_task_by_type '(common|monitor|mysql|update)' POOL_HOST_TASK_LOCK POOL_HOST_TASK_LIST
        print_task_by_type '(common|monitor|mysql|update)' "$POOL_HOST_TASK_LOCK" "$POOL_HOST_TASK_LIST"

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            local menu_list="\n\t$menu_00"
        else
            local menu_list="\n\t$menu_00\n\t$menu_01"
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
            *) change_bitrix_password "$HOST_MENU_SELECT" ;;
        esac
        [[ $? -eq 0 ]] && POOL_SERVER_LIST=
        HOST_MENU_SELECT=
    done
}

sub_menu

