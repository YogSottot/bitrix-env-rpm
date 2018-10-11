#!/bin/bash
# manage sites and site's options 
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/04_memcached/functions.sh || exit 1
logo=$(get_logo)

# print host menu
menu_mc() {

  menu_mc_00="$MC0201"
  menu_mc_01="$MC0006"
  menu_mc_02="$MC0007"
  menu_mc_03="$MC0008"

  mc_logo="$MC0009"

  MC_MENU_SELECT=
  until [[ -n "$MC_MENU_SELECT" ]]; do
    clear
    echo -e "\t\t\t" $logo
    echo -e "\t\t\t" $mc_logo
    echo

    # menu
    get_mc_number
    print_pool_info
    get_task_by_type '(memcached|monitor)' POOL_MC_TASK_LOCK POOL_MC_TASK_INFO
    print_task_by_type '(memcached|monitor)' "$POOL_MC_TASK_LOCK" "$POOL_MC_TASK_INFO"

    # define menu points
    if [[ $POOL_MC_TASK_LOCK -eq 1 ]]; then
      menu_list="\n\t$menu_mc_00"
    else
      if [[ $MC_SERVERS_CN -eq 0 ]]; then
        menu_list="\n\t$menu_mc_01\n\t$menu_mc_00"
      else
        menu_list="\n\t$menu_mc_01\n\t$menu_mc_02\n\t$menu_mc_03\n\t$menu_mc_00"
      fi
    fi
    print_menu

    print_message "$MC0205" '' '' MC_MENU_SELECT

    # process selection
    case "$MC_MENU_SELECT" in
      "1") create_mc; POOL_SERVER_LIST=;;
      "2") update_mc ;;
      "3") remove_mc; POOL_SERVER_LIST= ;;
      "0") exit ;;
      *)   error_pick; _host_select=;;
    esac

    MC_MENU_SELECT=
  done
}

menu_mc

