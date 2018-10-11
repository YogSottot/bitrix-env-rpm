PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

set_new_password(){
    local srv="${1}"
    local task_cmd="$bx_mysql_script -a change_password -s $srv"

    print_message "$(get_text "$MY0018" "$srv")" \
        "" "" user_choice "Y"
    [[ $(echo $user_choice | grep -wci "y") -eq 0 ]] && return 1

    ask_password_info "MySQL root" MYSQL_PASSWORD
    [[ $? -gt 0 ]] && return 1

    MYSQL_PASSWORD_FILE=$(mktemp $CACHE_DIR/.mysqlXXXXXXXX)
    echo "$MYSQL_PASSWORD" > $MYSQL_PASSWORD_FILE

    task_cmd="${task_cmd} --password_file $MYSQL_PASSWORD_FILE"

    [[ $DEBUG -gt 0  ]] && \
        echo "task_cmd=$task_cmd"
    exec_pool_task "$task_cmd" "$(get_text "$MY0019" "$srv")"
}

create_client_config(){
    local srv="${1}"
    local task_cmd="$bx_mysql_script -a client_config -s $srv"

    print_message "$MY0020" "$MY0021" "" user_choice "Y"

    [[ $(echo $user_choice | grep -wci "y") -eq 0  ]] && return 1
    
    print_message "$MY0022" "" "-s" MYSQL_PASSWORD

    if [[ -z $MYSQL_PASSWORD ]]; then
        print_message "$MY0200" "$MY0023" "" any_key
        return 1
    fi

    MYSQL_PASSWORD_FILE=$(mktemp $CACHE_DIR/.mysqlXXXXXXXX)
    echo "$MYSQL_PASSWORD" > $MYSQL_PASSWORD_FILE
    task_cmd="${task_cmd} --password_file $MYSQL_PASSWORD_FILE"

    [[ $DEBUG -gt 0  ]] && \
        echo "task_cmd=$task_cmd"
    exec_pool_task "$task_cmd" "$(get_text "$MY0024" "$srv")"
}

change_root_password(){
    local srv="${1}"
    local task_cmd="$bx_mysql_script -a change_password -s $srv"

    print_message "$(get_text "$MY0025" "$srv")" \
        "" "" user_choice "N"
    [[ $(echo $user_choice | grep -wci "y") -eq 0 ]] && return 1

    ask_password_info "MySQL root" MYSQL_PASSWORD
    [[ $? -gt 0 ]] && return 1

    MYSQL_PASSWORD_FILE=$(mktemp $CACHE_DIR/.mysqlXXXXXXXX)
    echo "$MYSQL_PASSWORD" > $MYSQL_PASSWORD_FILE

    task_cmd="${task_cmd} --password_file $MYSQL_PASSWORD_FILE"

    [[ $DEBUG -gt 0  ]] && \
        echo "task_cmd=$task_cmd"
    exec_pool_task "$task_cmd" "$(get_text "$MY0026" "$srv")"
}

update_mysql_root_password(){
    local my_server="${1}"

    if [[ -z $my_server ]]; then
        print_message "$MY0200" \
            "$MY0027" "" any_key
        exit
    fi

    cache_mysql_servers_status
    local my_data=$(echo "$MYSQL_SERVERS" | grep "^$my_server:")
    if [[ -z $my_data ]]; then
        my_data=$(echo "$MYSQL_SERVERS" | grep ":$my_server$")
    fi
    if [[ -z "$my_data" ]]; then
        print_message "$MY0200" \
            "$(get_text "$MY0028" "$my_server")" "" any_key
        exit
    fi

    [[ $DEBUG -gt 0 ]] && \
        echo "server data=$my_data"

    local my_passwd=$(echo "$my_data" | awk -F':' '{print $8}')
    local my_config=$(echo "$my_data" | awk -F':' '{print $9}')

    MYSQL_PASSWORD=
    if [[ $my_passwd == "N" ]]; then
        set_new_password "$my_server"
    else
        if [[ $my_config == "N" ]]; then
            create_client_config "$my_server"
        else
            change_root_password "$my_server"
        fi
    fi
}

sub_menu(){
    menu_00="$MY0201"
    menu_01="   $MY0029"

    menu_logo="$MY0029"


    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $menu_logo
        echo

        # print all server list; because we need to create server for future slaves
        print_mysql_servers_status "" "0"
        
        # task info
        get_task_by_type '(mysql|monitor)' POOL_MYSQL_TASK_LOCK POOL_MYSQL_TASK_INFO
        print_task_by_type '(mysql|monitor)' "$POOL_MYSQL_TASK_LOCK" "$POOL_MYSQL_TASK_INFO"

        if [[ $POOL_MYSQL_TASK_LOCK -eq 1 ]]; then
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
            *) update_mysql_root_password "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
