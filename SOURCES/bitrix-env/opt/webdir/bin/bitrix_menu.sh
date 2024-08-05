#!/usr/bin/bash
#
export TERM=linux

PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
VERBOSE=0
BASE_DIR=/opt/webdir
LOGS_DIR=$BASE_DIR/logs
TEMP_DIR=$BASE_DIR/temp

. $PROGPATH/bitrix_utils.sh || exit 1

# a_menu="0. Manage current host";
a_pick() {
    $PROGPATH/local_menu.sh || exit 1
}

#  b_menu="1. Manage group of servers"
b_pick() {
    $PROGPATH/pool_menu.sh || exit 1
}

print_menu() {
    # menu options
    a_menu="0. Manage current host";
    b_menu="1. Manage group of servers";

    # print menu
    LOGO=$(get_logo)
    #IP=$(get_ip_addr)

    echo -e "\t\t\t" $LOGO
    echo "Available actions:"
    echo
    echo -e "\t\t" ${a_menu}
    echo -e "\t\t" ${b_menu}
    echo
    echo $notice_message
    echo Type a number and press ENTER
    echo "(Ctrl-C for exit to shell)" ;

    notice_message=""
}

# get user choice and process it
while true; do
    [[ $DEBUG -eq 0 ]] && clear;

    print_menu
    read user_choice
    # processing choice
    case $user_choice in
	0|a) a_pick ;;
	1|b) b_pick ;;
	*) error_pick ;;
    esac
done
