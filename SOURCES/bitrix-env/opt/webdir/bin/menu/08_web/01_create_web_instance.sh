#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

#one_step_web() {
#    local srv="${1}"
#
#    # WEB_CLUSTER_TYPE =< fstype
#    local task_exec="$bx_web_script -a create_web -H $srv --fstype $WEB_CLUSTER_TYPE"
#    [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
#
#    exec_pool_task "$task_exec" "$(get_text "$WEB0013" "$srv")"
#}

#two_step_web() {
#    local srv="${1}"
#    local sync_type="${2:-1}"
#
#    # WEB_SYNC_TM               - last timestamp for site synchronization process
#    # WEB_CLUSTER_WEB_SERVER    - server name with configured lsyncd
#    local task_exec=
#    if [[ $sync_type -eq 1 ]]; then
#        task_exec="$bx_web_script -a web1 -H $srv --fstype $WEB_CLUSTER_TYPE"
#        task_desc="$(get_text "$WEB0014" "$srv")"
#    else
#        task_exec="$bx_web_script -a web2 -H $srv --fstype $WEB_CLUSTER_TYPE"
#        task_desc="$(get_text "$WEB0015" "$srv")"
#    fi
#    [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
#
#    exec_pool_task "$task_exec" "$task_desc"
#}

#web_instance() {
#    local web_server="${1}"
#
#    [[ $DEBUG -gt 0 ]] && echo " web_server=$web_server"
#
#    cache_web_servers_status
#    local web_data=$(echo "$WEB_SERVERS" | egrep -v ":(spare|main):" | \
#        grep "^$web_server:")
#    if [[ -z $web_data ]]; then
#        print_message "$WEB0200" \
#            "$(get_text "$WEB0206" "$web_server")" "" any_key
#        exit
#    fi
#
#    # test pool configuration
#    check_web_options
#    if [[ $? -gt 0 ]]; then
#        print_message "$WEB0200" "" "" any_key
#        exit
#    fi
#
#    # we can split configuration into two stages:
#    # 1. Preliminary site's data synchronization
#    # 2. Cluster configuration
#    # or complete two stages in one step
#    print_color_text "$WEB0016" blue
#    echo -e "$WEB0017"
#    echo -e "$WEB0018"
#    echo -e "$WEB0019"
#    echo -e "$WEB0020"
#    echo -e "$WEB0021"
#    echo
#    echo -e "$WEB0022"
#    echo
#    if [[ -z $WEB_CLUSTER_WEB_SERVER ]]; then
#        print_message "$WEB0023" '' '' conf_type 1
#
#        if [[ $conf_type -eq 1 ]]; then
#            one_step_web $web_server
#        elif [[ $conf_type -eq 2 ]]; then
#            print_color_text \
#                "$WEB0024"
#
#            two_step_web $web_server 1
#        else
#            print_message "$WEB0200" \
#                "$WEB0025 $conf_type" "" any_key
#            exit
#
#        fi
#    else
#        if [[ $WEB_CLUSTER_WEB_SERVER == "$web_server" ]]; then
#            print_color_text \
#                "$(get_text "$WEB0026" "$WEB_CLUSTER_WEB_SERVER")"
#            print_color_text \
#                "$WEB0027"
#            two_step_web $web_server 2
#        else
#            print_color_text \
#                "$(get_text "$WEB0028" "$WEB_CLUSTER_WEB_SERVER" "$web_server")"
#            print_message "$WEB0029" \
#                "$(get_text "$WEB0030" "$WEB_CLUSTER_WEB_SERVER")" \
#                "" any_key "n"
#            if [[ $(echo "$any_key" | grep -wci "y") -gt 0 ]]; then
#                two_step_web $web_server 1
#            else
#                exit
#            fi
#        fi
#    fi
#}

sub_menu() {
    menu_00="$WEB0201"
    menu_01="   $WEB0031"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$WEB0031"
        print_menu_header

        # print all
        print_web_servers_status "(main|spare)" "0"
        print_web_servers_status_rtn=$?

        # task info
        get_task_by_type '(web_cluster|mysql|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(web_cluster|mysql|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ ( $POOL_SUBMENU_TASK_LOCK -eq 1 ) || \
            ( $print_web_servers_status_rtn -gt 0  ) ]]; then
            menu_list="\n$menu_00"
        else
            menu_list="\n$menu_01\n$menu_00"
        fi

        print_menu

        if [[ ( $POOL_SUBMENU_TASK_LOCK -gt 0 ) || ( $print_web_servers_status_rtn -gt 0 ) ]]; then
            print_message "$WEB0202" '' '' MENU_SELECT 0
        else
            print_message "$WEB0204" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            #*) web_instance "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
