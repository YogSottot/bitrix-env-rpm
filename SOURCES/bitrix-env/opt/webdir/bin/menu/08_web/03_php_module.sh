#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

get_php_exts() {
    php_modules=$(php -m 2>/dev/null)
    IS_SSH2=$(echo "$php_modules" | grep ssh2 -cwi)
    IS_CURL=$(echo "$php_modules" | grep curl -cwi)
    IS_ZIP=$(echo "$php_modules" | grep zip -cwi)
    IS_DOM=$(echo "$php_modules" | grep dom -cwi)
    IS_PHAR=$(echo "$php_modules" | grep phar -cwi)
    IS_XDEBUG=$(echo "$php_modules" | grep xdebug -cwi)
    IS_IMAGICK=$(echo "$php_modules" | grep imagick -cwi)
    IS_XHPROF=$(echo "$php_modules" | grep xhprof -cwi)
}

manage_extension() {
    ext_status="${1:-0}" # 1 - disable, 0 -enable
    ext_name="${2:-ssh2}"
    [[ $DEBUG -gt 0 ]] && echo "ssh2_status=$ssh2_status"

    if [[ $ext_status -eq 0 ]]; then
        task_desc="$(get_text "$WEB0034" "$ext_name")"
        task_exec="$bx_web_script -a extension_enable --extension $ext_name"
    else
        task_desc="$(get_text "$WEB0035" "$ext_name")"
        task_exec="$bx_web_script -a extension_disable --extension $ext_name"
    fi

    [[ $DEBUG -gt 0  ]] && echo "task_exec=$task_exec"
    exec_pool_task "$task_exec" "$task_desc"
}

menu_constructor() {
    switch="${1}"
    var_a="${2}"
    var_b="${3}"

    if [[ $switch -gt 0 ]]; then
        menu_ch=$var_b
    else
        menu_ch=$var_a
    fi

    if [[ -z $menu_01 ]]; then
        menu_01="$menu_ch"
    else
        menu_01="$menu_01\n\t\t $menu_ch"
    fi
}

sub_menu() {
    menu_00="$WEB0201"
    menu_01_enable="1. $(get_text "$WEB0034" ssh2)"
    menu_01_disable="1. $(get_text "$WEB0035" ssh2)"

    menu_02_enable="2. $(get_text "$WEB0034" curl)"
    menu_02_disable="2. $(get_text "$WEB0035" curl)"

    menu_03_enable="3. $(get_text "$WEB0034" zip)"
    menu_03_disable="3. $(get_text "$WEB0035" zip)"

    menu_04_enable="4. $(get_text "$WEB0034" dom)"
    menu_04_disable="4. $(get_text "$WEB0035" dom)"

    menu_05_enable="5. $(get_text "$WEB0034" phar)"
    menu_05_disable="5. $(get_text "$WEB0035" phar)"

    menu_06_enable="6. $(get_text "$WEB0034" xdebug)"
    menu_06_disable="6. $(get_text "$WEB0035" xdebug)"

    menu_07_enable="7. $(get_text "$WEB0034" imagick)"
    menu_07_disable="7. $(get_text "$WEB0035" imagick)"

    menu_08_enable="8. $(get_text "$WEB0034" xhprof)"
    menu_08_disable="8. $(get_text "$WEB0035" xhprof)"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$WEB0036"
        menu_01=
        menu_list=
        print_menu_header

        # print all
        print_web_servers_status "" "1"
        print_web_servers_status_rtn=$?

        # modules
        get_php_exts

        menu_constructor $IS_SSH2 "$menu_01_enable" "$menu_01_disable"
        menu_constructor $IS_CURL "$menu_02_enable" "$menu_02_disable"
        menu_constructor $IS_ZIP  "$menu_03_enable" "$menu_03_disable"
        menu_constructor $IS_DOM  "$menu_04_enable" "$menu_04_disable"
        menu_constructor $IS_PHAR "$menu_05_enable" "$menu_05_disable"
        menu_constructor $IS_XDEBUG "$menu_06_enable" "$menu_06_disable"
        menu_constructor $IS_IMAGICK "$menu_07_enable" "$menu_07_disable"
        menu_constructor $IS_XHPROF "$menu_08_enable" "$menu_08_disable"

        # task info
        get_task_by_type '(mysql|site)' POOL_TASK_LOCK POOL_TASK_INFO
        print_task_by_type '(mysql|site)' "$POOL_TASK_LOCK" "$POOL_TASK_INFO"

        # background task or not found free servers in the pool
        if [[ ( $POOL_TASK_LOCK -eq 1 ) || ( $print_web_servers_status_rtn -gt 0 ) ]]; then
            menu_list="$menu_00"
        else
            menu_list="$menu_01\n\t\t $menu_00"
        fi

        print_menu

        if [[ $POOL_TASK_LOCK -gt 0 ]]; then
            print_message "$WEB0202" '' '' MENU_SELECT 0
        else
            print_message "$WEB0205" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            1) manage_extension $IS_SSH2 ssh2 ;;
            2) manage_extension $IS_CURL curl ;;
            3) manage_extension $IS_ZIP zip ;;
            4) manage_extension $IS_DOM dom ;;
            5) manage_extension $IS_PHAR phar ;;
            6) manage_extension $IS_XDEBUG xdebug ;;
            7) manage_extension $IS_IMAGICK imagick ;;
            8) manage_extension $IS_XHPROF xhprof ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
