#!/bin/bash
# manage sites and site's options 
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

logo=$(get_logo)
# get kernel options
# SITE_DB
# SITE_ROOT
# SITE_CHARSET
# SITE_PASSWORD
# SITE_CRON
get_kernel_options() {
    local site_name=${1}

    # site charset
    SITE_CHARSET="utf-8"
    print_message "$CS0013" "" \
        "" site_charset "$SITE_CHARSET"
    SITE_CHARSET=$(echo "$SITE_CHARSET" | awk '{print tolower($0)}')
    if [[ ( "$SITE_CHARSET" != "utf-8" ) && ( "$SITE_CHARSET" != "windows-1251" ) ]]; then
        print_message "$CS0100" "$CS0200" "" any_key
        return 1
    fi

    if [[ $PUSH_SERVERS_CNT -gt 0 ]]; then
        CONF_PUSH=y
        push_server=$(echo "$PUSH_SERVERS" | \
            grep NodeJS-PushServer | awk -F':' '{print $2}')
        print_message "$CS0015" "$(get_text "$CS0014" "$push_server")" \
            "" CONF_PUSH "$CONF_PUSH"
        CONF_PUSH=$(echo "$CONF_PUSH" | awk '{print tolower($0)}')
        if [[ ( "$CONF_PUSH" != "y"  ) && ( "$CONF_PUSH" != "n"  ) ]]; then
            print_message "$CS0100" "$CS0201" "" any_key
            return 1
        fi
    fi

    # site cron usage, enable or disable
    SITE_CRON="n"
    print_message "$CS0016" "$CS0017\n$CS0018" \
        "" SITE_CRON "$SITE_CRON"
    SITE_CRON=$(echo "$SITE_CRON" | awk '{print tolower($0)}')
    if [[ ( "$SITE_CRON" != "y" ) && ( "$SITE_CRON" != "n" ) ]]; then
        print_message "$CS0100" "$CS0201" "" any_key
        return 1
    fi

    # auto options
    SITE_ROOT=          # path to document root
    SITE_DB=            # database name
    SITE_USER=          # database user
    SITE_PASSWORD=      # database password
    manual_input=N
    print_message "$CS0020" "$CS0019" \
        "" manual_input "$manual_input"
    if [[ $(echo "$manual_input" | grep -wci "y") -gt 0 ]]; then
        local site_short=$(echo "$site_name" | awk -F'.' '{print $1}')
        SITE_ROOT=/home/bitrix/ext_www/$site_name
        SITE_DB=db"$site_short"
        SITE_USER=user"$site_short"

        # we dont't test empty string, because there is deafult value for this options
        print_message "$(get_text "$CS0021" "$SITE_ROOT")" "" "" SITE_ROOT "$SITE_ROOT"
        print_message "$(get_text "$CS0022" "$SITE_DB")" "" "" SITE_DB "$SITE_DB"
        print_message "$(get_text "$CS0023" "$SITE_USER")" "" "" SITE_USER "$SITE_USER"
        # test user name
        if [[ $(echo "$SITE_USER" | grep -wci "root") -gt 0 ]]; then
            print_message "$CS0100" "$CS0202" "" any_key
            return 1
        fi
        # password info
        ask_password_info "$SITE_USER" SITE_PASSWORD
        [[ $? -gt 0 ]] && return 1
    fi
    if [[ -n "$SITE_PASSWORD" ]]; then
        SITE_PASSWORD_FILE=$(mktemp $CACHE_DIR/.siteXXXXXXXX)
        echo "$SITE_PASSWORD" > $SITE_PASSWORD_FILE
    fi


    if [[ $DEBUG -gt 0 ]]; then
        if [[ -n $SITE_ROOT ]]; then
            echo "SITE_ROOT:            $SITE_ROOT"
            echo "SITE_DB:              $SITE_DB"
            echo "SITE_USER:            $SITE_USER"
            [[ -f $SITE_PASSWORD_FILE ]] && \
                echo "SITE_PASSWORD_FILE:   $SITE_PASSWORD_FILE"
            echo "SITE_PASSWORD:        $SITE_PASSWORD"
        fi
        echo "SITE_CHARSET:  $site_charset"
        echo "SITE_CRON:     $SITE_CRON"
        echo "CONF_PUSH:     $CONF_PUSH"
    fi
    return 0
}


