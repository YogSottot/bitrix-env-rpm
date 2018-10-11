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
    print_color_text "$MON0029"

    print_message "$MON0030" "" "" change "n"
    if [[ $(echo "$change" | grep -iwc "n" ) -gt 0 ]]; then
        return 1
    fi 

    monitor_options=Y

    local monitor_cmd="$bx_monitor_script -a disable"
    exec_pool_task "$monitor_cmd" "$MON0031"

}

main
