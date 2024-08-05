#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

TYPE="${1:-update}"

BIN_DIR=/opt/webdir/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

update_localhost() {
    [[ -z $OS_VERSION ]] && get_os_type

    # CentOS 7
    if [[ $OS_VERSION -eq 7 ]]; then
	yum -y install yum-utils > /dev/null 2>&1
	if [[ $(grep -v '^$\|^#' /etc/yum.conf | grep -c "installonly_limit" ) -eq 0 ]]; then
	    echo "installonly_limit=3" >> /etc/yum.conf
	else
	    if [[ $(grep -v '^$\|^#' /etc/yum.conf | grep -c "installonly_limit=5") -gt 0 ]]; then
		sed -i "s/installonly_limit=5/installonly_limit=3/" /etc/yum.conf
	    fi
	fi
	package-cleanup --oldkernels --count=3 -y
	# percona
	if [[ $(yum list installed | grep -c "Percona") -gt 0 ]]; then
	    yum -y --nogpg update percona-release
	fi
	yum update --merge-conf -y
	print_message "$CH100" "" "" any_key
    fi
    # CentOS Stream 9
    if [[ $OS_VERSION -eq 9 ]]; then
	dnf -y install dnf-utils > /dev/null 2>&1
	# yum.conf
	if [[ $(grep -v '^$\|^#' /etc/yum.conf | grep -c "installonly_limit" ) -eq 0 ]]; then
	    echo "installonly_limit=3" >> /etc/yum.conf
	else
	    if [[ $(grep -v '^$\|^#' /etc/yum.conf | grep -c "installonly_limit=5") -gt 0 ]]; then
		sed -i "s/installonly_limit=5/installonly_limit=3/" /etc/yum.conf
	    fi
	fi
	# dnf conf
	if [[ $(grep -v '^$\|^#' /etc/dnf/dnf.conf | grep -c "installonly_limit" ) -eq 0 ]]; then
	    echo "installonly_limit=3" >> /etc/dnf/dnf.conf
	else
	    if [[ $(grep -v '^$\|^#' /etc/dnf/dnf.conf | grep -c "installonly_limit=5") -gt 0 ]]; then
		sed -i "s/installonly_limit=5/installonly_limit=3/" /etc/dnf/dnf.conf
	    fi
	fi
	dnf remove --oldinstallonly --setopt installonly_limit=3 kernel -y
	# percona
	#if [[ $(dnf list installed | grep -c "Percona") -gt 0 ]]; then
	    #dnf -y --nogpg update percona-release
	#fi
	dnf -y update
	print_message "$CH100" "" "" any_key
    fi
}

sub_menu() {
    menu_logo="${TYPE^} server"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        [[ $DEBUG -eq 0 ]] && clear
        echo -e "\t\t" $logo
        echo -e "\t\t" $menu_logo
        echo

        print_message "$(get_text "$CH025" "$TYPE")" "" "" answer n

        [[ $(echo "$answer" | grep -wci "y") -gt 0 ]] || exit

        case "$TYPE" in
            "update") update_localhost ;;
        esac
    done
}

sub_menu