# kernel site
create_site_kernel() {
    local site_name=$1

    create_site_mark=N
    create_site_exe=
    create_site_limit=3
    create_site_try=1
    until [[ "$create_site_mark" == "Y" ]]; do
        if [[ $create_site_try -gt $create_site_limit ]]; then
            print_message "$CS0101" "$CS0203" "" any_key
            exit
        fi
        create_site_try=$(($create_site_try+1))
        get_kernel_options "$site_name"
        [[ $? -gt 0 ]] && continue

        create_site_exe=$bx_sites_script" -a create -s $site_name"
        create_site_exe=$create_site_exe" -t kernel --charset $site_charset"
        if [[ "$SITE_CRON" == "y" ]]; then
            create_site_exe=$create_site_exe" --cron"
        fi
        if [[ -n "$SITE_ROOT" ]]; then
            create_site_exe=$create_site_exe" -d $SITE_DB -u $SITE_USER"
            create_site_exe=$create_site_exe" --password_file $SITE_PASSWORD_FILE"
            create_site_exe=$create_site_exe" -r $SITE_ROOT"
        fi
        if [[ ( -n $CONF_PUSH ) && ( $CONF_PUSH == "y" ) ]]; then
            create_site_exe=$create_site_exe" --nodejspush"
        fi
        create_site_mark=Y
    done

    [[ $DEBUG -gt 0 ]] && echo "$create_site_exe"
    exec_pool_task "$create_site_exe" "create kernel-site $site_name"
    print_log "create background task=$_task_id for kernel-site=$site_name" $LOGS_FILE

}

# kernel site
external_kernel() {
    local site_name=$1

 
    create_site_mark=N
    create_site_exe=
    create_site_limit=3
    create_site_try=1
    until [[ "$create_site_mark" == "Y" ]]; do
        if [[ $create_site_try -gt $create_site_limit ]]; then
            print_message "$CS0101" "$CS0203" "" any_key
            exit
        fi
        create_site_try=$(($create_site_try+1))
        get_kernel_options "$site_name"
        [[ $? -gt 0 ]] && continue

        create_site_exe=$bx_sites_script" -a create -s $site_name"
        create_site_exe=$create_site_exe" -t ext_kernel --charset $site_charset"
        if [[ "$SITE_CRON" == "y" ]]; then
            create_site_exe=$create_site_exe" --cron"
        fi
        if [[ -n "$SITE_ROOT" ]]; then
            create_site_exe=$create_site_exe" -d $SITE_DB -u $SITE_USER"
            create_site_exe=$create_site_exe" --password_file $SITE_PASSWORD_FILE"
            create_site_exe=$create_site_exe" -r $SITE_ROOT"
        fi
        create_site_mark=Y
    done
    [[ $DEBUG -gt 0 ]] && echo "$create_site_exe"
    exec_pool_task "$create_site_exe" "create ext_kernel-site $site_name"
    print_log "create background task=$_task_id for kernel=$site_name kernel_dir=$site_root" $LOGS_FILE
}


