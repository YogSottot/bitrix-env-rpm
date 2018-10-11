#!/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

enable_beta_version(){
    print_message "$HM0106" \
        "$HM0107" \
        "" confirm "n"
     if [[ $( echo "$confirm" | grep -wci 'y'  ) -gt 0  ]]; then
        cmd="$ansible_wrapper -a enable_beta_version"
        if [[ $DEBUG -gt 0 ]]; then
            echo "cmd=$cmd"
        fi

        if [[ $IN_POOL -gt 0 ]]; then
            exec_pool_task "$cmd" "$HM0108"
        else
            bx_enable_beta_version
        fi

     fi

}

disable_beta_version(){
    print_message "$HM0109" \
        "" "" confirm "y"
     if [[ $( echo "$confirm" | grep -wci 'y'  ) -gt 0  ]]; then
        cmd="$ansible_wrapper -a disable_beta_version"
        if [[ $DEBUG -gt 0 ]]; then
            echo "cmd=$cmd"
        fi
        if [[ $IN_POOL -gt 0 ]]; then
            exec_pool_task "$cmd" "$HM0110"
        else
            bx_disable_beta_version
        fi
     fi
}

create_menu_list() {
    bx_repo_version
    bx_repo_version_rn=$?

    host_logo="$HM0103"
    menu_01="1. $HM0103"
    if [[ $bx_repo_version_rn -eq 2 ]]; then
        host_logo="$HM0104"
        menu_01="1. $HM0104"
    fi
}

# create host in the ansible config and copy ssh key on it
sub_menu() {
    menu_00="$HM0042"

    get_client_settings

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        create_menu_list

        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        if [[ $IN_POOL -gt 0 ]]; then
            print_pool_info
        
            # is there some task which can interrupted by adding new host (iptables and so on)
            get_task_by_type '(common|monitor|mysql|update)' POOL_HOST_TASK_LOCK POOL_HOST_TASK_LIST
            print_task_by_type '(common|monitor|mysql|update)' "$POOL_HOST_TASK_LOCK" "$POOL_HOST_TASK_LIST"
        else
            POOL_HOST_TASK_LOCK=0
        fi

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_00"
        else
            menu_list="\n\t$menu_00\n\t$menu_01"
        fi

        print_menu

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            print_message "$HM0202" '' '' MENU_SELECT 0
        else
            print_message "$HM0204" '' '' MENU_SELECT 0
        fi
        # process selection
        case "$MENU_SELECT" in
            "0") exit ;;
            "1") 
                if [[ $bx_repo_version_rn -eq 2 ]]; then
                    disable_beta_version
                else 
                    enable_beta_version
                fi;;
            *)   error_pick; POOL_SERVER_LIST= ;;
        esac
        [[ $? -eq 0 ]] && POOL_SERVER_LIST=
        HOST_MENU_SELECT=
    done
}

sub_menu

