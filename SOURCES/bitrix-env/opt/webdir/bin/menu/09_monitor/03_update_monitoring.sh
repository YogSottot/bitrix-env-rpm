#!/bin/bash
# manage sites and site's options
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

main() {
    local monitor_cmd="$bx_monitor_script -a update"
    exec_pool_task "$monitor_cmd" "$MON0032"
}

main
