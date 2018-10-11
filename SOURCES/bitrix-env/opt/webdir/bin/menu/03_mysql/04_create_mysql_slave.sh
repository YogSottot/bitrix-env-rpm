PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

get_mysql_settings(){
    if [[ ! -f $ansible_mysql_group ]]; then
        print_message "$MY0200" \
            "$(get_text "$MY0036" "$ansible_mysql_group")" "" any_key
        return 1
    fi

    MYSQL_OPTIONS="replica_login==bx_repluser
replica_password==
cluster_login==bx_clusteruser
cluster_password=="

    for opt_portrait in $MYSQL_OPTIONS; do
        my_key=$(echo "$opt_portrait" | awk -F'=' '{print $1}')
        my_value=$(echo "$opt_portrait" | awk -F'=' '{print $2}')
        my_default=$(echo "$opt_portrait" | awk -F'=' '{print $3}')

        # if value exists in the config than script doesn't change it
        is_inventory_value_exists=$(grep -v '^$\|^#' $ansible_mysql_group | \
            grep "^$my_key:" | awk -F':' '{print $2}' | grep -cv "^\s*$"  )
        [[ $DEBUG -gt 0 ]] && \
            echo "$my_key => $is_inventory_value_exists"

        if [[ $is_inventory_value_exists -gt 0 ]]; then
            MYSQL_OPTIONS=$(echo "$MYSQL_OPTIONS" | \
                sed -e "s/$my_key==/$my_key=FROM_INVENTORY_FILE=/")
            continue
        fi

        # in other case use must define options
        if [[ $(echo "$my_key" | grep -c "_password$") -gt 0 ]]; then
            ask_password_info "$(echo $my_key | awk -F'_' '{print $1}')" MYSQL_PASSWORD
            [[ $? -gt 0 ]] && return 1
            MYSQL_PASSWORD_FILE=$(mktemp $CACHE_DIR/.${my_key}XXXXXXXX)
            echo "$MYSQL_PASSWORD" > $MYSQL_PASSWORD_FILE
            MYSQL_OPTIONS=$(echo "$MYSQL_OPTIONS" | \
                sed -e "s:$my_key==:$my_key=$MYSQL_PASSWORD_FILE=:")
        else
            key_var1="$(echo $my_key | awk -F'_' '{print $1}')"
            key_var2="$(echo $my_key | awk -F'_' '{print $2}')"
            print_message \
                "$MY0037 $key_var1 $key_var2: " \
                "" "" "user_choice" "$my_default"
            MYSQL_OPTIONS=$(echo "$MYSQL_OPTIONS" | \
                sed -e "s/$my_key==/$my_key=$user_choice=/")
        fi
    done

    if [[ $DEBUG -gt 0 ]]; then
        for opt_portrait in $MYSQL_OPTIONS; do
            printf "%-10s: %s\n" \
                "$(echo "$opt_portrait" | awk -F'=' '{print $1}')" \
                "$(echo "$opt_portrait" | awk -F'=' '{print $2}')"
        done
    fi
}

create_slave(){
    local my_server="${1}"

    # test if server exist
    cache_mysql_servers_status
    local my_data=$(echo "$MYSQL_SERVERS" | egrep -v ":(master|slave):" |  grep "^$my_server:")
    if [[ -z $my_data  ]]; then
        my_data=$(echo "$MYSQL_SERVERS" | egrep -v ":(master|slave):" |grep ":$my_server$")
    fi
    if [[ -z "$my_data" ]]; then
        print_message "$MY0200" \
            "$(get_text "$MY0038" "$my_server")" "" any_key
        exit
    fi

    # test server settings
    check_mysql_options "$my_server"
    if [[ $? -gt 0 ]]; then
        print_message "$MY0200" \
            "" "" any_key
        exit
    fi

    # test inventory options and create them by asking user
    get_mysql_settings 
    if [[ $? -gt 0 ]]; then
        print_message "$MY0200" \
            "" "" any_key
        exit
    fi

    local task_cmd="$bx_mysql_script -s $my_server -a slave"
    for opt_portrait in $MYSQL_OPTIONS; do
        my_key=$(echo "$opt_portrait" | awk -F'=' '{print $1}')
        my_value=$(echo "$opt_portrait" | awk -F'=' '{print $2}')

        if [[ $my_value != "FROM_INVENTORY_FILE" ]]; then
            task_cmd="$task_cmd --$my_key $my_value"
        fi
    done

    [[ $DEBUG -gt 0   ]] && \
        echo "task_cmd=$task_cmd"
    exec_pool_task "$task_cmd" "$(get_text "$MY0039" "$my_server")"
}

sub_menu(){
    menu_00="$MY0200"
    menu_01="$MY0040"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$MY0040"
        print_menu_header

        # print all server list; because we need to create server for future slaves
        print_mysql_servers_status "(slave|master)" "0"
        print_mysql_servers_status_rtn=$?
        
        # task info
        get_task_by_type '(mysql|monitor)' POOL_MYSQL_TASK_LOCK POOL_MYSQL_TASK_INFO
        print_task_by_type '(mysql|monitor)' "$POOL_MYSQL_TASK_LOCK" "$POOL_MYSQL_TASK_INFO"

        # background task or not found free servers in the pool
        if [[ ( $POOL_MYSQL_TASK_LOCK -eq 1 )  || ( $print_mysql_servers_status_rtn -gt 0 )]]; then
            menu_list="\n\t$menu_00"
        else
            menu_list="\n\t$menu_01\n\t$menu_00"
        fi
        
        print_menu

        if [[ $POOL_MYSQL_TASK_LOCK -gt 0 ]]; then
            print_message "$MY0202" '' '' MENU_SELECT 0
        else
            print_message "$MY0204" '' '' MENU_SELECT 
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            *) create_slave "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
