#!/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

. $PROGPATH/functions.sh || exit 1

[[ -z $DEBUG ]] && DEBUG=0


get_os_type
sub_menu_update_php(){
    local min_php_version="${1:-255}"
    local phost_name="${2}"


    local host_logo="$HM0088"
    local menu_exit="$HM0042"
    local up_php83="1. $HM00888"

    local up_php82="2. $HM00887"
    local up_php81="3. $HM00886"
    local up_php80="4. $HM00885"
    local up_php74="5. $HM00884"
    local up_php73="6. $HM00883"
    local up_php72="7. $HM00882"
    local up_php71="8. $HM00881"
    local up_php70="9. $HM00880"
    local up_php56="10. $HM0087"

    
    local up_menu="\n\t$menu_exit"
    [[ $min_php_version -ge 56 && $min_php_version -lt 83  && $OS_VERSION -gt 6 ]] && \
        up_menu=$up_menu"\n\t$up_php83"
    [[ $min_php_version -ge 56 && $min_php_version -lt 82  && $OS_VERSION -gt 6 ]] && \
        up_menu=$up_menu"\n\t$up_php82"
    [[ $min_php_version -ge 56 && $min_php_version -lt 81  && $OS_VERSION -gt 6 ]] && \
        up_menu=$up_menu"\n\t$up_php81"
    [[ $min_php_version -ge 56 && $min_php_version -lt 80  && $OS_VERSION -gt 6 ]] && \
        up_menu=$up_menu"\n\t$up_php80"
    [[ $min_php_version -ge 56 && $min_php_version -lt 74  && $OS_VERSION -gt 6 ]] && \
        up_menu=$up_menu"\n\t$up_php74"
    [[ $min_php_version -ge 56 && $min_php_version -lt 73 ]] && \
        up_menu=$up_menu"\n\t$up_php73"
    [[ $min_php_version -ge 56 && $min_php_version -lt 72 ]] && \
        up_menu=$up_menu"\n\t$up_php72"
    [[ $min_php_version -ge 56 && $min_php_version -lt 71 ]] && \
        up_menu=$up_menu"\n\t$up_php71"
    [[ $min_php_version -ge 56 && $min_php_version -lt 70 ]] && \
        up_menu=$up_menu"\n\t$up_php70"
    [[ $min_php_version -lt 56 ]] && \
        up_menu=$up_menu"\n\t$up_php56"

    menu_list="$up_menu"

    UP_MENU=
    upgrade_cmd=
    upgrade_version=
    until [[ -n "$UP_MENU" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_mysql_php_version "$phost_name"
        echo "$(get_text "$HM0101" "${min_php_version:0:1}.${min_php_version:1:2}")"

        print_menu

        print_message "$HM0204" '' '' UP_MENU

        # test main module version
        # update php 5.6 to 7.0 version
        if [[ $UP_MENU -ge 1 && $UP_MENU -le 5 && $min_php_version -eq 56 ]]; then
            test_main_module_for_php7
            test_main_module_for_php7_rtn=$?
            echo "test_main_module_for_php7_rtn=$test_main_module_for_php7_rtn"
   			if [[ $test_main_module_for_php7_rtn -gt 1 ]]; then

				print_message "$TEST_PHP7_NOTPASS" \
                    "$(get_text "$HM0029" "$MAIN_LOWER_VERSION")" \
					'' ANY_KEY
				error_pick
				UP_MENU=
				continue
            elif [[ $test_main_module_for_php7_rtn -gt 0 ]]; then
				print_message "$TEST_PHP7_SKIP" "$HM0031" "" ANY_KEY
            fi 
        fi

        case "$UP_MENU" in
            "0") return 1 ;;
            "1") 
                echo "$UP_MENU"
                if [[ $min_php_version -ge 83 || $OS_VERSION -eq 6 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php83 --host $phost_name "
                upgrade_version="8.3"
            ;;
             "2") 
                if [[ $min_php_version -ge 82 || $OS_VERSION -eq 6 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php82 --host $phost_name "
                upgrade_version="8.2"
            ;;
 
            "3") 
                if [[ $min_php_version -ge 81 || $OS_VERSION -eq 6 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php81 --host $phost_name "
                upgrade_version="8.1"
            ;;
            "4") 
                if [[ $min_php_version -ge 80 || $OS_VERSION -eq 6 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php80 --host $phost_name "
                upgrade_version="8.0"
            ;;
            "5") 
                if [[ $min_php_version -ge 74 || $OS_VERSION -eq 6 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php74 --host $phost_name "
                upgrade_version="7.4"
            ;;
            "6")
                if [[ $min_php_version -ge 73 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php73 --host $phost_name"
                upgrade_version="7.3"
                ;;

             "7") 
                if [[ $min_php_version -ge 72 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php72 --host $phost_name"
                upgrade_version="7.2"
                ;;
            "8")
                if [[ $min_php_version -ge 71 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php71 --host $phost_name"
                upgrade_version="7.1"
                ;;
             "9")
                if [[ $min_php_version -ge 70 ]]; then
                    error_pick
                    UP_MENU=
                    continue
                fi
                upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php70 --host $phost_name"
                upgrade_version="7.0"
                ;;
             "10")
                 if [[ $min_php_version -lt 56 ]]; then
                     upgrade_cmd="$ansible_wrapper -a bx_php_upgrade_php56 --host $phost_name"
                     upgrade_version="5.6"
                 else
                     error_pick
                     UP_MENU=
                     continue
                 fi
                 ;;
             *) 
                 error_pick
                 UP_MENU=

                 ;;
        esac
    done

    if [[ $DEBUG -gt 0 ]]; then
        echo "upgrade_cmd=[$upgrade_cmd]"
    fi
    [[ -z $upgrade_cmd ]] && return 0

    print_color_text "$HM0075" red -e
    echo "$(get_text "$HM0099" "$upgrade_version")"

    print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'
    [[ $(echo "$confirm" | grep -iwc 'y') -eq 0  ]] && return 1
    exec_pool_task "$upgrade_cmd" "update php to $upgrade_version"

}

sub_menu_downgrade_php(){
    local min_php_version="${1:-255}"
    local phost_name="${2}"

    local host_logo="$HM0089"
    local menu_exit="$HM0042"

    local down_php56="1. $HM00890"
    local down_php70="2. $HM00891"
    local down_php71="3. $HM00892"
    local down_php72="4. $HM00893"
    local down_php73="5. $HM00894"
    local down_php74="6. $HM00895"
    local down_php80="7. $HM00896"
    local down_php81="8. $HM00897"
    local down_php82="9. $HM00898"

    local down_menu="\n\t$menu_exit"
    [[ $min_php_version -gt 56 && $BITRIX_ENV_TYPE != "crm" ]] && \
        down_menu=$down_menu"\n\t$down_php56"

    [[ $min_php_version -gt 70 && $BITRIX_ENV_TYPE != "crm" ]] && \
        down_menu=$down_menu"\n\t$down_php70"

    [[ $min_php_version -gt 71 ]] && \
        down_menu=$down_menu"\n\t$down_php71"

    [[ $min_php_version -gt 72 ]] && \
        down_menu=$down_menu"\n\t$down_php72"

    [[ $min_php_version -gt 73 ]] && \
        down_menu=$down_menu"\n\t$down_php73"
    
    [[ $min_php_version -gt 74 ]] && \
        down_menu=$down_menu"\n\t$down_php74"
    [[ $min_php_version -gt 80 ]] && \
        down_menu=$down_menu"\n\t$down_php80"
    [[ $min_php_version -gt 81 ]] && \
        down_menu=$down_menu"\n\t$down_php81"
    [[ $min_php_version -gt 82 ]] && \
        down_menu=$down_menu"\n\t$down_php82"

    menu_list="$down_menu"

    DOWN_MENU=
    down_cmd=
    down_version=
    until [[ -n "$DOWN_MENU" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_mysql_php_version "$phost_name"
        echo "$(get_text "$HM0101" "${min_php_version:0:1}.${min_php_version:1:2}")"
        print_menu

        print_message "$HM0204" '' '' DOWN_MENU

        case "$DOWN_MENU" in
            "0") return 1 ;;
            "1") 
                if [[ $min_php_version -le 56 || $BITRIX_ENV_TYPE == "crm" ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php7 --host ${phost_name}"
                down_version="5.6"
            ;;
            "2")
                if [[ $min_php_version -le 70 || $BITRIX_ENV_TYPE == "crm" ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php70 --host ${phost_name}"
                down_version="7.0"
 
               ;;
            "3") 
                if [[ $min_php_version -le 71 ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php71 --host ${phost_name}"
                down_version="7.1"
 
               ;;
            "4")
                if [[ $min_php_version -le 72 ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php72 --host ${phost_name}"
                down_version="7.2"
 
               ;;
            "5")
                if [[ $min_php_version -le 73 ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php73 --host ${phost_name}"
                down_version="7.3"
 
               ;;
            "6")
                if [[ $min_php_version -le 74 ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php74 --host ${phost_name}"
                down_version="7.4"
               ;;
             "7")
                if [[ $min_php_version -le 80 ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php80 --host ${phost_name}"
                down_version="8.0"
               ;;
              "8")
                if [[ $min_php_version -le 81 ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php81 --host ${phost_name}"
                down_version="8.1"
               ;;
               "9")
                if [[ $min_php_version -le 82 ]]; then
                    error_pick
                    DOWN_MENU=
                    continue
                fi
                down_cmd="$ansible_wrapper -a bx_php_rollback_php82 --host ${phost_name}"
                down_version="8.2"
               ;;
 
             *) 
                 error_pick
                 DOWN_MENU=

                 ;;
        esac
    done

    if [[ $DEBUG -gt 0 ]]; then
        echo "down_cmd=[$down_cmd]"
    fi

    [[ -z $down_cmd ]] && return 0

    print_color_text "$HM0077" red -e
    echo "$(get_text "$HM0100" "$down_version")"

    print_message "$(get_text "$HM0079" "downgrade")" "" "" confirm 'n'
    [[ $(echo "$confirm" | grep -iwc 'y') -eq 0  ]] && return 1
    exec_pool_task "$down_cmd" "downgrade php to $down_version"

}

sub_upgrade_mysql() {
    local min_mysql_version=${1:-255}
    local phost_name=${2}

    local host_logo="$HM010201"
    local menu_exit="$HM0042"

    local up_mysql57="1. $HM010202"
    local up_mysql55="1. $HM010203"
    local up_mysql58="1. $HM010205"
    
    local up_menu="\n\t$menu_exit"
    [[ $min_mysql_version -eq 57 && $OS_VERSION -gt 6 ]] &&
        up_menu="\n\t$menu_exit\n\t$up_mysql58"

    [[ $min_mysql_version -lt 57 ]] && \
        up_menu="\n\t$menu_exit\n\t$up_mysql57"

    [[ $min_mysql_version -lt 55 ]] && \
        up_menu="\n\t$menu_exit\n\t$up_mysql55"


    menu_list="$up_menu"

    UP_MENU=
    upgrade_cmd=
    upgrade_version=
    until [[ -n "$UP_MENU" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo


        print_mysql_php_version "${phost_name}"
        echo "$(get_text "$HM0102" "${min_mysql_version:0:1}.${min_mysql_version:1:2}")"

        print_menu

        print_message "$HM0204" '' '' UP_MENU

        case "$UP_MENU" in
            "0") return 1 ;;
            "1") 
                if [[ $min_mysql_version -lt 80 && \
                    $min_mysql_version -ge 57 && $OS_VERSION -gt 6 ]]; then
                    upgrade_cmd="$ansible_wrapper -a bx_upgrade_mysql80 --host $phost_name"
                    upgrade_version="8.0"
                    upgrade_desc="update MySQL to $upgrade_version"
                elif [[ $min_mysql_version -lt 57 && \
                    $min_mysql_version -ge 55 ]]; then
                    upgrade_cmd="$ansible_wrapper -a bx_upgrade_mysql57 --host $phost_name"
                    upgrade_version="5.7"
                    upgrade_desc="update MySQL to $upgrade_version"
                elif [[ $min_mysql_version -lt 55 ]]; then
                    upgrade_cmd="$ansible_wrapper -a bx_php_upgrade --host $phost_name"
                    upgrade_version="5.5"
                    upgrade_desc="update mysql to $upgrade_version and php to 5.6"
                else
                    error_pick
                    UP_MENU=
                    continue
                fi
            ;;
            *) 
                 error_pick
                 UP_MENU=

            ;;
        esac
    done

    if [[ $DEBUG -gt 0 ]]; then
        echo "upgrade_cmd=[$upgrade_cmd]"
    fi

    if [[ $upgrade_version == "5.7" ]]; then
        print_color_text "$HM0080" red
        echo "$HM0081"
        echo
    elif [[ $upgrade_version == "5.5" ]]; then
        print_color_text "$HM0075" red
        echo "$HM0083"
        echo
    fi

    print_message "$(get_text "$HM0079" "update")" "" "" confirm 'n'
    [[ $(echo "$confirm" | grep -iwc 'y') -eq 0 ]] && return 1

    exec_pool_task "$upgrade_cmd" "$upgrade_desc"

}

# select update type for the host
select_update_type() {
    local select_hname="${1}"


    if [[ $select_hname != "all" ]]; then
        cur_id=$(get_server_id "$select_hname")
        cur_id_rtn=$?

        if [[ $cur_id_rtn -eq 1   ]]; then
            print_message "$HM0200" "$(get_text "$HM0013" "$host_ident")" "" any_key
            return 1

        elif [[ $cur_id_rtn -eq 2  ]]; then
            print_message "$HM0200" "$(get_text "$HM0012" "$host_ident")"
            return 1
        elif [[ $cur_id_rtn -eq 3 ]]; then
            print_message "$HM0200" "$HM0044"
            return 1
        fi
    fi

    H_SELECT=

    local host_logo="$HM0085"

    # very old options
    local menu_php_and_mysql="1. $HM0086" # Update PHP to version 5.4 and MySQL to version 5.5
    local menu_php54_56="1. $HM0087"      # Update PHP to version 5.6
    
    # current one
    local menu_php_upgrade="1. $HM0088"     # Upgrade PHP
    local menu_php_downgrade="2. $HM0089"   # Downgrade PHP
    local menu_mysql_upgrade="3. $HM010201" # update mysql server

    # status
    local menu_status="1. $HM0091"           # Show current status


    until [[ -n "$H_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_mysql_php_version "${select_hname}"
        if [[ $DEBUG -gt 0 ]]; then
            echo "MYSQl VERSION: $MYSQL_VERSION"
            echo "PHP VERSION:   $PHP_VERSION"
        fi

        menu_list="\n\t${menu_exit}"
        if [[ $PHP_VERSION -le 82 ]]; then
            menu_list="${menu_list}\n\t${menu_php_upgrade}"
        fi

        if [[ $PHP_VERSION -gt 56 ]]; then
                menu_list="${menu_list}\n\t${menu_php_downgrade}"
        fi 

        if [[ ${select_hname} != "all" ]]; then
            if [[ $MYSQL_VERSION -le 51  ]]; then
                menu_list="${menu_list}\n\t${menu_php54_56}"
            elif [[ $MYSQL_VERSION -lt 80 ]]; then
                menu_list="${menu_list}\n\t${menu_mysql_upgrade}"
            fi
        fi

        print_menu

        print_message "$HM0204" '' '' H_SELECT

        # process selection
        case "$H_SELECT" in
            "0") return 0 ;;

            "1") sub_menu_update_php "$PHP_VERSION" "$select_hname";;

            "2") sub_menu_downgrade_php "$PHP_VERSION" "$select_hname" ;;

            "3") sub_upgrade_mysql "$MYSQL_VERSION" "$select_hname" ;;

            *) error_pick ;;
        esac
        H_SELECT=
    done
    exit
}


# select one host min the Bitrix pool
sub_menu() {
    local host_logo="$HM0085"
    local menu_exit="$HM0042"

    local menu_exit="$HM0042"                   # 0. Previous screen or exit
    local menu_update="$HM10001"                # Update or rallback software on the server
    local menu_select_message="$HM0205"         # Enter hostname or 0 to exit


    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        clear
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" $host_logo
        echo

        print_mysql_php_version
        MASTER_MYSQL_VERSION="$MYSQL_VERSION"
        MASTER_PHP_VERSION="$PHP_VERSION"
        if [[ $DEBUG -gt 0 ]]; then
            echo "MASTER MYSQL VERSION: $MASTER_MYSQL_VERSION"
            echo "MASTER PHP VERSION:   $MASTER_PHP_VERSION"
        fi

        get_task_by_type '(common|web_cluster|mysql|monitor)' \
            POOL_SUBMENU_TASK_LOCK POOL_SUBMENU_TASK_INFO
        print_task_by_type '(common|web_cluster|mysql|monitor)' \
            "$POOL_SUBMENU_TASK_LOCK" "$POOL_SUBMENU_TASK_INFO"

        menu_list="\n\t${menu_update}\n\t${menu_exit}"

        if [[ $POOL_SUBMENU_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_exit"
        fi

        print_menu
        if [[ $POOL_SUBMENU_TASK_LOCK -eq 1 ]]; then
            print_message "$HM0202" '' '' MENU_SELECT 0
        else
            print_message "$menu_select_message" "$HM10002" '' MENU_SELECT 0
        fi

        case "$MENU_SELECT" in
            0) exit;;
            *) select_update_type "$MENU_SELECT" ;;
        esac
        MENU_SELECT=
    
    done
}

sub_menu

