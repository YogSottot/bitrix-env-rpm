#!/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

[[ -z $DEBUG ]] && DEBUG=0

# CLUSTER_MESSAGE
upgrade_php_mysql() {
    current_state="${1:-255}"
    user_choice="${2}"

    [[ $DEBUG -gt 0 ]] && echo "msg=$CLUSTER_MESSAGE"
    # update mysql
    if [[ $user_choice -eq 3 ]]; then
        print_color_text "$HM0080" red
        echo "$HM0081"
        echo
        print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'
        [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

        local upgrade_task="$ansible_wrapper -a bx_upgrade_mysql57"
        [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
        exec_pool_task "$upgrade_task" "update mysql to version 5.7"

        return $?
    fi

    # php 7.0 - 40
    # php 7.1 - 41
    # php 7.2 - 42
    # 1 - rollback; 2 - update
    if [[ ( $current_state -eq 40 ) || ( $current_state -eq 50 ) ]]; then
        if [[ $user_choice -eq 1 ]]; then
            print_color_text "$HM0077" red
            echo "$HM0078"
            echo
            print_message "$(get_text "$HM0079" "rollback")" "" "" confirm 'n'
            [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

            local upgrade_task="$ansible_wrapper -a bx_php_rollback_php7"
            [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
            exec_pool_task "$upgrade_task" "rollback php to 5.6"

        else
            print_color_text "$HM0075" red -e
            echo "$HM0099"
            echo
            print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'
            [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

            local upgrade_task="$ansible_wrapper -a bx_php_upgrade_php71"
            [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
            exec_pool_task "$upgrade_task" "update php to 7.1"
        fi

    elif [[ ( $current_state -eq 41 ) || ( $current_state -eq 51 ) ]]; then
        if [[ $user_choice -eq 1 ]]; then
            print_color_text "$HM0077" red
            echo "$HM0100"
            echo
            print_message "$(get_text "$HM0079" "rollback")" "" "" confirm 'n'
            [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

            local upgrade_task="$ansible_wrapper -a bx_php_rollback_php70"
            [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
            exec_pool_task "$upgrade_task" "rollback php to 7.0"

        else
            print_color_text "$HM0075" red -e
            echo "$HM0101"
            echo
            print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'
            [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

            local upgrade_task="$ansible_wrapper -a bx_php_upgrade_php72"
            [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
            exec_pool_task "$upgrade_task" "update php to 7.2"
        fi


    elif [[ ( $current_state -eq 42 ) || ( $current_state -eq 52 ) ]]; then
        if [[ $user_choice -eq 1 ]]; then
            print_color_text "$HM0077" red
            echo "$HM0102"
            echo
            print_message "$(get_text "$HM0079" "rollback")" "" "" confirm 'n'
            [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

            local upgrade_task="$ansible_wrapper -a bx_php_rollback_php71"
            [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
            exec_pool_task "$upgrade_task" "rollback php to 7.0"

        fi

    elif [[ ( (  $current_state -eq 21 ) || ( $current_state -eq 31 ) ) \
        && ( $user_choice -eq 1 ) ]]; then

        print_color_text "$HM0075" red -e
        echo "$HM0076"
        echo
        print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'
        [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

        local upgrade_task="$ansible_wrapper -a bx_php_upgrade_php7"
        [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
        exec_pool_task "$upgrade_task" "update php to 7.0"


    elif [[ ( ( $current_state -eq 22 ) || ( $current_state -eq 32 ) ) \
        && ( $user_choice -eq 1 ) ]]; then
        print_color_text "$HM0077" red
        echo "$HM0078"
        echo
        print_message "$(get_text "$HM0079" "rollback")" "" "" confirm 'n'
        [[ $(echo "$confirm" | grep -iwc 'n') -gt 0   ]] && return 1

        local upgrade_task="$ansible_wrapper -a bx_php_rollback_php7"
        [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
        exec_pool_task "$upgrade_task" "rollback php to 5.6"

    elif [[ $current_state -eq 1 ]]; then
        print_color_text "$HM0075" red
        echo "$HM0082"
        echo
        print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'

        [[ $(echo "$confirm" | grep -iwc 'n') -gt 0  ]] && return 1

        local upgrade_task="$ansible_wrapper -a bx_php_upgrade_php56"
        [[ $DEBUG -gt 0  ]] && echo "cmd=$upgrade_task"
        exec_pool_task "$upgrade_task" "update php to 5.6"

    elif [[ $current_state -eq 0 ]]; then

        print_color_text "$HM0075" red
        echo "$HM0083"
        echo
        print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'

        [[ $(echo "$confirm" | grep -iwc 'n') -gt 0 ]] && return 1

        local upgrade_task="$ansible_wrapper -a bx_php_upgrade"
        [[ $DEBUG -gt 0 ]] && echo "cmd=$upgrade_task"
        exec_pool_task "$upgrade_task" "update mysql and php"
    else 
        print_message "$HM0200" \
            "$HM0084\n$CLUSTER_MESSAGE"
            "" any_key
        return 1
    fi
 
}

sub_menu() {
    local host_logo="$HM0085"
    local menu_00="$HM0042"
    local menu_000="1. $HM0086"
    local menu_001="1. $HM0087"
    # php 5.6
    local menu_0021="1. $HM0088"

    # php 7.0
    local menu_00302="2. $HM00881" # update
    local menu_00301="1. $HM0089"  # rollback

    # php 7.1
    local menu_00312="2. $HM00882" # update
    local menu_00311="1. $HM00891" # rollback

    # php 7.2
    local menu_00321="1. $HM00892" # rollback

    local menu_003="3. $HM0090" # update mysql server

    local menu_255="1. $HM0091"


    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_pool_info
    
        # test current status
        test_upgrade_on_cluster
        test_upgrade_on_cluster_rtn=$?
        [[ $DEBUG -gt 0  ]] && echo "msg=$CLUSTER_MESSAGE"

        menu_list=
        if [[ $test_upgrade_on_cluster_rtn -eq 255 ]]; then

            menu_list="\n\t$menu_00\n\t$menu_255"

        elif [[ $test_upgrade_on_cluster_rtn -eq 1 ]]; then

            menu_list="\n\t$menu_00\n\t$menu_001"

        elif [[ $test_upgrade_on_cluster_rtn -eq 0 ]]; then

            menu_list="\n\t$menu_00\n\t$menu_000"

        elif [[ $test_upgrade_on_cluster_rtn -eq 21 ]]; then

            menu_list="\n\t$menu_00\n\t$menu_0021\n\t$menu_003"

        elif [[ $test_upgrade_on_cluster_rtn -eq 22 ]]; then

            menu_list="\n\t$menu_00\n\t$menu_00301\n\t$menu_003"

        elif [[ $test_upgrade_on_cluster_rtn -eq 31 ]]; then

            menu_list="\n\t$menu_00\n\t$menu_0021"

        # 40 - 7.0
        # 41 - 7.1
        # 42 - 7.2
        elif [[ $test_upgrade_on_cluster_rtn -eq 40 ]]; then
            if [[ $BITRIX_ENV_TYPE == "crm" ]]; then
                menu_list="\n\t$menu_00\n\t$menu_00302"
            else
                menu_list="\n\t$menu_00\n\t$menu_00301\n\t$menu_00302"

            fi
 
        elif [[ $test_upgrade_on_cluster_rtn -eq 41 ]]; then
            if [[ $DEBUG -gt 0 ]]; then
                menu_list="\n\t$menu_00\n\t$menu_00311\n\t$menu_00312"
            else
                menu_list="\n\t$menu_00\n\t$menu_00311"
                menu_exclude=2
            fi

 
        elif [[ $test_upgrade_on_cluster_rtn -eq 42 ]]; then
            if [[ $DEBUG -gt 0 ]]; then
                menu_list="\n\t$menu_00\n\t$menu_00321"
            else
                menu_list="\n\t$menu_00"
                menu_exclude=2
            fi

        # 50 - 7.0, mysql 5.5
        # 51 - 7.1, mysql 5.5
        # 52 - 7.2, mysql 5.5
        elif [[ $test_upgrade_on_cluster_rtn -eq 50 ]]; then
            if [[ $BITRIX_ENV_TYPE == "crm" ]]; then
                menu_list="\n\t$menu_00\n\t$menu_00302\n\t$menu_003"
            else
                menu_list="\n\t$menu_00\n\t$menu_00301\n\t$menu_00302\n\t$menu_003"

            fi
 
        elif [[ $test_upgrade_on_cluster_rtn -eq 51 ]]; then
            if [[ $DEBUG -gt 0 ]]; then
                menu_list="\n\t$menu_00\n\t$menu_00311\n\t$menu_00312\n\t$menu_003"
            else
                menu_list="\n\t$menu_00\n\t$menu_00311\n\t$menu_003"
                menu_exclude=2
            fi

 
        elif [[ $test_upgrade_on_cluster_rtn -eq 52 ]]; then
            if [[ $DEBUG -gt 0 ]]; then
                menu_list="\n\t$menu_00\n\t$menu_00321\n\t$menu_003"
            else
                menu_list="\n\t$menu_00\n\t$menu_003"
                menu_exclude=2
            fi


        else

            menu_list="\n\t$menu_00"
        fi 

        print_menu

        print_message "$HM0204" '' '' MENU_SELECT
        if [[ ( -n $menu_exclude ) && ( -n $MENU_SELECT ) \
            && ( $MENU_SELECT -eq $menu_exclude ) ]]; then
            error_pick
            MENU_SELECT=
            exit
        fi
        # process selection
        case "$MENU_SELECT" in
            "0") exit ;;
            [123]) 
                echo 
                if [[ ( $test_upgrade_on_cluster_rtn -eq 40 ) && \
                    ( $BITRIX_ENV_TYPE == "crm" ) && ( $MENU_SELECT -eq 1 ) ]]; then
                    error_pick 
                    MENU_SELECT=
                else
                    upgrade_php_mysql "$test_upgrade_on_cluster_rtn" "$MENU_SELECT"
                fi
                ;;
            *) error_pick;;

        esac
        MENU_SELECT=
    done
}

sub_menu

