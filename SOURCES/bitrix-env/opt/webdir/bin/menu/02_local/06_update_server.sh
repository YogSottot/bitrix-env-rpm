PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

TYPE="${1:-update}"

update_localhost() {

    yum -y yum-utils > /dev/null 2>&1

    if [[ $(grep -v '^$\|^#' /etc/yum.conf | \
        grep -c "installonly_limit" ) -eq 0 ]]; then
        echo "installonly_limit=3" >> /etc/yum.conf
    else
        if [[ $(grep -v '^$\|^#' /etc/yum.conf | \
            grep -c "installonly_limit=5") -gt 0 ]]; then
            sed -i "s/installonly_limit=5/installonly_limit=3/" /etc/yum.conf 
        fi
    fi

    package-cleanup --oldkernels --count=3

    yum update --merge-conf -y

    print_message "$CH100" "" "" any_key
}

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
            "update") 
                update_localhost ;;
        esac
    done
}

sub_menu

