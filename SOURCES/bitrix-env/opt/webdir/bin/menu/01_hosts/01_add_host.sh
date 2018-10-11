#!/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

create_host() {
    local host_addr="$1"

    # test if host_addr is IP
    is_ip_addr=$(echo "$host_addr" | egrep -c '^([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}$')
    # test if hostname contains correct chars
    if [[ $is_ip_addr -eq 0 ]]; then
        test_hostname "$host_addr" 
        [[ $test_hostname -eq 0 ]] && return 1
    fi

    local host_user=root
    local host_pass=            # password for ssh connect
    local host_iden=            # unique identifier for the server

    # test if defined host exist in server list (small check without name resolution)
    [[ -z "$POOL_SERVER_LIST" ]] && cache_pool_info
    is_host_in_pool=$(echo "$POOL_SERVER_LIST" | \
        grep -c "\(^$host_addr:\|:$host_addr:\|=$host_addr\)")
    [[ $DEBUG -gt 0 ]] && echo "$POOL_SERVER_LIST"

    if [[ $is_host_in_pool -gt 0 ]]; then
        print_message "$HM0200" "$(get_text "$HM0032" "$host_addr")" "" any_key
        return 1
    # host not found, try add it
    else
        if [[ $is_ip_addr -eq 0 ]]; then
            print_message "$HM0033 (default: $host_addr): " \
                "" "" host_iden "$host_addr"
        else
            print_message "$HM0033: " \
                "" "" host_iden
        fi
        test_hostname "$host_iden"
        [[ $test_hostname -eq 0 ]] && return 1

        # get user password for ssh
        print_message "$(get_text "$HM0034" "$host_user")" "" "-s" host_pass

        # find out ANSIBLE_SSHKEY_PRIVATE and ANSIBLE_SSHKEY_PUBLIC
        print_color_text "$(get_text "$HM0035" "$host_addr")"
        copy_sshkey "$host_addr" "$host_user" "$host_pass"
        copy_sshkey_rtn=$?
        if [[ $copy_sshkey_rtn -gt 0 ]]; then
            # check the error on the known to us: User must change password
            if [[ $(echo "$ANSIBLE_COPY_MSG" | \
                grep -ci "User must change password") -gt 0 ]]; then
                
                # change user password
                echo "$ANSIBLE_COPY_MSG"
                change_password_viassh "$host_addr" "$host_user" "$host_pass"
                change_password_viassh_rtn=$?
                # try update
                if [[ $change_password_viassh_rtn -gt 0 ]]; then
                    print_message "$HM0200" \
                        "$(get_text "$HM0036" "$ANSIBLE_CHPWD_MSG" "$log_changepwd")" \
                        '' any_key
                    return 1
                # password is updated => try copy again
                else
                    copy_sshkey "$host_addr" "$host_user" "$host_pass"
                    copy_sshkey_rtn=$? 
                    if [[ $copy_sshkey_rtn -gt 0 ]]; then
                        print_message "$HM0200" \
                            "$(get_text "$HM0037" "$ANSIBLE_COPY_MSG" "$log_copy_keys")" \
                            '' any_key
                        return 1
                    fi
                fi
            # unknown error
            else
                print_message "$HM0200" \
                    "$(get_text "$HM0037" "$ANSIBLE_COPY_MSG" "$log_copy_keys")" \
                    '' any_key
                return 1
            fi
        fi
    fi
    print_color_text "$(get_text "$HM0038" "$ANSIBLE_SSHKEY_PUBLIC" "$host_addr")"
      
    # short name and server-id in ansible config
    add_server_to_pool "$host_iden" "$host_addr"
    add_server_to_pool_rtn=$?
    if [[ $add_server_to_pool_rtn -gt 0 ]]; then
        print_message "$HM0200" \
            "$HM0039: $ANSIBLE_ADD_MSG" \
            "" any_key
        return 1
    else
        print_message "$HM0201" \
            "$(get_text "$HM0040" "$host_iden" "$host_addr")" \
            "" any_key
        return 0
    fi
}

# create host in the ansible config and copy ssh key on it
sub_menu() {
    host_logo="$HM0041"
    menu_00="$HM0042"
    menu_01="   $HM0041"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_pool_info
        
        # is there some task which can interrupted by adding new host (iptables and so on)
        get_task_by_type '(common|monitor|mysql)' POOL_HOST_TASK_LOCK POOL_HOST_TASK_LIST
        print_task_by_type '(common|monitor|mysql)' "$POOL_HOST_TASK_LOCK" "$POOL_HOST_TASK_LIST"

        if [[ $POOL_HOST_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_00"
        else
            menu_list="\n\t$menu_00\n\t$menu_01"
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
            *) create_host "$HOST_MENU_SELECT" ;;
        esac

        [[ $? -eq 0 ]] && POOL_SERVER_LIST=
        HOST_MENU_SELECT=
    done
}

sub_menu

