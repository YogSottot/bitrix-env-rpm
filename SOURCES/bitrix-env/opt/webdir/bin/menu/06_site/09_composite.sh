#!/usr/bin/bash
#
# manage nginx composite settings
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

manage_composite() {
    site_name=$1

    test_sitename $site_name || exit

    service_site_exe=
    service_site_status=

    #default:sitemanager:kernel:finished:srv01.ksh.bx:/home/bitrix/www:utf-8:Y:N:N:N:
    site_composite=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $10}')
    site_nginx=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $11}')
    [[ $DEBUG -gt 0 ]] && echo "site_name=$site_name composite=$site_composite nginx_settings=$site_nginx"

    if [[ "$site_composite" == "N" ]]; then
        print_message "$CS0100" "$(get_text "$SM0110" "$site_name")" "" any_key
    else
        # composite settings found in the nginx config:
        # 1. update settings
        # 2. delete settings
        if [[ "$site_nginx" == "Y" ]]; then
            # 1
            print_message "$(get_text "$SM0111" "$site_name")" "" "" site_answer 'y'
            if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
                service_site_status="update"
                service_site_exe="$bx_sites_script -a composite -s $site_name --enable"
            # 2
            else
                print_message "$(get_text "$SM0112" "$site_name")" "" "" site_answer 'n'
                if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
                    service_site_status="remove"
                    service_site_exe="$bx_sites_script -a composite -s $site_name --disable"
                fi
            fi
            # composite settings not found in the nginx config
            # 1. create settings
        else
            service_site_status="create"
            service_site_exe="$bx_sites_script -a composite -s $site_name --enable"
        fi

        [[ $DEBUG -gt 0 ]] && echo "$service_site_exe"
        if [[ -n "$service_site_exe" ]]; then
            exec_pool_task "$service_site_exe" "$(get_text "$SM0113" "$service_site_status")"
        else
            print_message "$CS0101" "" "" any_key
        fi

        get_task_by_type "site" POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
    fi
}

# print host menu
menu_composite() {
    _menu_cronservice_00="$SM0201"
    _menu_cronservice_01="$SM0114"

    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do
        menu_logo="$SM0114"
        print_menu_header

        # menu
        print_site_list_point_composite
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="$_menu_cronservice_00"
        else
            menu_list="$_menu_cronservice_01\n\t\t $_menu_cronservice_00"
        fi
        print_menu

        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            print_message "$SM0202" '' '' SITE_MENU_SELECT 0
        else
            print_message "$SM0207" '' '' SITE_MENU_SELECT "default"
        fi

        # process selection
        case "$SITE_MENU_SELECT" in
            "0") exit ;;
            *) manage_composite "$SITE_MENU_SELECT" ;;
        esac

        SITE_MENU_SELECT=
    done
}

menu_composite
