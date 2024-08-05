#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

#web_instance() {
#    local web_server="${1}"
#
#    [[ $DEBUG -gt 0 ]] && echo " web_server=$web_server"
#
#    cache_web_servers_status
#    local web_data=$(echo "$WEB_SERVERS" | egrep -v ":(main):" | grep "^$web_server:")
#    if [[ -z $web_data ]]; then
#        print_message "$WEB0200" \
#            "$(get_text "$WEB0207" "$web_server")" "" any_key
#        exit
#    fi
#
#    # WEB_CLUSTER_TYPE =< fstype
#    local task_exec="$bx_web_script -a delete_web -H $web_server"
#    [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
#
#    exec_pool_task "$task_exec" "$(get_text "$WEB0032" "$srv")"
#
#}

sub_menu() {
    menu_00="$WEB0201"
    menu_01="   $WEB0033"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$WEB0033"
        print_menu_header

        # print all
        print_web_servers_status "(main)" "1"
        print_web_servers_status_rtn=$?

        # task info
        get_task_by_type '(web_cluster|mysql|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(web_cluster|mysql|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ ( $POOL_SUBMENU_TASK_LOCK -eq 1 ) || ( $print_web_servers_status_rtn -gt 0 ) ]]; then
            menu_list="\n$menu_00"
        else
            menu_list="\n$menu_01\n$menu_00"
        fi

        print_menu

        if [[ $POOL_SUBMENU_TASK_LOCK -gt 0 ]]; then
            print_message "$WEB0202" '' '' MENU_SELECT 0
        else
            print_message "$WEB0204" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            #*) web_instance "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
