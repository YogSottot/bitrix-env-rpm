#!/usr/bin/bash
#
# manage host in the pool
# ex.
# add|create - add host vto the pool
# delete     - delete host in the pool
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/01_hosts/functions.sh || exit 1

# create host in the ansible config and copy ssh key on it
menu_create_host() {
    $hosts_menu/01_add_host.sh
}

# delete host from pool
# this action can be done on empty server
menu_delete_host() {
    $hosts_menu/02_delete_host.sh
}

menu_reboot_host() {
    $hosts_menu/03_reboot_host.sh
}

menu_update_host() {
    $hosts_menu/04_update_host.sh
}

menu_passw_bitrix_host() {
    $hosts_menu/05_change_password.sh
}

menu_configure_tz() {
    $hosts_menu/06_configure_tz.sh
}

menu_remove_pool() {
    $hosts_menu/07_remove_pool.sh
    exit
}

menu_upgrade_php() {
    $hosts_menu/08_upgrade_php_mysql.sh
}

# print host menu
menu_host() {
    #local menu_03="1. $HM1003"
    #local menu_04="2. $HM1004"
    #local menu_05="3. $HM1005"
    #local menu_06="4. $HM1006"
    #local menu_07="5. $HM1007"
    #local menu_08="6. $HM1008"
    local menu_00="$HM0009"

    HOST_MENU_SELECT=

    until [[ -n "$HOST_MENU_SELECT" ]]; do
        menu_logo="$HM0010"
        print_menu_header

        # menu
        print_pool_info           # print main host list

        # get upgrade task if the one exists in background
        get_task_by_type upgrade_mysql_php POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type upgrade_mysql_php "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        

        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_00"
        else
            menu_list="\n\t$menu_03\n\t$menu_04\n\t$menu_05"
            menu_list=$menu_list"\n\t$menu_06\n\t$menu_07\n\t$menu_08\n\t$menu_00"
        fi
        print_menu
        print_message "$HM0011" '' '' HOST_MENU_SELECT

        # process selection
        case "$HOST_MENU_SELECT" in
            #"1") menu_reboot_host ;;
            #"2") menu_update_host ;;
            #"3") menu_passw_bitrix_host ;;
            #"4") menu_configure_tz ;;
            #"5") menu_remove_pool ;;
            #"6") menu_upgrade_php ;;
            "0") exit ;;
            *) error_pick; HOST_MENU_SELECT= ;;
        esac
        HOST_MENU_SELECT=
    done
}

menu_host
