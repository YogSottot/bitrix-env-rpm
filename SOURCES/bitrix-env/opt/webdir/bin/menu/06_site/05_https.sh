#!/usr/bin/bash
#
# enable or disable access via http
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

manage_https() {
    site_name=$1

    test_sitename "$site_name" || exit

    site_dir=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $6}')
    [[ $DEBUG -gt 0 ]] && echo "site=$site_name dir=$site_dir"

    get_site_info $site_name $site_dir "https"
    [[ $DEBUG -gt 0 ]] && echo "data=$site_info_dat"
    # https:cp.ksh.bx:dbcp:disable:/etc/nginx/ssl/cert.pem:/etc/nginx/ssl/cert.pem:/etc/nginx/bx/conf/ssl.conf
    https_status=$(echo "$site_info_dat" | awk -F':' '{print $4}')
    https_status_human="$SM0044"
    [[ "$https_status" == "enable" ]] && https_status_human="$SM0044"

    print_color_text "$https_status_human $site_name" blue
    if [[ "$https_status" == "disable" ]]; then
        print_message "$(get_text "$SM0046" "$site_name")" "" "" site_answer "y"
        if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
            site_https_exe="$bx_sites_script -a https -s $site_name --enable"
            site_https_message="$SM0048"
        fi
    fi

    if [[ "$https_status" == "enable" ]]; then
        print_message "$(get_text "$SM0047" "$site_name")" "" "" site_answer "n"
        if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
            site_https_exe="$bx_sites_script -a https -s $site_name --disable"
            site_https_message="$SM0049"
        fi
    fi

    [[ $DEBUG -gt 0 ]] && echo "cmd=$site_https_exe"
    if [[ -n "$site_https_exe" ]]; then
        https_site_inf=$(eval $site_https_exe)
        https_site_err=$(echo "$https_site_inf" | grep "^error" | sed -e 's/^error://')
        https_site_msg=$(echo "$https_site_inf" | grep "^message" | sed -e 's/^message://')

        if [[ -n "$https_site_err" ]]; then
            print_message "$CS0101" "$SM0019 - $https_site_msg" "" any_key
        else
            http_status=$(echo "$https_site_inf" | awk -F':' '/bxSite:https/{print $5}')
            print_message "$CS0101" "$site_https_message" "" any_key
        fi
    fi
}

# print host menu
menu_https() {
    _menu_https_00="$SM0201"
    _menu_https_01="$SM0050"

    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do
        menu_logo="$SM0050"
        print_menu_header

        # menu
        print_site_list_point_https
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="$_menu_https_00"
        else
            menu_list="$_menu_https_01\n\t\t $_menu_https_00"
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
            *) manage_https "$SITE_MENU_SELECT" ;;
        esac

        SITE_MENU_SELECT=
    done
}

menu_https
