#!/usr/bin/bash
#
# manage web instances
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

tr_dir=$PROGPATH/11_transformer

. $PROGPATH/11_transformer/functions.sh || exit 1

logo=$(get_logo)

configure_tr_service() {
    $tr_dir/01_create_tr.sh
}

remove_tr_service() {
    $tr_dir/02_remove_tr.sh
}

# print host menu
submenu() {
    submenu_00="$TRANSF201"
    #submenu_01="1. $TRANSF003"
    #submenu_02="2. $TRANSF004"

    SUBMENU_SELECT=
    until [[ -n "$SUBMENU_SELECT" ]]; do
        menu_logo="$TRANSF008"
        print_menu_header

        print_transformer_status 
        # task info
        get_task_by_type '(web_cluster|mysql|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(web_cluster|mysql|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ $POOL_SUBMENU_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$submenu_00"
        else
            if [[ -z $TR_SERVER ]]; then
                menu_list="\n\t$submenu_01\n\t$submenu_00"
            else
                menu_list="\n\t$submenu_01\n\t$submenu_02\n\t$submenu_00"
            fi
        fi

        print_menu
        print_message "$PUSH205" '' '' SUBMENU_SELECT
       
        case "$SUBMENU_SELECT" in
            #"1") configure_tr_service ;;
            #"2") remove_tr_service ;;
            "0") exit ;;
            *) error_pick; SUBMENU_SELECT= ;;
        esac

        SUBMENU_SELECT=
    done
}

submenu
