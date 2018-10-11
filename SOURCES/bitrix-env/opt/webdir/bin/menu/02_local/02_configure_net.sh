PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

TYPE="${1:-manual}"


sub_menu(){
    menu_00="$CH000"
    menu_01=" $CH009"

    menu_logo="$CH009"
    [[ $TYPE == "manual" ]] && \
        menu_logo="$CH0091" && \
        menu_01=" $CH0091"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $menu_logo
        echo

        get_local_network $LINK_STATUS
        menu_list="\n$menu_01\n$menu_00"

        print_menu
        print_message "$CH010" '' '' MENU_SELECT

        case "$MENU_SELECT" in
            0) exit ;;
            *) configure_network "$TYPE" "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu

