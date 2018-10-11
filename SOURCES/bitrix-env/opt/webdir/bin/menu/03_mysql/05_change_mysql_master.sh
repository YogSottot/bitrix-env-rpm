PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

change_master(){
    local my_server="${1}"

    # test if server exist
    cache_mysql_servers_status
    local my_data=$(echo "$MYSQL_SERVERS" | egrep ":slave:" |  grep "^$my_server:")
    if [[ -z $my_data  ]]; then
        my_data=$(echo "$MYSQL_SERVERS" | egrep ":slave:" | grep ":$my_server$")
    fi
    if [[ -z "$my_data" ]]; then
        print_message "$MY0200" \
            "$(get_text "$MY0038" "$my_server")" "" any_key
    fi

    # test server settings
    check_mysql_options
    if [[ $? -gt 0 ]]; then
        print_message "$MY0200" \
            "" "" any_key
        exit
    fi

    local task_cmd="$bx_mysql_script -s $my_server -a master"
    [[ $DEBUG -gt 0   ]] && \
        echo "task_cmd=$task_cmd"
    exec_pool_task "$task_cmd" "$(get_text "$MY0041" "$my_server")"
}

sub_menu(){
    menu_00="$MY0201"
    menu_01="   $MY0042"

    menu_logo="$MY0042"


    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $menu_logo
        echo

        # print only slave servers
        print_mysql_servers_status "master" "1"
        print_mysql_servers_status_rtn=$?
        
        # task info
        get_task_by_type '(mysql|monitor)' POOL_MYSQL_TASK_LOCK POOL_MYSQL_TASK_INFO
        print_task_by_type '(mysql|monitor)' "$POOL_MYSQL_TASK_LOCK" "$POOL_MYSQL_TASK_INFO"

        # background task or not found free servers in the pool
        if [[ ( $POOL_MYSQL_TASK_LOCK -eq 1 )  || ( $print_mysql_servers_status_rtn -gt 0 )]]; then
            menu_list="\n$menu_00"
        else
            menu_list="\n$menu_01\n$menu_00"
        fi
        
        print_menu

        if [[ $POOL_MYSQL_TASK_LOCK -gt 0 ]]; then
            print_message "$MY0202" '' '' MENU_SELECT 0
        else
            print_message "$MY0204" '' '' MENU_SELECT 
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            *) change_master "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
