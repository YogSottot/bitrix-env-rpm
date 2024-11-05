#!/usr/bin/bash
#
# enable backup for site
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

delete_backup() {
    backup_kernel="${1}"

    bx_backup_disable=$($bx_sites_script -a backup -d "$backup_kernel" --disable)
    if [[ $(echo "$bx_backup_disable" | grep -cw 'error') -gt 0 ]]; then
        message=$(echo "$bx_backup_disable" | grep -w 'message')
        print_color_text "$message" red
        print_message "$CS0101" "$SM0051 $message" "" any_key
    else
        print_message "$CS0101" "$(get_text "$SM0052" "$backup_kernel")" "" any_key
    fi
}

update_backup() {
    backup_kernel=$1

    print_color_text "$(get_text "$SM0053" "$backup_kernel")"
    echo "$SM0054"

    print_message "$SM0205" "" "" backup_period 1
    case $backup_period in
    "0")
        # once a day
        _min=10
        _hour=24
        _day='*'
        _month='*'
        _wday='*'
        until [[ ( $_hour -ge 0 ) && ( $_hour -le 23 ) ]]; do
            print_message "$SM0055" "" "" _hour $_hour
            if [[ ( $_hour -ge 0 ) && ( $_hour -le 23 ) ]]; then
                echo "$(get_text "$SM0056" "$_hour" "$_min")"
            else
                echo "$SM0057" ;
            fi
        done
    ;;
    "1")
        # once a week (default)
        _min=10
        _hour=23
        _day='*'
        _month='*'
        _wday=0
        # week_day_arr[input]=cron_day
        week_days_arr=(0 1 2 3 4 5 6 0)
        week_days_arr_str=(0 monday tuesday wednesday thursday friday saturday sunday)

        until [[ ( $_wday -gt 0 ) && ( $_wday -le 7 ) ]]; do
            print_message "$SM0058" "" "" _wday $_wday
            if [[ ( $_wday -gt 0 ) && ( $_wday -le 7 ) ]]; then
                echo "$(get_text "$SM0059" "${week_days_arr_str[$_wday]}")"
            else
                echo "$SM0060" ;
            fi
        done
        _wday=${week_days_arr[$_wday]}
    ;;
    "2")
        # once a month
        _min=10
        _hour=23
        _day=32
        _month='*'
        _wday='*'
        until [[ ( $_day -ge 1 ) && ( $_day -le 31 ) ]]; do
            print_message "$SM0061" "" "" _day $_day
            if [[ ( $_day -ge 1 ) && ( $_day -le 31 ) ]]; then
                echo "$(get_text "$SM0062" "$_day")"
            else
                echo "$SM0063" ;
            fi
        done
    ;;
    *)
        print_message "$CS0101" "$SM0064" "" any_key
    ;;
    esac

    [[ "$_hour" == '*' ]] && _hour=any
    [[ "$_day" == '*' ]] && _day=any
    [[ "$_month" == '*' ]] && _month=any
    [[ "$_wday" == '*' ]] && _wday=any

    echo "$SM0065 $backup_kernel"

    [[ $DEBUG -gt 0 ]] && echo "$bx_sites_script -a backup -d $backup_kernel --enable --minute=$_min --hour=$_hour --day=$_day --month=$_month --weekday=$_wday"

    bx_backup_create=$($bx_sites_script -a backup -d $backup_kernel --enable --minute=$_min --hour=$_hour --day=$_day --month=$_month --weekday=$_wday)
  
    if [[ $(echo "$bx_backup_create" | grep -cw 'error') -gt 0 ]]; then
        message=$(echo "$bx_backup_create" | grep -w 'message')
        print_color_text "$message" red
        print_message "$CS0101" "$SM0019 - $message" "" any_key
    else
        print_message "$CS0101" "$SM0066 $backup_kernel" "" any_key
    fi
}

#manage_backup() {
#    site_name=$1
#
#    test_sitename "$site_name" "link" || exit
#
#    # ext_share:dbcp:ext_kernel:finished::/home/bitrix/share:utf-8
#    site_dir=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $6}')
#    [[ $DEBUG -gt 0 ]] && echo "site=$site_name dir=$site_dir"
#
#    get_site_info $site_name $site_dir "backup"
#    [[ $DEBUG -gt 0 ]] && echo "data=$site_info_dat"
#    # backup:ext_share:dbcp:disable:::::::
#    # backup:default:sitemanager:enable:v5:/home/bitrix/backup/archive:10:23:*:*:*
#    backup_status=$(echo "$site_info_dat" | awk -F':' '{print $4}')
#    backup_kernel=$(echo "$site_info_dat" | awk -F':' '{print $3}')
#    [[ $DEBUG -gt 0 ]] && echo "db=$backup_kernel status=$backup_status"
#
#    print_color_text "$(get_text "$SM0067" "${backup_status}d" "$backup_kernel")" blue
#    if [[ "$backup_status" == "enable" ]]; then
#        print_message "$SM0068" "" "" backup_answer 'n'
#        if [[ $(echo "$backup_answer" | grep -wci 'y') -gt 0 ]]; then
#            print_message "$SM0069" "" "" backup_answer_update 'y'
#            if [[ $(echo "$backup_answer_update" | grep -wci 'y') -gt 0 ]]; then
#                update_backup $backup_kernel
#            else
#                print_message "$SM0070" "" "" backup_answer_disable 'n'
#                if [[ $(echo "$backup_answer_disable" | grep -wci 'y') -gt 0 ]]; then
#                    delete_backup $backup_kernel
#                fi
#            fi
#        fi
#    else
#        print_message "$SM0069" "" "" backup_answer_update 'y'
#        if [[ $(echo "$backup_answer_update" | grep -wci 'y') -gt 0 ]]; then
#            update_backup $backup_kernel
#        fi
#    fi
#}

# print host menu
menu_backup() {
    #_menu_backup_00="$SM0201"
    #_menu_backup_01="   $SM0071"

    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do
        menu_logo="$SM0071"
        print_menu_header

        # menu
        print_site_list_point_backup
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t\t$_menu_backup_00"
        else
            menu_list="\n\t\t$_menu_backup_01\n\t\t$_menu_backup_00"
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
            #*) manage_backup "$SITE_MENU_SELECT" ;;
        esac
        
        SITE_MENU_SELECT=
    done
}

menu_backup
