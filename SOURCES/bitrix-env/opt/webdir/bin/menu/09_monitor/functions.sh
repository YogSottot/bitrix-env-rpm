#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_monitor_script=$BIN_DIR/bx-monitor
monitor_menu=$BIN_DIR/menu/09_monitor

# get_text variables
[[ -f $monitor_menu/functions.txt     ]] && \
    . $monitor_menu/functions.txt


# monitoring status
# fill out
# POOL_MONITOR_STATUS
# POOL_MONITOR_SERVER
get_monitor_status() {

    local _monitor_inf=$($bx_monitor_script)
    local _monitor_err=$(echo "$_monitor_inf" | grep '^error:' | sed -e "s/^error://")
    local _monitor_msg=$(echo "$_monitor_inf" | grep '^message:' | sed -e "s/^message://")

    if [[ -n "$_monitor_err" ]]; then
        print_message "$MON0001 $MON0200" \
            "$_monitor_msg" "" any_key
        return 2
    fi

    # info:monitor:h01w:disable
    POOL_MONITOR_SERVER=$(echo "$_monitor_inf" | grep ':monitor:' | awk -F':' '{print $3}')
    POOL_MONITOR_STATUS=$(echo "$_monitor_inf" | grep ':monitor:' | awk -F':' '{print $4}')
}

# output info about current monitoing status
print_monitor_status() {
    [[ -z "$POOL_MONITOR_SERVER" ]] && get_monitor_status

    print_color_text "$MON0002 $POOL_MONITOR_STATUS"
    if [[ "$POOL_MONITOR_STATUS" == "enable" ]]; then
        echo "$MON0003 $POOL_MONITOR_SERVER"
        echo "$MON0004 http://$POOL_MONITOR_SERVER/nagios"
        echo "$MON0005 http://$POOL_MONITOR_SERVER/munin"
    fi
    echo

    if [[ $POOL_MONITOR_STATUS == "disable" ]]; then
        return 1
    else
        return 0
    fi
}

# return 
# 0 - user configured variables
# 1 - user didn't set variables
# 2 - error
get_monitoring_auth_options() {
    NAGIOS_USER=nagiosadmin
    NAGIOS_PASSWORD=
    MUNIN_USER=admin
    MUNIN_PASSWORD=
    local monitoring_host=$(hostname)

    print_color_text "$MON0006"
    echo "$MON0007 http://$monitoring_host/munin/"
    echo "$MON0008 http://$monitoring_host/nagios/"

    print_message "$MON0009" "" "" change "y"
    if [[ $(echo "$change" | grep -iwc "n" ) -gt 0 ]]; then
        return 1
    fi

    print_message "$(get_text "$MON0010" "$NAGIOS_USER")" \
        "" ""  NAGIOS_USER "$NAGIOS_USER"
    ask_password_info "$NAGIOS_USER" NAGIOS_PASSWORD
    [[ $? -gt 0 ]] && return 2

    print_message "$(get_text "$MON0011" "$MUNIN_USER")" \
        "" "" MUNIN_USER "$MUNIN_USER"
    ask_password_info "$MUNIN_USER" MUNIN_PASSWORD
    [[ $? -gt 0 ]] && return 2

    return 0
}

# return 
# 0 - user configured variables
# 1 - user didn't set variables
# 2 - error
get_email_options() {
    EMAIL=
    EMAIL_SERVER=
    EMAIL_PORT=
    EMAIL_TLS=
    EMAIL_METHOD=
    EMAIL_LOGIN=
    EMAIL_PASSWORD=
    EMAIL_NAGIOS=0

    local all_options_is_good=0
    local limit_try=3

    print_color_text "$MON0012"
    print_message "$MON0013" \
        "" "" change1 "y"
    if [[ $(echo "$change1" | grep -iwc "n" ) -gt 0  ]]; then
        return 1
    fi

    while [[ $all_options_is_good -eq 0 ]]; do
        # limit number tries
        limit_try=$(( $limit_try - 1 ))
        if [[ $limit_try -eq 0 ]]; then
            print_message "$MON0200" \
                "$MON0014" "" any_key
            return 2
        fi
        
        # get the necessary values
        [[ $DEBUG -eq 0 ]] && clear
        print_color_text "$MON0015"

        # get email 
        print_message "$MON0016" \
            "" "" EMAIL
        if [[ -z $EMAIL ]]; then
            print_message "$MON0210" \
                "$MON0017" "" any_key
            continue
        fi
        
        # value with default values
        print_message "$MON0018" \
            "" "" EMAIL_SERVER 127.0.0.1
        print_message "$MON0019" \
            "" "" EMAIL_PORT 25

        # SMTP Auth
        print_message \
            "$(get_text "$MON0020" "$EMAIL_SERVER:$EMAIL_PORT")" \
            "" "" email_auth 'n'
        if [[ $(echo "$email_auth" | grep -iwc 'y') -gt 0 ]]; then
            print_message "$(get_text "$MON0021" "$EMAIL")" \
                "" "" EMAIL_LOGIN $EMAIL
            print_message "$MON0022" "" "-s" EMAIL_PASSWORD

            # get smtp method
            supported_methods="plain,scram-sha-1,cram-md5,gssapi,external,digest-md5,login,ntlm"
            print_message "$MON0023" \
                "$MON0024 $supported_methods" \
                "" EMAIL_METHOD auto
            EMAIL_METHOD=$(echo "$EMAIL_METHOD" | awk '{print tolower($0)}')

            if [[ $(echo $supported_methods | grep -wc "$EMAIL_METHOD") -gt 0  ]]; then
                print_message "$MON0200" \
                    "$(get_text "$MON0025" "$EMAIL_METHOD")" "" any_key
                continue
            fi
        fi

        # TLS options
        print_message "$MON0026" \
            "" "" EMAIL_TLS 'y'
        all_options_is_good=1
    done 
    return 0
}
