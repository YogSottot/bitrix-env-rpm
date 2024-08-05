#!/usr/bin/bash
#
# manage crontab record for site: only kernel involved
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

manage_crontab() {
    site_dir=$1

    test_directory "$site_dir" || exit

    [[ $DEBUG -gt 0 ]] && echo "$POOL_SITES_KERNEL_LIST"
    [[ $DEBUG -gt 0 ]] && echo "$POOL_SITES_LINK_LIST"

    # try found site in menu
    is_kernel_site=$(echo "$POOL_SITES_KERNEL_LIST" | grep -c ":$site_dir:")
    if [[ $is_kernel_site -eq 0 ]]; then
        site_name="ext_"$(basedir $site_dir)
    else
        site_name=$(echo "$POOL_SITES_KERNEL_LIST" | grep ":$site_dir:" | awk -F':' '{print $1}')
    fi

    get_site_info $site_name $site_dir "cron"
    [[ $DEBUG -gt 0 ]] && echo "$site_info_dat"

    site_cron_status=$(echo "$site_info_dat" | awk -F':' '{print $4}')
    if [[ "$site_cron_status" == "enable" ]]; then
        print_message "$SM0017" "$SM0008: $site_dir" "" site_answer 'n'
        if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
            cron_site_exe="$bx_sites_script -a cron -s $site_name -r $site_dir --disable"
        fi
    else
        print_message "$SM0018" "$SM0008: $site_dir" "" site_answer 'y'
        if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
            cron_site_exe="$bx_sites_script -a cron -s $site_name -r $site_dir --enable"
        fi
    fi

    if [[ -n "$cron_site_exe" ]]; then
        [[ $DEBUG -gt 0 ]] && echo "$cron_site_exe"
        cron_site_inf=$(eval $cron_site_exe)
        cron_site_err=$(echo "$cron_site_inf" | grep "^error" | sed -e 's/^error://')
        cron_site_msg=$(echo "$cron_site_inf" | grep "^message" | sed -e 's/^message://')

        if [[ -n "$cron_site_err" ]]; then
            print_message "$CS0101" "$SM0019 $cron_site_msg" "" any_key
        else
            cron_status=$(echo "$cron_site_inf" | grep '^bxSite:cron:' | sed -e 's/bxSite:cron://' | awk -F':' '{print $3}')
            print_message "$CS0101" "$(get_text "$SM0020" "${cron_status}d") $site_dir" "" any_key
        fi
    fi
}

# print host menu
menu_crontab() {
    _menu_crontab_00="$SM0201"
    _menu_crontab_01="$SM0021"

    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do
        menu_logo="$SM0021"
        print_menu_header

        # menu
        print_site_list_point_cron
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="$_menu_crontab_00"
        else
            menu_list="$_menu_crontab_01\n\t\t $_menu_crontab_00"
        fi
        print_menu

        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            print_message "$SM0202" '' '' SITE_MENU_SELECT 0
        else
            print_message "$SM0206" "" "" SITE_MENU_SELECT "/home/bitrix/www"
        fi

        # process selection
        case "$SITE_MENU_SELECT" in
            "0") exit ;;
            *) manage_crontab "$SITE_MENU_SELECT" ;;
        esac

        SITE_MENU_SELECT=
    done
}

menu_crontab
