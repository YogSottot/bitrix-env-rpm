#!/bin/bash
# manage sites and site's options 
# set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

delete_site() {
    site_dir=$1
  
    test_directory "$site_dir" || exit 1


    delete_site_mark=N
    delete_site_exe=
    delete_site_limit=3
    delete_site_try=1
    [[ $DEBUG -gt 0 ]] && echo "$POOL_SITES_KERNEL_LIST"
    [[ $DEBUG -gt 0 ]] && echo "$POOL_SITES_LINK_LIST"
    [[ $DEBUG -gt 0 ]] && echo "$POOL_SITES_ERRORS_LIST"


    # try found site in menu
    is_kernel_site=$(echo "$POOL_SITES_KERNEL_LIST" | grep -c ":$site_dir:")
    is_link_site=$(echo "$POOL_SITES_LINK_LIST" | grep -c ":$site_dir:")
    
    # site not found, try test option site with directory
    if [[ ( $is_kernel_site -eq 0 ) && ( $is_link_site -eq 0 ) ]]; then
        site_info=$($bx_sites_script -a status -r $site_dir | grep '^bxSite:status:')
        site_ok=$(echo "$site_info" | grep -c ':error:')
        if [[ $site_ok -eq 0 ]]; then
            site_name="ext_"$(basename $site_dir)
            delete_site_exe="$bx_sites_script -a delete -r $site_dir"
            delete_site_mark=Y
        else

            # delete site without bitrix directory in DocumentRoot
            if [[ $(echo "$POOL_SITES_LINK_LIST" | \
                grep -c "Not found $site_dir/bitrix on the host") ]]; then
                
                # test site info, if we can found nginx and apache config we will delete it
                local site_name=$(basename $site_dir)
                local site_info=$($bx_sites_script -a status --site $site_name --root $site_dir | \
                    grep "^bxSite:configs:$site_name:" | sed -e "s/bxSite:configs:$site_name://")
                local ngx_cfg=$(echo "$site_info" | awk -F ':' '{print $1}')
                if [[ -z $ngx_cfg ]]; then
                    print_message "$CS0101" \
                        "$(get_text "$SM0003" "$site_name")" "" any_key
                    exit
                else
                    local ngx_cfg_enable_dir=$(echo "$site_info" | awk -F':' '{print $4}')
                    local ngx_cfg_available_dir=$(echo "$site_info" | awk -F':' '{print $3}')
                    local ngx_cfg2=$(echo "$site_info" | awk -F':' '{print $2}')
                    local nginx_cfg_http="$ngx_cfg_enable_dir/$ngx_cfg"
                    local nginx_cfg_https="$ngx_cfg_enable_dir/$ngx_cfg2"
                    local apache_cfg=$(echo "$site_info" | awk -F':' '{print $5}')
                    local site_dir=$(echo "$site_info" | awk -F':' '{print $6}')
                    local php_sess_dir=$(echo "$site_info" | awk -F':' '{print $7}')
                    local php_upload_dir=$(echo "$site_info" | awk -F':' '{print $8}')
                    print_color_text "$SM0004"
                    printf "%-20s: %s\n" "$SM0005" "$nginx_cfg_http"
                    printf "%-20s: %s\n" "$SM0006" "$nginx_cfg_https"
                    printf "%-20s: %s\n" "$SM0007" "$apache_cfg"
                    printf "%-20s: %s\n" "$SM0008" "$site_dir"
                    [[ -d $php_sess_dir ]] && \
                        printf "%-20s: %s\n" "$SM0009" "$php_sess_dir"
                    [[ -d $php_upload_dir ]] && \
                        printf "%-20s: %s\n" "$SM0010" "$php_upload_dir"
                    print_message "$SM0011" "" "" delete_it "n"

                    if [[ $(echo $delete_it | grep -iwc "y") -gt 0 ]]; then
                        for file in $nginx_cfg_http $nginx_cfg_https $apache_cfg; do
                            echo -n "$SM0012 "$file
                            rm -f $file && echo "..ok" || "..error"
                        done
                        for dir in $site_dir $php_sess_dir $php_upload_dir; do
                            echo -n "$SM0013 "$dir
                            [[ -d $dir ]] && rm -fr $dir && echo "..ok" || "..error"
                        done
                        /sbin/service nginx reload 1>/dev/null
                        /sbin/service httpd reload 2>/dev/null
                        print_message "$CS0101" \
                            "" "" any_key
                        exit
                    else
                        exit
                    fi
                fi
            else

                print_message "$CS0101" \
                    "$SM0014 $site_dir" \
                    "" any_key
                exit
            fi
        fi

    # site found in the list
    else
        [[ $is_kernel_site -gt 0 ]] && \
            site_name=$(echo "$POOL_SITES_KERNEL_LIST" | \
            grep ":$site_dir:" | awk -F':' '{print $1}')
        [[ $is_link_site -gt 0 ]] && \
            site_name=$(echo "$POOL_SITES_LINK_LIST" | \
            grep ":$site_dir:" | awk -F':' '{print $1}')

        delete_site_exe="$bx_sites_script -a delete -r $site_dir -s $site_name"
        delete_site_mark=Y
    fi

    # test transformer options
    if [[ $is_kernel_site -gt 0 ]]; then
        . $tr_menu_fnc || exit 1
        cache_transfomer_status
        if [[ -n "$TR_INFO" && $TR_DIR == "$site_dir" ]]; then
            print_message "$TRANSF016" \
                "$TRANSF012 $site_dir" "" any_key
            exit
        fi
    fi

    [[ $DEBUG -gt 0 ]] && echo "$delete_site_exe"
    exec_pool_task "$delete_site_exe" "$(get_text "$SM0015" "$site_name")" 

}

# print host menu
menu_delete() {
    menu_delete_00="$SM0201"
    menu_delete_01="   $SM0016"


    SITE_MENU_SELECT=
    until [[ -n "$SITE_MENU_SELECT" ]]; do
        menu_logo="$SM0016"
        print_menu_header

        # menu
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        [[ $POOL_SITE_TASK_LOCK -eq 0 ]] && POOL_SITES_KERNEL_COUNT=

        print_pool_sites
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            menu_list="\n\t$menu_delete_00"
        else
            menu_list="\n\t$menu_delete_01\n\t$menu_delete_00"
        fi
        print_menu

        if [[ $POOL_SITE_TASK_LOCK -eq 1 ]]; then
            print_message "$SM0202" '' '' SITE_MENU_SELECT 0
        else
            print_message "$SM0206" "" "" SITE_MENU_SELECT
        fi

        # process selection
        case "$SITE_MENU_SELECT" in
            "0") exit ;;
            *)   delete_site "$SITE_MENU_SELECT";;
        esac
    
        SITE_MENU_SELECT=
    done
}

menu_delete

