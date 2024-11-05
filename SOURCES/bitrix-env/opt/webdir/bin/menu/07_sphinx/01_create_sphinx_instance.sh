#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG  ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)

create_sphinx_instance() {
    local srv_name="$1"

    test_srv_name=$(echo "$NOSPHINX_SERVERS" | grep -c "^$srv_name:")
    [[ $test_srv_name -eq 0 ]] && print_message "$(get_text "$SPH0206" "$srv_name")" "" "" any_key && return 1

    print_pool_sites "" "Y"
    print_message "$SPH0005" "" "" sphinx_dbname
    if [[ $(echo "$POOL_SITES_KERNEL_LIST" | grep -c ":$sphinx_dbname:") -eq 0 ]];
    then
        print_message "$(get_text "$SPH0006" "$sphinx_dbname")" "" "" any_key
        return 2
    fi

    print_message "$SPH0007" "" "" sphinx_reindex 'n'
    task_exec="$bx_sphinx_script -a create -s $srv_name -d $sphinx_dbname"
    task_desc="$(get_text "$SPH0008" "$srv_name")"

    [[ $(echo "$sphinx_reindex" | grep -wic "y") -gt 0  ]] && task_exec=$task_exec" --reindex"

    [[ $DEBUG -gt 0  ]] && echo "task_exec=$task_exec"
    exec_pool_task "$task_exec" "$task_desc"
}

sub_menu() {
    menu_00="$SPH0201"
    menu_01="$SPH0009"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$SPH0009"
        print_menu_header

        # print all
        print_sphinx_servers_status nosphinx
        print_sphinx_servers_status_rtn=$?

        # task info
        get_task_by_type '(sphinx|monitor)' POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(sphinx|monitor)' "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        if [[ ( $POOL_SUBMENU_TASK_LOCK -eq 1 ) || ( $print_sphinx_servers_status_rtn -gt 0  ) ]];
        then
            menu_list="$menu_00"
        else
            menu_list="$menu_01\n\t\t $menu_00"
        fi

        print_menu

        if [[ ( $POOL_SUBMENU_TASK_LOCK -gt 0 ) || ( $print_web_servers_status_rtn -gt 0 ) ]];
        then
            print_message "$SPH0202" '' '' MENU_SELECT 0
        else
            print_message "$SPH0204" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            *) create_sphinx_instance "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
