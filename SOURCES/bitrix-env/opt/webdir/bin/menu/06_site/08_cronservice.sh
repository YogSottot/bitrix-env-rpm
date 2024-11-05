#!/usr/bin/bash
#
# enable backup for site
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

#manage_cronservice() {
#    site_name=$1
#
#    test_sitename "$site_name" "link" || exit
#    service_site_exe=
#
#    # ext_share:dbcp:ext_kernel:finished::/home/bitrix/share:utf-8
#    site_dir=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $6}')
#
#    get_site_info $site_name $site_dir "cron_services"
#    [[ $DEBUG -gt 0 ]] && echo "data=$site_info_dat"
#    # data=cron_services:default:sitemanager:enabled:smtpd
#    service_status=$(echo "$site_info_dat" | awk -F':' '{print $4}')
#    [[ $DEBUG -gt 0 ]] && echo "dir=$site_dir status=$backup_status"
#
#    service_xmppd=disabled
#    [[ $(echo "$site_info_dat" | awk -F':' '{print $5}' | grep -wc "xmppd") -gt 0 ]] && service_xmppd=enabled
#
#    service_smtpd=disabled
#    [[ $(echo "$site_info_dat" | awk -F':' '{print $5}' | grep -wc "smtpd") -gt 0 ]] && service_smtpd=enabled
#
#    print_message "$SM0105" "" "" service_name
#    if [[ $(echo "$service_name" | grep -ic '^\(smtpd\|xmppd\)$') -eq 0 ]]; then
#        print_message "$CS0101" "$SM0106" "" any_key
#    else
#
#        service_name=$(echo "$service_name" | awk '{print tolower($0)}')
#        service_status=disabled
#        [[ "$service_name" == "smtpd" ]] && service_status=$service_smtpd
#        [[ "$service_name" == "xmppd" ]] && service_status=$service_xmppd
#
#        if [[ "$service_status" == "enabled" ]]; then
#            print_message "$(get_text "$SM0107" "$service_name" "$site_name")" "" "" site_answer 'n'
#            if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
#                service_site_exe="$bx_sites_script -a service -s $site_name -r $site_dir  --disable --service=$service_name"
#                service_new=disabled
#            fi
#        else
#            print_message "$(get_text "$SM0108" "$service_name" "$site_name")" "" "" site_answer 'y'
#            if [[ $(echo "$site_answer" | grep -icw 'y') -gt 0 ]]; then
#                service_site_exe="$bx_sites_script -a service -s $site_name -r $site_dir  --enable --service=$service_name"
#                service_new=enabled
#            fi
#        fi
#    fi
#
#    if [[ -n "$service_site_exe" ]]; then
#        cron_site_inf=$(eval $service_site_exe)
#        cron_site_err=$(echo "$cron_site_inf" | grep "^error" | sed -e 's/^error://')
#        cron_site_msg=$(echo "$cron_site_inf" | grep "^message" | sed -e 's/^message://')
#        if [[ -n "$cron_site_err" ]]; then
#            print_message "$CS0101" "$SM0019 - $cron_site_msg" "" any_key
#        else
#            print_message "$CS0101" "Cron $service_name is $service_new for $site_name" "" any_key
#        fi
#    fi
#}

# print host menu
menu_cronservice() {
    _menu_cronservice_00="$SM0201"
    _menu_cronservice_01="   $SM0109"

    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do
        menu_logo="$SM0109"
        print_menu_header

        # menu
        print_site_list_point_cronservices
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t\t$_menu_cronservice_00"
        else
            menu_list="\n\t\t$_menu_cronservice_01\n\t\t$_menu_cronservice_00"
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
            #*) manage_cronservice "$SITE_MENU_SELECT" ;;
        esac
    
        SITE_MENU_SELECT=
    done
}

menu_cronservice
