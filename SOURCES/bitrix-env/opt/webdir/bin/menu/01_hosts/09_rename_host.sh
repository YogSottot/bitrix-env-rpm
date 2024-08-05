#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

#change_hostname() {
#    local chhost="$1"
#
#    if [[ -z "$chhost" ]]; then
#        print_message "$HM0200" \
#            "$HM0044" "" any_key
#        return 1
#    fi
#    # test if defined host exist in server list (small check without name resolution)
#    [[ -z "$POOL_SERVER_LIST" ]] && cache_pool_info
#    local host_iden=$(echo "$POOL_SERVER_LIST" | \
#        grep "\(^$chhost:\|:$chhost:\|=$chhost\)" | \
#        awk -F':' '{print $1}')
#    [[ $DEBUG -gt 0 ]] && echo "$POOL_SERVER_LIST"
#    if [[ -z $host_iden ]]; then
#        print_message "$HM203" "$(get_text "$HM0012" "$chhost")" \
#            "" answer "n"
#        [[ $(echo "$answer" | grep -iwc "n") -gt 0 ]] && exit 1
#        return 1
#    fi
#
#    print_message "$(get_text "$HM0095" "$chhost")" \
#        "" "" newhost
#    test_hostname "$newhost"
#    test_hostname_rtn=$?
#    [[ $test_hostname_rtn -gt 0 ]] && return $test_hostname_rtn
#
#    if [[ $newhost == "$chhost" ]]; then
#        print_message "$HM0200" \
#            "$HM0097" \ 
#            "" any_key
#        return 1
#    fi
#
#    if_hostname_exists_in_the_pool "$newhost"
#    if [[ $? -gt 0  ]]; then
#        print_message "$HM0200" \
#            "$(get_text "$HM0096" "$newhost")" \
#            "" any_key
#        return 1
#    fi
#
#    print_message "$(get_text "$HM0092" "$host_iden")" \
#        "" "" _confirm 'n'
#    if [[ $( echo "$_confirm" | grep -wci 'y' ) -gt 0 ]]; then
#        cmd="$ansible_wrapper -a change_hostname -H $host_iden --hostname $newhost"
#        if [[ $DEBUG -gt 0 ]]; then
#            echo "cmd=$cmd"
#        fi
#        exec_pool_task "$cmd" "change hostname"
#    fi
#    return 0
#}

# create host in the ansible config and copy ssh key on it
sub_menu() {
    host_logo="$HM0093"
    menu_00="$HM0042"
    menu_01="   $HM0093"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $host_logo
        echo

        print_pool_info
        
        # is there some task which can interrupted by adding new host (iptables and so on)
        get_task_by_type '(common|monitor|mysql|update)' POOL_HOST_TASK_LOCK POOL_HOST_TASK_LIST
        print_task_by_type '(common|monitor|mysql|update)' "$POOL_HOST_TASK_LOCK" "$POOL_HOST_TASK_LIST"

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t\t$menu_00"
        else
            menu_list="\n\t\t$menu_00\n\t\t$menu_01"
        fi

        print_menu

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            print_message "$HM0202" '' '' HOST_MENU_SELECT 0
        else
            print_message "$HM0043" '' '' HOST_MENU_SELECT
        fi
        # process selection
        case "$HOST_MENU_SELECT" in
            "0") exit ;;
            #*) change_hostname "$HOST_MENU_SELECT" ;;
        esac
        [[ $? -eq 0 ]] && POOL_SERVER_LIST=
        HOST_MENU_SELECT=
    done
}

sub_menu
