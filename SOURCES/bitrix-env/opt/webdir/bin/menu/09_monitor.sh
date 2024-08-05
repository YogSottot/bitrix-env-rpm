#!/usr/bin/bash
#
# manage monitoring options 
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/09_monitor/functions.sh || exit 1

logo=$(get_logo)

_configure_monitoring() {
    $monitor_menu/01_configure_monitoring.sh
}

_disable_monitoring() {
    $monitor_menu/02_disable_monitoring.sh
}

_update_monitoring() {
    $monitor_menu/03_update_monitoring.sh
}

# print host menu
_monitor_menu() {
    # Monitoring is disabled in the pool
    #menu_01="$MON0033"
    # Monitoring is enabled in the pool
    #menu_02="$MON0034"
    #menu_03="$MON0035"
    menu_00="$MON0201"

    MONITOR_MENU_SELECT=

    until [[ -n "$MONITOR_MENU_SELECT" ]]; do

        menu_logo="$MON0036"
        print_menu_header

        # menu
        # good looking page with monitoring status
        print_monitor_status
        print_monitor_status_rtn=$?
        # testing background tasks
        get_task_by_type monitor POOL_MONITOR_TASK_LOCK POOL_MONITOR_TASK_INFO
        print_task_by_type monitor "$POOL_MONITOR_TASK_LOCK" "$POOL_MONITOR_TASK_INFO"

        # found backgroud tasks
        if [[ $POOL_MONITOR_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_00"

        # not found background tasks
        else
            # monitoring services don't configure
            if [[ $print_monitor_status_rtn -eq 1 ]]; then
                menu_list="\n\t$menu_01\n\t$menu_00"
            # request to status of monitoring services return error
            elif [[ $print_monitor_status_rtn -eq 2 ]]; then
                exit
            # monitorings services are configured
            else 
                menu_list="\n\t$menu_01\n\t$menu_02\n\t$menu_03\n\t$menu_00"
            fi
        fi

        print_menu
        print_message "$MON0205" '' '' SUBMENU_SELECT

        # process selection
        case "$SUBMENU_SELECT" in
        #"1") _configure_monitoring;;
        #"2") _disable_monitoring ;;
        #"3") _update_monitoring ;;
        "0") exit ;;
        *) error_pick ;;
        esac
        MONITOR_MENU_SELECT=
        POOL_MONITOR_SERVER=
    done
}

_monitor_menu
