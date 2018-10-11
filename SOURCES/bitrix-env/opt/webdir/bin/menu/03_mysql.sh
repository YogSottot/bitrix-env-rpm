#!/bin/bash
# manage sites and site's options 
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/03_mysql/functions.sh || exit 1
logo=$(get_logo)

update_mysql_configs() {
    $mysql_menu/01_update_mysql_configs.sh
}

create_mysql_slave() {
    $mysql_menu/04_create_mysql_slave.sh
}

change_mysql_master() {
    $mysql_menu/05_change_mysql_master.sh
}

remove_mysql_slave() {
    $mysql_menu/06_remove_mysql_slave.sh
}

change_mysql_password() {
    $mysql_menu/02_change_mysql_password.sh
}

manage_mysql_service() {
    $mysql_menu/03_manage_mysql_service.sh
}

# print host menu
menu_mysql() {
    menu_mysql_00="$MY0201"
    menu_mysql_01="$MY0045"
    menu_mysql_02="$MY0046"
    menu_mysql_03="$MY0047"
    menu_mysql_04="$MY0048"
    menu_mysql_05="$MY0049"
    menu_mysql_06="$MY0050"

    menu_logo="$MY0051"

    MYSQL_MENU_SELECT=
    until [[ -n "$MYSQL_MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $menu_log
        echo

        # mysql servers list
        print_mysql_servers_status
        # task info
        get_task_by_type '(mysql|monitor)' POOL_MYSQL_TASK_LOCK POOL_MYSQL_TASK_INFO
        print_task_by_type '(mysql|monitor)' "$POOL_MYSQL_TASK_LOCK" "$POOL_MYSQL_TASK_INFO"

        if [[ $POOL_MYSQL_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_mysql_00"
        else
            menu_list="\n\t$menu_mysql_01\n\t$menu_mysql_02\n\t$menu_mysql_03\n\t$menu_mysql_04"
            if [[ $MYSQL_SLAVES_CNT -gt 0 ]]; then
                menu_list="$menu_list\n\t$menu_mysql_05\n\t$menu_mysql_06"
            fi
            menu_list="$menu_list\n\t$menu_mysql_00"
        fi
        print_menu

        print_message "$MY0205" '' '' MYSQL_MENU_SELECT
       
        case "$MYSQL_MENU_SELECT" in
            "1") update_mysql_configs   ;;
            "2") change_mysql_password  ;;
            "3") manage_mysql_service   ;;
            "4") create_mysql_slave     ;;
            "5") change_mysql_master    ;;
            "6") remove_mysql_slave     ;;
            "0") exit ;;
            *)   error_pick; MYSQL_MENU_SELECT=;;
        esac

        MYSQL_MENU_SELECT=
done
}

menu_mysql

