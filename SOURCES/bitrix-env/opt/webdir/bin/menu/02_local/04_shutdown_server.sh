PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

TYPE="${1:-reboot}"


sub_menu(){
    menu_logo="${TYPE^} server"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $menu_logo
        echo

        print_message "$(get_text "$CH025" "$TYPE")" "" "" answer n
        [[ $(echo "$answer" | grep -wci "y") -gt 0 ]] || exit

        case "$TYPE" in
            "reboot") shutdown -r now "$menu_logo" ;;
            "halt") shutdown -h now "$menu_logo" ;;
        esac
        print_message "$CH100" "" "" any_key
    done
}

sub_menu

