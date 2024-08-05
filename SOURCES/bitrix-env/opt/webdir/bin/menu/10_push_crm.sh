#!/usr/bin/bash
#
# manage web instances
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/10_push/functions.sh || exit 1

logo=$(get_logo)

configure_push_service() {
    $submenu_dir/01_configure_push_service.sh
}

# print host menu
submenu() {
    submenu_00="$PUSH201"
    #submenu_01="1. $PUSH006"

    SUBMENU_SELECT=
    until [[ -n "$SUBMENU_SELECT" ]]; do
        menu_logo="$PUSH011"
        print_menu_header

        print_push_servers_status 
        # task info
        get_task_by_type '(web_cluster|mysql|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(web_cluster|mysql|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ $POOL_SUBMENU_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$submenu_00"
        else
            if [[ $PUSH_VERSION -eq 1 ]]; then
                menu_list="\n\t$submenu_01\n\t$submenu_00"
            else
                menu_list="\n\t$submenu_00"
            fi
        fi

        print_menu
        print_message "$PUSH205" '' '' SUBMENU_SELECT
       
        case "$SUBMENU_SELECT" in
            #"1") 
                #if [[ $PUSH_VERSION -eq 1 ]]; then
                    #configure_push_service
                #else
                    #error_pick
                #fi;;
            "0") exit ;;
            *)   error_pick; SUBMENU_SELECT=;;
        esac

        SUBMENU_SELECT=
    done
}

submenu
