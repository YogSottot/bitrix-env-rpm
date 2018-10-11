#!/bin/bash
# manage web instances
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/07_sphinx/functions.sh || exit 1
logo=$(get_logo)

create_sphinx_instance() {
    $sphinx_menu_dir/01_create_sphinx_instance.sh
}

create_sphinx_index() {
    $sphinx_menu_dir/02_create_sphinx_index.sh
}

delete_sphinx_instance() {
    $sphinx_menu_dir/03_delete_sphinx_instance.sh
}

# print host menu
submenu() {
    submenu_00="$SPH0201"
    submenu_01="$SPH0015"
    submenu_02="$SPH0016"
    submenu_03="$SPH0017"

    SUBMENU_SELECT=
    until [[ -n "$SUBMENU_SELECT" ]]; do

        menu_logo="$SPH0018"
        print_menu_header

        # sphinx servers list
        print_sphinx_servers_status 
        # task info
        get_task_by_type '(sphinx|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(sphinx|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"


        if [[ $POOL_SUBMENU_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$submenu_00"
        else
            if [[ $SPHINX_SERVERS_CN -eq 0 ]]; then
                menu_list="\n\t$submenu_01\n\t$submenu_00"
            elif [[ ( $SPHINX_SERVERS_CN -gt 0 ) && ( $NOSPHINX_SERVERS_CN -eq 0 ) ]]; then
                menu_list="\n\t$submenu_02\n\t$submenu_03\n\t$submenu_00"
            else
                menu_list="\n\t$submenu_01\n\t$submenu_02\n\t$submenu_03\n\t$submenu_00"
            fi
        fi

        print_menu
        print_message "$SPH0205" '' '' SUBMENU_SELECT
       
        case "$SUBMENU_SELECT" in
            "1") create_sphinx_instance  ;;
            "2") create_sphinx_index ;;
            "3") delete_sphinx_instance  ;;
            "0") exit ;;
            *)   error_pick; SUBMENU_SELECT=;;
        esac

        SUBMENU_SELECT=
done
}

submenu

