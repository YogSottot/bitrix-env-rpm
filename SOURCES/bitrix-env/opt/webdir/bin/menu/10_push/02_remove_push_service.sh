#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

configure_nodejs() {
    local hostname="$1"
    local task_exec="$bx_web_script -a push_remove_nodjs -H $hostname"
    [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
    exec_pool_task "$task_exec" "$(get_text "$PUSH007" "$hostname")"
}

push_instance() {
    local hostname="$1"

    [[ $DEBUG -gt 0 ]] && echo "hostname=$hostname"

    #is_current_ngx_push=$(echo "$PUSH_SERVERS" | grep "Nginx-PushStreamModule:$hostname:" -c)
    is_currnet_nodejs_push=$(echo "$PUSH_SERVERS" | grep "NodeJS-PushServer:$hostname:" -c)
    is_exist_host=$(echo "$PUSH_SERVERS" | grep -c ":$hostname:")
    if [[ $is_exist_host -eq 0 ]]; then
        print_message "$PUSH200" "$(get_text "$PUSH206" "$hostname")" "" any_key
        return 1
    fi

    if [[ $hostname != "$NODE_PUSH_SERVER" ]]; then
        print_message "$PUSH200" "$(get_text "$PUSH008" "$hostname")" "" any_key
        return 1
    fi

    print_message "$(get_text "$PUSH009" "$hostname")" "" "" any_key "n"

    if [[ $(echo "$any_key" | grep -wci "y") -gt 0  ]]; then
        configure_nodejs $hostname
    fi
}

sub_menu() {
    menu_00="$PUSH201"
    menu_01="$PUSH010"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$PUSH010"
        print_menu_header

        print_push_servers_status "" 1
        print_push_servers_status_rtn=$?

        # task info
        get_task_by_type '(web_cluster|mysql|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(web_cluster|mysql|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ ( $POOL_SUBMENU_TASK_LOCK -eq 1 ) || ( $print_push_servers_status_rtn -gt 0 ) ]]; then
            menu_list="$menu_00"
        else
            menu_list="$menu_01\n\t\t $menu_00"
        fi

        print_menu

        if [[ ( $POOL_SUBMENU_TASK_LOCK -gt 0 ) || ( $print_push_servers_status_rtn -gt 0 ) || ( -z $NODE_PUSH_SERVER ) ]]; then
            print_message "$PUSH202" '' '' MENU_SELECT 0
            MENU_SELECT=0
        else
            print_message "$PUSH204" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            *) push_instance "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
