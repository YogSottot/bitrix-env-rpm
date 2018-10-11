#!/bin/bash
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

menu_rename_server(){
    $hosts_menu/09_rename_host.sh
}

menu_change_repo(){
    $hosts_menu/10_change_repository.sh
}


# print host menu
submenu() {
    local menu_01="$HM0001" #_create_host
    local menu_02="$HM0002"    #_delete_host
    local menu_03="$HM0003"
    local menu_04="$HM0004"
    local menu_05="$HM0005"
    local menu_06="$HM0006"
    local menu_07="$HM0007"
    local menu_08="$HM0008"
    local menu_09="$HM0098"
    local menu_10="$HM0105"

    local menu_00="$HM0009"  # exit

    host_logo="$HM0010"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        # menu
        print_pool_info           # print main host list

        # get upgrade task if the one exists in background
        get_task_by_type upgrade_mysql_php POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type upgrade_mysql_php "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        

        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_00"
        else
            menu_list="\n\t$menu_01\n\t$menu_02\n\t$menu_03\n\t$menu_04"
            menu_list="$menu_list\n\t$menu_05\n\t$menu_06\n\t$menu_07\n\t$menu_08"
            menu_list="$menu_list\n\t$menu_09\n\t$menu_10\n\t$menu_00"
        fi
        print_menu
        print_message "$HM0011" '' '' HOST_MENU_SELECT
        if [[ $POOL_SITE_TASK_LOCK -eq 1  ]]; then
            case "$HOST_MENU_SELECT" in
                "0") exit ;;
                *) error_pick ; HOST_MENU_SELECT=;;
            esac
        else
            # process selection
            case "$HOST_MENU_SELECT" in
                "1") menu_create_host; POOL_SERVER_LIST= ;;
                "2") menu_delete_host; POOL_SERVER_LIST= ;;
                "3") menu_reboot_host ;;
                "4") menu_update_host ;;
                "5") menu_passw_bitrix_host ;;
                "6") menu_configure_tz ;;
                "7") menu_remove_pool; POOL_SERVER_LIST= ;;
                "8") menu_upgrade_php ;;
                "9") menu_rename_server; POOL_SERVER_LIST= ;;
                "10") menu_change_repo; POOL_SERVER_LIST= ;;
                "0") exit ;;
                *)   error_pick; HOST_MENU_SELECT=;;
            esac
        fi
        HOST_MENU_SELECT=
  done
}

submenu

