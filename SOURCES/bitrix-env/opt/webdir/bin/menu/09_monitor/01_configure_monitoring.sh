#!/bin/bash
# manage sites and site's options
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

main() {
    local monitor_options=N
    monitoring_logo="$MON0027"


    clear
    echo -e "\t\t\t" $logo
    echo -e "\t\t\t" $monitoring_logo
    echo

    # print monitoring status
    print_monitor_status
    print_color_text "$MON0028"

    # get auth option for monitoring;
    # NAGIOS_USER, NAGIOS_PASSWORD, MUNIN_USER, MUNIN_PASSWORD
    get_monitoring_auth_options
    get_monitoring_auth_options_rtn=$?
    [[ $get_monitoring_auth_options_rtn -gt 1 ]] && exit 1

    # get email options
    # EMAIL EMAIL_SERVER EMAIL_PORT EMAIL_TLS EMAIL_METHOD EMAIL_LOGIN EMAIL_PASSWORD
    # EMAIL_NAGIOS
    get_email_options
    get_email_options_rtn=$?
    [[ $get_email_options_rtn -gt 1 ]] && exit 1

    if [[ $DEBUG -gt 0 ]]; then
        echo "Configuration options:"
        echo "Nagios user:     $NAGIOS_USER"
        echo "Nagios password: $NAGIOS_PASSWORD"
        echo "Munin user:      $MUNIN_USER"
        echo "Munin password:  $MUNIN_PASSWORD"
        echo 
        echo "EMAIL:           $EMAIL"
        echo "EMAIL Server:    $EMAIL_SERVER:$EMAIL_PORT"
        echo "EMAIL Login:     $EMAIL_LOGIN"
    fi

    local monitor_cmd="$bx_monitor_script -a enable"
    if [[ $get_monitoring_auth_options_rtn -eq 0 ]]; then
        monitor_cmd=$monitor_cmd" --nagios_user=$NAGIOS_USER"
        monitor_cmd=$monitor_cmd" --nagios_password=$(printf "%q" "$NAGIOS_PASSWORD")"
        monitor_cmd=$monitor_cmd" --munin_user=$MUNIN_USER"
        monitor_cmd=$monitor_cmd" --munin_password=$(printf "%q" "$MUNIN_PASSWORD")"
    fi

    if [[ $get_email_options_rtn -eq 0 ]]; then
        monitor_cmd=$monitor_cmd" --notify_nagios"
        monitor_cmd=$monitor_cmd" --monitor_email=$EMAIL"
        monitor_cmd=$monitor_cmd" --smtphost=$EMAIL_SERVER --smtpport=$EMAIL_PORT"

        if [[ -n "$EMAIL_LOGIN" ]]; then
            monitor_cmd=$monitor_cmd" --smtppass=$(printf "%q" "$EMAIL_PASSWORD")"
            monitor_cmd=$monitor_cmd" --smtplogin=$EMAIL_LOGIN"
        fi
        
        [[ $(echo "$EMAIL_TLS" | grep -iwc 'y') -gt 0 ]] && \
            monitor_cmd=$monitor_cmd" --smtptls"
        [[ -n $EMAIL_METHOD ]] && \
            monitor_cmd=$monitor_cmd" --smtpmethod=$EMAIL_METHOD"
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "$monitor_cmd"
    fi
    exec_pool_task "$monitor_cmd" "$MON0027"
}

main
