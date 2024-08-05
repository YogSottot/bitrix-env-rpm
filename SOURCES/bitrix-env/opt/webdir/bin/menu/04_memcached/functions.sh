#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_mc_script=$BIN_DIR/bx-mc
bx_process_script=$BIN_DIR/bx-process
bx_host_script=$BIN_DIR/wrapper_ansible_conf
mc_menu=$BIN_DIR/menu/04_memcached

# get_text variables
[[ -f $mc_menu/functions.txt  ]] && \
        . $mc_menu/functions.txt

# count memcached servers in the pool
# fill out 
# MC_SERVERS_CN
get_mc_number() {
    [[ -z "$POOL_SERVER_LIST"  ]] && cache_pool_info
    MC_SERVERS_CN=$(echo "$POOL_SERVER_LIST" | grep -cw "memcached")
}

print_mc_servers() {
    [[ $DEBUG -eq 0 ]] && clear
    get_mc_number 
    if [[ $MC_SERVERS_CN -eq 0 ]]; then
        print_message "$MC0200" "$MC0001" "" any_key
        return 1
    fi
    print_pool_info "" "memcached" 
}

update_mc() {
    print_mc_servers || return 1

    task_cmd="$bx_mc_script -a update"
    [[ $DEBUG -gt 0 ]] && echo "task_cmd=\`$task_cmd\`"
    exec_pool_task "$task_cmd" "$MC0002"
}

create_mc() {
    [[ $DEBUG -eq 0 ]] && clear
    print_pool_info "memcached"
    print_message "$MC0003" "" "" mc_server
    test_server=$(echo "$POOL_SERVER_LIST" | grep -cw "$mc_server")
    if [[ $test_server -eq 0 ]]; then
         print_message "$MC0200" "$(get_text "$MC0206" "$mx_server")" "" any_key
         return 1
    fi

    task_cmd="$bx_mc_script -a create -s $mc_server"
    [[ $DEBUG -gt 0 ]] && echo "task_cmd=\`$task_cmd\`"
    exec_pool_task "$task_cmd" "$(get_text "$MC0004" "$mc_server")"
}

remove_mc() {
    print_mc_servers || return 1 
    print_message "$MC0003" "" "" mc_server
    test_server=$(echo "$POOL_SERVER_LIST" | grep -w "memcached" | grep -cw "$mc_server")
    if [[ $test_server -eq 0 ]]; then
         print_message "$MC0200" "$(get_text "$MC0206" "$mc_server")" "" any_key
         return 1
    fi

    task_cmd="$bx_mc_script -a remove -s $mc_server"
    [[ $DEBUG -gt 0 ]] && echo "task_cmd=\`$task_cmd\`"
    exec_pool_task "$task_cmd" "$(get_text "$MC0005" "$mc_server")"
}