# link site
create_site_link() {
    site_name=$1
  
    create_site_mark=N
    create_site_exe=
    create_site_limit=3
    create_site_try=1
    until [[ "$create_site_mark" == "Y" ]]; do
        kernel_directory=/home/bitrix/www
        if [[ $create_site_try -gt $create_site_limit ]]; then
            print_message "$CS0101" "$CS0203" "" any_key
            exit
        fi
         print_message "$(get_text "$CS0024" "$kernel_directory")" \
             "" "" kernel_directory "$kernel_directory"
        # test input options
        if [[ -z "$kernel_directory" ]]; then
            print_message "$CS0100" "$CS0207" "" any_key
        else

            # test if directory exist
            if [[ ! -d "$kernel_directory" ]]; then
                print_message "$CS0100" "$(get_text "$CS0208" "$kernel_directory")" \
                    "" any_key
            else
                test_subdirectory=""
                for folder in "upload" "images" "bitrix"; do
                    if [[ ! -d "$kernel_directory/$folder" ]]; then
                        test_subdirectory=$test_subdirectory"$folder, "
                    fi
                done
                test_subdirectory=$(echo $test_subdirectory | sed -e 's/, $//')

                # all test done, form exec command
                if [[ -n "$test_subdirectory" ]]; then
                    print_message "$CS0100" \
                        "$(get_text "$CS0212" "$test_subdirectory" "$kernel_directory")" \
                        "" any_key
                else
                # try found kernel name and options
                kernel_configs=$(echo "$SITES_LIST_WITH_NUMBER" | grep "$kernel_directory")
                    if [[ -n $kernel_configs ]]; then
                        kernel_name=$(echo "$kernel_configs" | awk -F':' '{print $2}') 
                        create_site_exe="$bx_sites_script -a create -s $site_name -t link --kernel_site $kernel_name --kernel_root $kernel_directory"
                        create_site_mark=Y
                    else
                        create_site_exe="$bx_sites_script -a create -s $site_name -t link --kernel_root $kernel_directory"
                        create_site_mark=Y
                    fi
                fi
            fi
        fi
        create_site_try=$(($create_site_try+1))
    done

    [[ $DEBUG -gt 0 ]] && echo "$create_site_exe"
    exec_pool_task "$create_site_exe" "create link-site $site_name"
    print_log "create background task=$_task_id for link=$site_name kernel_dir=$kernel_directory" $LOGS_FILE

}

# create site
# use SITES_LIST_WITH_NUMBER for check if site exist or not
create_site() {
    site_name=$1

    # test site name
    if [[ -z "$site_name" ]]; then
        print_message "$CS0101" "$CS0209" "" any_key
        return 1
    fi

    ### 1. test if site with defined name exists in list
    #echo "$SITES_LIST_WITH_NUMBER"
    if [[ $(echo "$SITES_LIST_WITH_NUMBER" | grep -ci ":$site_name:") -gt 0 ]]; then
        print_message "$CS0101" \
            "$(get_text "$CS0210" "$site_name")" \
            "" any_key
        return 1
    fi

    # additional options
    site_type="link"
  
    ### 2. site type: link, kernel or ext kernel
    print_color_text "$CS0007" blue
    echo "$CS0008"
    echo "$CS0009"
    echo "$CS0010"
    print_color_text "$CS0011" blue
    print_message "$CS0012" "" "" site_type "$site_type"

    # process input
    # coonvert to lower case string
    site_type=$(echo "$site_type" | awk '{print tolower($0)}')
    case "$site_type" in
    link) create_site_link "$site_name" ;;
    kernel) create_site_kernel "$site_name" ;;
    ext_kernel) external_kernel "$site_name" ;;
    *) 
        print_message "$CS0101" \
            "$(get_text "$CS0211" "$site_type")" "" any_key
    ;;
    esac
}

# print host menu
sub_menu() {
    menu_00="$CS0002"
    menu_01="$CS0001"


    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do

        menu_logo="$CS0003"
        print_menu_header

        # test mysql options: 
        #   empty password and empty my.cnf file
        #   cluster settings
        #   push server settings
        check_site_options 
        if [[ $? -gt 0 ]]; then
            print_message "$CS0101" "" "" any_key
            exit
        fi

        # test backgrounf tasks
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        [[ $POOL_SITE_TASK_LOCK -eq 0 ]] && POOL_SITES_KERNEL_COUNT=

        print_pool_sites
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="\n$menu_00"
        else
            menu_list="\n$menu_01\n$menu_00"
        fi

        print_menu

        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            print_message "$CS0005" '' '' SITE_MENU_SELECT 0
        else
            print_message "$CS0006" '' '' SITE_MENU_SELECT
        fi

        # process selection
        case "$SITE_MENU_SELECT" in
            "0") exit ;;
            *)
                test_hostname $SITE_MENU_SELECT
                [[ $test_hostname -eq 1 ]] && create_site "$SITE_MENU_SELECT"
            ;;
        esac
    
        SITE_MENU_SELECT=
    done
}

sub_menu

