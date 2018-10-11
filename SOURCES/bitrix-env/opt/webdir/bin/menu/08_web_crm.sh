#!/bin/bash
# manage web instances
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/08_web/functions.sh || exit 1
logo=$(get_logo)

create_web_instance() {
    $submenu_dir/01_create_web_instance.sh
}

delete_web_instance() {
    $submenu_dir/02_delete_web_instance.sh
}

manage_php_exts() {
    $submenu_dir/03_php_module.sh
}

manage_certificates() {
    $submenu_dir/04_manage_certificates.sh
}

# print host menu
submenu() {
    submenu_00="$WEB0201"
    submenu_01="$WEB0066"
    submenu_02="$WEB0067"



    SUBMENU_SELECT=
    until [[ -n "$SUBMENU_SELECT" ]]; do

        menu_logo="$WEB0065"
        print_menu_header

        # mysql servers list
        print_web_servers_status 
        # task info
        get_task_by_type '(web_cluster|mysql|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(web_cluster|mysql|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ $POOL_SUBMENU_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$submenu_00"
        else
            menu_list="\n\t$submenu_01\n\t$submenu_02\n\t$submenu_00"
        fi

        print_menu
        print_message "$WEB0205" '' '' SUBMENU_SELECT
       
        case "$SUBMENU_SELECT" in
            "1") manage_php_exts  ;;
            "2") manage_certificates ;;
            "0") exit ;;
            *)   error_pick; SUBMENU_SELECT=;;
        esac

        SUBMENU_SELECT=
done
}

submenu

