PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

# /opt/webdir/bin/bx-sites -a configure_transformer --site sitename --root /home/bitrix/ext_www/sitename --hostname vm04
remove_tr(){
    if [[ -z $TR_SERVER ]]; then
        cache_transfomer_status
    fi

    if [[ -z $TR_SERVER ]]; then
        print_message "$TRANSF210" "$TRANSF011" "" any_key
        return 1
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "SITE_NAME: $TR_SITE"
        echo "SITE_DIR: $TR_DIR"
        echo "SERVER CHOICE: $TR_SERVER"
    fi

    print_message "$(get_text "$TRANSF006" "$TR_SERVER")" "" "" ans "n"
    if [[ $(echo "$ans" | grep -iwc "y") -eq 0 ]]; then
        return 1
    fi

    local task_exec="$bx_web_script -a remove_transformer"
    task_exec=$task_exec" --site $TR_SITE"
    task_exec=$task_exec" --root $TR_DIR"
    task_exec=$task_exec" --hostname $TR_SERVER"
    [[ $DEBUG -gt 0 ]] && \
        echo "task_exec=$task_exec"
    exec_pool_task "$task_exec" "remove_transformer"

}

sub_menu(){

    submenu_00="$TRANSF201"
    submenu_01="1. $TRANSF004"

    SITE_NAME=
    until [[ -n "$SITE_NAME" ]]; do

        menu_logo="$TRANSF004"
        print_menu_header

        print_transformer_status
        print_transformer_status_rtn=$?

        print_sites_transformer_status

        menu_list="\n\t$submenu_01\n\t$submenu_00"

        print_menu

        print_message "$TRANSF205" '' '' SITE_NAME

        case "$SITE_NAME" in
            0) exit ;;
            1) remove_tr ;;
        esac
        SITE_NAME=
    done
}

sub_menu

