#!/usr/bin/bash
#
# manage nginx composite settings
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

proxy_ignore_client_abort() {
    print_message "$SM0208" "" "" site_name "default"
    test_sitename $site_name || exit

    site_dir=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $6}')
    [[ $DEBUG -gt 0  ]] && echo "site=$site_name dir=$site_dir"

    get_site_info $site_name $site_dir "configs"
    # proxy_ignore_client_abort
    proxy_ignore_client_abort=$(echo "$site_info_dat" | awk -F':' '{print $11}')
    [[ $DEBUG -gt 0 ]] && echo "proxy_ignore_client_abort=$proxy_ignore_client_abort"

    if [[ $proxy_ignore_client_abort == "off" ]]; then
        print_message "$(get_text "$SM0115" "$site_name")" "" "" site_answer 'n'
        [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]] && task_exec="$bx_sites_script -a proxy_ignore_client_abort -s $site_name --enable"
        task_desc="$SM0116"
    else
        print_message "$(get_text "$SM0117" "$site_name")" "" "" site_answer 'y'
        [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]] && task_exec="$bx_sites_script -a proxy_ignore_client_abort -s $site_name --disable"
        task_desc="$SM0118"
    fi
    [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"

    if [[ -n "$task_exec" ]]; then
        #exec_pool_task "$task_exec" "$task_desc"
    fi
}

enable_custom_settings() {
    task_exec=
    task_desc=

    print_message "$(get_text "$SM0148" "$site_name")" "" "" site_answer 'y'

    [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]] && task_exec="$bx_sites_script -a nginx_custom_site_settings --enable" && task_desc="$SM0150"

    if [[ $DEBUG -gt 0 ]]; then
        echo "$task_exec"
    fi

    if [[ -n "$task_exec" ]]; then
        #exec_pool_task "$task_exec" "$task_desc"
    fi
}

enable_bx_temp_files_dir() {
    task_exec=
    task_desc=

    print_message "$(get_text "$SM0149" "$site_name")" "" "" site_answer 'y'
    [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]] && task_exec="$bx_sites_script -a dbconn_temp_files --enable" && task_desc="$SM0151"

    if [[ $DEBUG -gt 0 ]]; then
        echo "$task_exec"
    fi

    if [[ -n "$task_exec" ]]; then
        #exec_pool_task "$task_exec" "$task_desc"
    fi
}

sub_menu() {
    menu_00="$SM0201"
    menu_01="$SM0120"
    menu_02="$SM0142"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$SM0119"
        print_menu_header

        # print all
        print_site_list_point_options

        # task info
        get_task_by_type '(site|mysql|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(site|mysql|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ $POOL_SUBMENU_TASK_LOCK -eq 1 ]]; then
            menu_list="\n$menu_00"
        else
            menu_list="\n$menu_01\n$menu_02\n$menu_00"
        fi

        print_menu

        if [[ ( $POOL_SUBMENU_TASK_LOCK -gt 0 ) || ( $print_web_servers_status_rtn -gt 0 ) ]]; then
            print_message "$SM0202" '' '' MENU_SELECT 0
        else
            print_message "$SM0205" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            #1) proxy_ignore_client_abort;;
            #2) enable_bx_temp_files_dir ;;
            *) error_pick ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
