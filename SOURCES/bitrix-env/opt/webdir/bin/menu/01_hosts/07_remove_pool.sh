#!/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1
[[ -z $DEBUG ]] && DEBUG=0


# return 0 - we will delete pool
# return 1 - found mysql cluster
# return 2 - found web cluster
# return 3 - found mysql server on another server in the group
# return 255 - something else
test_delete_conditions() {
    [[ -z $POOL_SERVER_LIST  ]] && cache_pool_info
    DESCRIBE_MESSAGE=

    # found not connected servers
    if [[ -n "$POOL_UNU_SERVER_LIST" ]]; then
        server_list=$(echo "$POOL_UNU_SERVER_LIST" | \
            awk -F':' '{printf "%s, ", $1}' | sed -e 's/^, //;s/, $//;')
        DESCRIBE_MESSAGE="$(get_text "$HM0026" "$server_list")"
        DESCRIBE_MESSAGE="$DESCRIBE_MESSAGE
        $HM0067"
        return 255
    fi
    [[ $DEBUG -gt 0 ]] && echo "POOL_SERVER_LIST=$POOL_SERVER_LIST"

    local cnt_mysql=$(echo "$POOL_SERVER_LIST" | awk -F':' '{print $3}'| grep -c 'mysql')
    local cnt_web=$(echo "$POOL_SERVER_LIST" | awk -F':' '{print $3}'| grep -c 'web')

    local mgmt_is_master=$(echo "$POOL_SERVER_LIST" | grep mysql_master | \
        awk -F':' '{print $3}' | grep -cw "mgmt")
    local master_name=$(echo "$POOL_SERVER_LIST" | grep mysql_master | \
        awk -F':' '{print $1}' | sed -e 's/^\s\+//;s/\s\+$//')

    [[ $DEBUG -gt 0 ]] && echo "cnt_mysql=$cnt_mysql cnt_web=$cnt_web mgmt_is_master=$mgmt_is_master"

    if [[ $cnt_mysql -gt 1 ]]; then
        DESCRIBE_MESSAGE="$(get_text "$HM0068" "mysql")"
        return 1
    fi
    if [[ $cnt_web -gt 1 ]]; then
        DESCRIBE_MESSAGE="$(get_text "$HM0068" "web")"
        return 2
    fi

    if [[ $mgmt_is_master -eq 0 ]]; then
        DESCRIBE_MESSAGE="$(get_text "$HM0069" "$master_name")"
        return 3
    fi
    return 0
}

warn_and_remove() {

    print_color_text "$HM0070" red
    echo "$HM0071"
    echo
    # test conditions
    test_delete_conditions
    test_delete_conditions_rtn=$?
    if [[ $test_delete_conditions_rtn -gt 0 ]]; then
        print_message "$HM0200" \
            "$DESCRIBE_MESSAGE" "" any_key
        return 1
    fi
    
    # deletion process
    print_message "$HM0072" "" "" confirm 'n'
    [[ $DEBUG -gt 0 ]] && echo $confirm
    [[ $(echo "$confirm" | grep -iwc 'n') -gt 0 ]] && return 1
    remove_pool
    if [[ $? -gt 0 ]]; then
        print_message "$HM0200" \
            "$DELETE_MSG" \
            "" any_key
        return 1
    else
        print_message "$HM0201" \
            "$HM0073" \
            "" any_key
        exit
    fi
}

menu_remove_pool() {
    local host_logo="$HM0074"
    local menu_00="$HM0042"
    local menu_01="1. $HM0074"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_pool_info
        
        menu_list="\n\t$menu_00\n\t$menu_01"
        print_menu

        print_message "$HM0204" '' '' HOST_MENU_SELECT
        # process selection
        case "$HOST_MENU_SELECT" in
            "0") exit ;;
            *) warn_and_remove ;;
        esac
        HOST_MENU_SELECT=
    done
}

menu_remove_pool

