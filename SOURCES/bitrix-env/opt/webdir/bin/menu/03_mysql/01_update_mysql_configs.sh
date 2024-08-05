#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

update_mysql_setttings() {
    local task_cmd="$bx_mysql_script -a update"
    [[ $DEBUG -gt 0 ]] && echo "task_cmd=$task_cmd"
    exec_pool_task "$task_cmd" "$MY0016"
}

sub_menu() {
    menu_00="$MY0201"
    menu_01="1. $MY0016"

    menu_logo="$MY0016"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $menu_logo
        echo

        # mysql servers list
        print_mysql_servers_status
        # task info
        get_task_by_type '(mysql|monitor)' POOL_MYSQL_TASK_LOCK POOL_MYSQL_TASK_INFO
        print_task_by_type '(mysql|monitor)' "$POOL_MYSQL_TASK_LOCK" "$POOL_MYSQL_TASK_INFO"

        if [[ $POOL_MYSQL_TASK_LOCK -eq 1 ]]; then
            menu_list="$menu_00"
        else
            menu_list="$menu_01\n\t\t $menu_00"
        fi

        print_menu

        if [[ $POOL_MYSQL_TASK_LOCK -gt 0 ]]; then
            print_message "$MY0202" '' '' MENU_SELECT 0
        else
            print_message "$MY0203" "$MY0017" '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            1) update_mysql_setttings ;;
            *) exit ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
