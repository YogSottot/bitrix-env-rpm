#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

# /opt/webdir/bin/bx-sites -a configure_transformer --site sitename --root /home/bitrix/ext_www/sitename --hostname vm04
configure_tr() {
    if [[ -z $SITES_TR ]]; then
        sites_transformer_status
    fi

    if [[ -z $TR_CHOICE ]]; then
        cache_transfomer_status
    fi

    # SITES_TR
    if [[ -z $SITE_NAME ]]; then
        print_message "$TRANSF210" "$TRANSF013" "" any_key
        return 1
    fi

    SITE_DIR=$(echo -e "$SITES_TR" | grep "^$SITE_NAME:" | \
        awk -F':' '{print $2}')
    if [[ -z $SITE_DIR ]]; then
        print_message "$TRANSF210" \
            "$(get_text "$TRANSF014" "$SITE_NAME")" \
            "" any_key
        return 1
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "SITE_NAME: $SITE_NAME"
        echo "SITE_DIR: $SITE_DIR"
        echo "SERVER CHOICE: $TR_CHOICE"
    fi

    print_message "$TRANSF002" "$TRANSF017" "" ans "y"
    if [[ $(echo "$ans" | grep -iwc "y") -eq 0 ]]; then
        return 1
    fi

    #local task_exec="$bx_web_script -a configure_transformer"
    #task_exec=$task_exec" --site $SITE_NAME"
    #task_exec=$task_exec" --root $SITE_DIR"
    #task_exec=$task_exec" --hostname $TR_CHOICE"
    #task_exec=$task_exec" --domains $SITE_NAME,localhost"
    #[[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
    #exec_pool_task "$task_exec" "configure_transformer"

}

sub_menu() {
    submenu_00="$TRANSF201"
    submenu_01="   $TRANSF204"

    SITE_NAME=
    until [[ -n "$SITE_NAME" ]]; do

        menu_logo="$TRANSF003"
        print_menu_header

        print_transformer_status
        print_transformer_status_rtn=$?

        print_sites_transformer_status


        if  [[ -n "$TR_SERVER" ]]; then
            menu_list="\n\t$submenu_00"
        else
            menu_list="\n\t$submenu_01\n\t$submenu_00"
        fi

        if [[ -n "$TR_SERVER" ]]; then
            print_color_text "$TRANSF015"
            echo
        fi

        print_menu
        if  [[ -n "$TR_SERVER" ]]; then
            print_message "$TRANSF202" '' '' SITE_NAME
        else
            print_message "$TRANSF204 " '' '' SITE_NAME
        fi


        case "$SITE_NAME" in
            0) exit ;;
            *) 
                if [[ -n "$TR_SERVER" ]]; then
                    exit
                fi
                #configure_tr "$SITE_NAME" ;;
        esac
        SITE_NAME=
    done
}

sub_menu
