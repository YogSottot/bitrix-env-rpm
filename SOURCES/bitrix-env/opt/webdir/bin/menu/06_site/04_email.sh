#!/usr/bin/bash
#
# manage email settings for site
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

update_email() {
    site_name=$1

    site_email_serv=127.0.0.1
    site_email_port=25
    site_email_exec="$bx_sites_script -a email -s $site_name"
    print_message "$SM0022" "" "" site_email_from
    print_message "$SM0023 ($site_email_serv): " "" "" site_email_serv $site_email_serv
    print_message "$SM0024 ($site_email_port): " "" "" site_email_port $site_email_port

    site_email_exec=$site_email_exec" --smtphost=$site_email_serv"
    site_email_exec=$site_email_exec" --smtpport=$site_email_port"
    site_email_exec=$site_email_exec" --email=$site_email_from"
    print_message "$(get_text "$SM0025" "$site_email_serv" "$site_email_port")" "" "" site_email_auth 'n'
    if [[ $(echo "$site_email_auth" | grep -wci 'y') -gt 0 ]]; then
        print_message "$SM0026 ($site_email_from): " "" "" site_email_user $site_email_from
        print_message "$SM0027 " "" "-s" site_email_pass
        site_email_exec=$site_email_exec" --smtpuser=$site_email_user"

        # file transfer
        smtppassword_file=$(mktemp $CACHE_DIR/.smtpXXXXXXXX)
        echo "$site_email_pass" > $smtppassword_file
        site_email_exec=$site_email_exec" --password_file=$smtppassword_file"

        # user can choose auth method
        supported_methods="plain,scram-sha-1,cram-md5,gssapi,external,digest-md5,login,ntlm"
        print_message "$SM0028" "$SM0029 $supported_methods" "" site_auth_method "auto"
        site_auth_method=$(echo "$site_auth_method" | awk '{print tolower($0)}')

        if [[ $(echo $supported_methods | grep -wc "$site_auth_method") -gt 0 ]]; then
            site_email_exec=$site_email_exec" --smtpauth=$site_auth_method"
        elif [[ $(echo "$site_auth_method" | grep -c '^\(auto\|on\)$') -eq 0 ]]; then
            print_message "$CS0101" "$(get_text "$SM0030" "$site_auth_method")" "" any_key
            return 1
        fi
    fi

    print_message "$(get_text "$SM0031" "$site_email_serv" "$site_email_port")" "" "" site_email_tls_opt 'y'
    if [[ $( echo $site_email_tls_opt | grep -wci "y" ) -gt 0 ]]; then
        site_email_exec=$site_email_exec" --smtptls"
    fi
    [[ $DEBUG -gt 0 ]] &&  echo "$site_email_exec"
    eval $site_email_exec 1>/dev/null
    if [[ $? -gt 0 ]]; then
        print_message "$CS0101" "$SM0019" "" any_key
    else
        print_message "$CS0101" "$(get_text "$SM0032" "$site_name")" "" any_key
    fi
}

manage_email() {
    site_name="${1}"

    test_sitename "$site_name" || exit
    site_dir=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $6}')
    [[ $DEBUG -gt 0 ]] && echo "site=$site_name dir=$site_dir"

    get_site_info $site_name $site_dir "email"
    [[ $DEBUG -gt 0 ]] && echo "data=$site_info_dat"
    # email:cp.ksh.bx:dbcp:cp.ksh.bx:bob@example.org:192.168.0.25:26:bob@example.org:*************:on
    site_email_status=$(echo "$site_info_dat" | awk -F':' '{print $5}')
    site_email_human_status="$(get_text "$SM0036" "$site_name")"
    [[ -n "$site_email_status" ]] && site_email_human_status="$(get_text "$SM0035" "$site_name")"

    print_color_text "$site_email_human_status" blue
    if [[ -n  "$site_email_status" ]]; then
        printf "%-20s: %s\n" "$SM0037" $(echo "$site_info_dat" | awk -F':' '{print $5}')
        printf "%-20s: %s\n" "$SM0038" $(echo "$site_info_dat" | awk -F':' '{print $6}')
        printf "%-20s: %s\n" "$SM0039" $(echo "$site_info_dat" | awk -F':' '{print $7}')
        printf "%-20s: %s\n" "$SM0040" $(echo "$site_info_dat" | awk -F':' '{print $8}')
        printf "%-20s: %s\n" "$SM0041" $(echo "$site_info_dat" | awk -F':' '{print $10}')
        print_message "$(get_text "$SM0042" "$site_name")" "" "" _update_email_answ 'n'
        if [[ $(echo "$_update_email_answ" | grep -wci 'y') -gt 0 ]]; then
            update_email "$site_name"
        else
            print_message "$CS0101" "" "" any_key
            exit
        fi
    else
        update_email "$site_name"
    fi
}

# print host menu
menu_email() {
    _menu_email_00="$SM0201"
    _menu_email_01="$SM0043"

    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do
        menu_logo="$SM0043"
        print_menu_header

        # menu
        print_site_list_point_email
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="$_menu_email_00"
        else
            menu_list="$_menu_email_01\n\t\t $_menu_email_00"
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
            *) manage_email "$SITE_MENU_SELECT" ;;
        esac

        SITE_MENU_SELECT=
    done
}

menu_email
