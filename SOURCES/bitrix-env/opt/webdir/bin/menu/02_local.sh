#!/bin/bash
# manage localhost options
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/02_local/functions.sh || exit 1
logo=$(get_logo)

# get_text variables
[[ -f $PROGPATH/${PROGNAME%.sh}.txt ]] && \
    . $PROGPATH/${PROGNAME%.sh}.txt

configure_hostname() {
    $submenu_dir/01_configure_hostname.sh
}

configure_net() {
    type=${1:-manual}
    $submenu_dir/02_configure_net.sh $type
}

shutdown_server() {
    type=${1:-reboot}
    $submenu_dir/04_shutdown_server.sh $type
}

update_server() {
    $submenu_dir/06_update_server.sh
}

beta_version() {
    $PROGPATH/01_hosts/10_change_repository.sh
}

# print host menu
submenu() {
    submenu_00="$CFGL0000"
    submenu_01="$CFGL0001"
    submenu_02="$CFGL0002"
    submenu_03="$CFGL0003"
    submenu_04="$CFGL0004"
    submenu_05="$CFGL0005"
    submenu_06="$CFGL0006"
    submenu_07="$CFGL0009"

    menu_logo="$CFGL0007"

    SUBMENU_SELECT=
    until [[ -n "$SUBMENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $menu_log
        echo

        get_local_network $LINK_STATUS
        menu_list="\n\t$submenu_01\n\t$submenu_02"
        menu_list="$menu_list\n\t$submenu_03\n\t$submenu_04"
        menu_list="$menu_list\n\t$submenu_05\n\t$submenu_06"
        menu_list="$menu_list\n\t$submenu_07\n\t$submenu_00"

        print_menu
        print_message "$CFGL0008" '' '' SUBMENU_SELECT
       
        case "$SUBMENU_SELECT" in
            "1") configure_hostname  ;;
            "2") configure_net dhcp  ;;
            "3") configure_net manual ;;
            "4") shutdown_server reboot ;;
            "5") shutdown_server halt ;;
            "6") update_server ;;
            "7") beta_version ;;
            "0") exit ;;
            *)   error_pick; SUBMENU_SELECT=;;
        esac

        SUBMENU_SELECT=
done
}

submenu

