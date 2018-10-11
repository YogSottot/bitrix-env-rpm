#!/bin/bash
# manage sites and site's options 
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/06_site/functions.sh || exit 1
logo=$(get_logo)

_ntlm_menu() {
  $sites_menu/07_ntlm.sh
}

_create_site() {
  $sites_menu/01_create.sh
}

_delete_site() {
  $sites_menu/02_delete.sh
}

_cron_site() {
  $sites_menu/03_crontab.sh
}

_email_site() {
  $sites_menu/04_email.sh
}

_http_site() {
  $sites_menu/05_https.sh
}

_backup_kernel() {
  $sites_menu/06_backup.sh
}

_cron_service() {
  $sites_menu/08_cronservice.sh
}

_composite_site() {
  $sites_menu/09_composite.sh
}

_site_options() {
  $sites_menu/10_site_options.sh
}

# print host menu
_menu_sites() {
  _menu_sites_00="$SM0201"
  _menu_sites_03="$SM0133"
  _menu_sites_04="$SM0134"
  _menu_sites_05="$SM0135"
  _menu_sites_06="$SM0136"
  _menu_sites_10="$SM0137"
  _menu_sites_11="$SM0138"

  SITE_MENU_SELECT=
  until [[ -n "$SITE_MENU_SELECT" ]]; do
    menu_logo="$SM0132"
    print_menu_header

    # menu
    get_pool_sites
    print_pool_sites
    get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
    print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
    if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
      menu_list="\n\t$_menu_sites_00"
    else

    # define menu points
        menu_list="\n\t$_menu_sites_03\n\t$_menu_sites_04\n\t$_menu_sites_05"
        menu_list=$menu_list"\n\t$_menu_sites_06\n\t$_menu_sites_10"
        if [[ $POOL_SITES_ERRORS_COUNT -gt 0 ]]; then
            menu_list=$menu_list"\n\t$_menu_sites_11\n\t$_menu_sites_00"
        else
            menu_list=$menu_list"\n\t$_menu_sites_00"
        fi
    fi
    print_menu
    print_message "$SM0205" '' '' SITE_MENU_SELECT

    # process selection
    case "$SITE_MENU_SELECT" in
      "1") _cron_site;;
      "2") _email_site;;
      "3") _http_site;;
      "4") _backup_kernel;;
      "5") _site_options;;
      "6") print_pool_sites_error;;
      "0") exit ;;
      *)   error_pick;;
    esac
    SITE_MENU_SELECT=
  done
}

_menu_sites

