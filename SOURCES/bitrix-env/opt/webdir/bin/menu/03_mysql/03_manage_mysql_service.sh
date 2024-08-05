#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

manage_mysql_service() {
    local my_server="${1}"

    cache_mysql_servers_status
    local my_data=$(echo "$MYSQL_SERVERS" | grep "^$my_server:")
    if [[ -z $my_data ]]; then
        my_data=$(echo "$MYSQL_SERVERS" | grep ":$my_server$")
    fi
    if [[ -z "$my_data" ]]; then
        print_message "$MY0200" "$(get_text "$MY0028" "$my_server")" "" any_key
    fi

    [[ $DEBUG -gt 0 ]] && echo "server data=$my_data"
    local my_status=$(echo "$my_data" | awk -F':' '{print $7}')

    local task_cmd="$bx_mysql_script -s $my_server"
    if [[ $my_status == "active" ]]; then
        print_message "$(get_text "$MY0030" "$my_server")" "" "" user_choice "N"
        [[ $(echo $user_choice | grep -wci "y") -eq 0   ]] && return 1
        task_cmd="$task_cmd -a stop_service"
        task_type=Stop
    else
        print_message "$(get_text "$MY0031" "$my_server")" "" "" user_choice "Y"
        [[ $(echo $user_choice | grep -wci "y") -eq 0   ]] && return 1
        task_cmd="$task_cmd -a start_service"
        task_type=Start
    fi

    [[ $DEBUG -gt 0   ]] && echo "task_cmd=$task_cmd"
    exec_pool_task "$task_cmd" "$(get_text "$task_type" "$my_server")"

    print_message "$MY0200" "" "" any_key
}

sub_menu() {
    menu_00="$MY0201"
    menu_01="$MY0034"

    menu_logo="$MY0035"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $menu_logo
        echo

        # print all server list; because we need to create server for future slaves
        print_mysql_servers_status "" "0"

        # task info
        get_task_by_type '(mysql|monitor)' POOL_MYSQL_TASK_LOCK POOL_MYSQL_TASK_INFO
        print_task_by_type '(mysql|monitor)' "$POOL_MYSQL_TASK_LOCK" "$POOL_MYSQL_TASK_INFO"

        if [[ $POOL_MYSQL_TASK_LOCK -eq 1 ]]; then
            menu_list="$menu_00"
        else
            menu_list="$menu_01\n\t\t $menu_00"
        fi

        print_menu

        if [[ $POOL_MYSQL_TASK_LOCK -gt 0 ]]; then
            print_message "$MY0202" '' '' MENU_SELECT 0
        else
            print_message "$MY0204" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            *) manage_mysql_service "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
