#!/usr/bin/bash
#
# manage tasks in the pool
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG  ]] && DEBUG=0

. $PROGPATH/05_task/functions.sh || exit 1

logo=$(get_logo)

# manage running tasks
running_tasks() {
    menu_rtask_00="$T0201"
    menu_rtask_01="$T0015"

    TASK_MENU_SELECT_01=
    until [[ -n "$TASK_MENU_SELECT_01" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        print_pool_tasks "" "running"
        if [[ $FILTERED_TASK_CNT -eq 0 ]]; then
            menu_list="$menu_rtask_00"
        else
            menu_list="$menu_rtask_01\n\t\t $menu_rtask_00"
        fi
        print_menu

        print_message "$T0205" '' '' TASK_MENU_SELECT_01

        # process selection
        case "$TASK_MENU_SELECT_01" in
            "1") stop_task ;;
            "0") exit ;;
            *) error_pick; TASK_MENU_SELECT= ;;
        esac
    done
}

# print host menu
menu_tasks() {
    menu_task_00="$T0201"
    menu_task_01="$T0016"
    menu_task_02=" $T0017"

    tasks_logo="$T0018"

    TASK_MENU_SELECT=
    until [[ -n "$TASK_MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $tasks_logo
        echo

        # menu
        print_pool_tasks

        # define menu points
        if [[ $POOL_TASKS_COUNT -eq 0 ]]; then
            menu_list="$menu_task_00"
        else
            menu_list="$menu_task_01\n\t\t$menu_task_02\n\t\t $menu_task_00"
        fi
        print_menu

        print_message "$T0205" '' '' TASK_MENU_SELECT

        # process selection
        case "$TASK_MENU_SELECT" in
            "1") running_tasks ;;
            "2") clear_history ;;
            "0") exit ;;
            *) error_pick; TASK_MENU_SELECT= ;;
        esac
        TASK_MENU_SELECT=
    done
}

menu_tasks
