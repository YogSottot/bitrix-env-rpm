#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

configure_tz() {
    local tz_file=/tmp/tzdata
    local tz_name=
    # get from user info about timezone string and saved it to user_tz_file
    tzselect > $tz_file
    if [[ $? -gt 0 ]]; then
        print_message "$HM0200" "$HM0061" "" any_key
        exit 1
    fi
    local tz_name=$(cat $tz_file)
    # Please confirm the installation timezone
    php_choice=0
    print_message "$(get_text "$HM0062" "$tz_name")" "" "" php y
    [[ $(echo "$php" | grep -iwc 'y') -gt 0 ]] && php_choice=1

    # Notification
    print_color_text "$HM0063" red
    echo " /etc/sysconfig/clock"
    echo " /etc/localtime"
    [[ $php_choice -eq 1 ]] && echo " /etc/php.d/bitrixenv.ini"
    print_color_text "$HM0064" red
    echo " mysqld"
    echo " postgresql"
    echo " crond"
    echo " rsyslog"
    [[ $php_choice -eq 1 ]] && echo " httpd"
    print_message "$HM0065" "" "" confirm 'n'

    [[ $(echo "$confirm" | grep -iwc 'n') -gt 0 ]] && return 1
    local tz_task="$ansible_wrapper -a timezone --timezone $tz_name"
    [[ $php_choice -eq 1 ]] && tz_task=$tz_task" --php"
    [[ $DEBUG -gt 0 ]] && echo "cmd=$tz_task"
    exec_pool_task "$tz_task" "setting timezone=$tz_name"
}

menu_configure_tz() {
    local host_logo="$HM0066"
    local menu_00="$HM0042"
    local menu_01="1. $HM0066"

    HOST_MENU_SELECT=
    until [[ -n "$HOST_MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $host_logo
        echo

        print_pool_info

        menu_list="$menu_01\n\t\t $menu_00"
        print_menu

        print_message "$HM0204" '' '' HOST_MENU_SELECT
        # process selection
        case "$HOST_MENU_SELECT" in
            "0") exit ;;
            *) configure_tz ;;
        esac
        HOST_MENU_SELECT=
    done
}

menu_configure_tz
