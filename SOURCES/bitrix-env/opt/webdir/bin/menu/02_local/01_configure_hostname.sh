#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

configure_hostname() {
    new_hostname="${1}"

    # test current hostname
    DEFAULT_NOTE="(N|y)"
    DEFAULT_ANSW="n"
    test_hostname $CURRENT_HOSTNAME 0 0
    if [[ $? -gt 0 ]]; then
        DEFAULT_NOTE="(Y|n)"
        DEFAULT_ANSW="y"
    fi
    print_message "$CH008 $DEFAULT_NOTE: " "" "" answer $DEFAULT_ANSW
    if [[ $(echo "$answer" | grep -wci 'y' ) -eq 0 ]]; then
        return 0
    fi

    # test if pool exist
    get_client_settings
    if [[ $IN_POOL -gt 0 ]]; then
        # change via ansible
        configure_hostname_pool $new_hostname $CURRENT_HOSTNAME
    else
        configure_hostname_local $new_hostname
    fi
}

sub_menu() {
    menu_00="$CH000"
    menu_01="$(get_text "$CH001" "$CURRENT_HOSTNAME")"

    menu_logo="$(get_text "$CH001" "$CURRENT_HOSTNAME")"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $menu_logo
        echo

        get_local_network $LINK_STATUS
        menu_list="$menu_01\n\t\t $menu_00"

        print_menu
        print_message "$CH002" '' '' MENU_SELECT

        case "$MENU_SELECT" in
            0) exit ;;
            *) configure_hostname "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
