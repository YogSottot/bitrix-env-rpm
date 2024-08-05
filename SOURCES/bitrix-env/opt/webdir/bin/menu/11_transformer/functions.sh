#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_process_script=$BIN_DIR/bx-process
bx_host_script=$BIN_DIR/wrapper_ansible_conf
bx_web_script=$BIN_DIR/bx-sites

submenu_dir=$BIN_DIR/menu/11_transformer
trasformer_menu=$submenu_dir
ansible_web_group=/etc/ansible/group_vars/bitrix-web.yml


site_menu_dir=$BIN_DIR/menu/06_site
site_menu_fnc=$site_menu_dir/functions.sh
. $site_menu_fnc || exit 1


# get_text variables
[[ -f $trasformer_menu/functions.txt ]] && \
    . $trasformer_menu/functions.txt

sites_transformer_status() {
    cache_pool_sites
    
    IFS_BAK=$IFS
    IFS=$'\n'
    SITES_TR=
    # POOL_SITES_KERNEL_LIST - there are list of kernel sites
    # default:sitemanager:kernel:not_installed:vm04:/home/bitrix/www:utf-8:N:N:N:N:::N
    for line in $POOL_SITES_KERNEL_LIST; do
        site_name=$(echo "$line" | awk -F ':' '{print $1}')
        site_dir=$(echo "$line" | awk -F ':' '{print $6}')
        site_status=$(echo "$line" | awk -F':' '{print $4}')
        site_tr=$(echo "$line" | awk -F ':' '{print $14}')
        module_transformer=$(echo "$site_tr" | awk -F';' '{print $1}')
        module_transformercontroller=$(echo "$site_tr" | awk -F';' '{print $2}')

        if [[ $DEBUG -gt 0 ]]; then
            echo "$site_name: $site_dir: $site_status: $module_transformer: $module_transformercontroller"
        fi
        if [[ $module_transformer == 'N' || \
            $module_transformercontroller == 'N' || \
            $site_status != "finished" ]]; then
            continue
        fi

        if [[ -z $SITES_TR ]]; then
            SITES_TR="$site_name:$site_dir:$module_transformer:$module_transformercontroller"
        else
            SITES_TR="$SITES_TR\n$site_name:$site_dir:$module_transformer:$module_transformercontroller"
        fi
    done

    IFS=$IFS_BAK
    IFS_BAK=

}

print_sites_transformer_status() {
    sites_transformer_status

    if [[ -z $SITES_TR ]]; then
       print_message    "$TRANSF210" "$TRANSF209" "" any_key
       exit
    fi

    IFS_BAK=$IFS
    IFS=$'\n'
    print_color_text "$TRANSF009"
    echo $MENU_SPACER
    printf "%-35s | %s\n" \
        "SiteName" "DocumentRoot"
    echo $MENU_SPACER

    for line in $(echo -e "$SITES_TR"); do
        site_name=$(echo "$line" | awk -F':' '{print $1}')
        site_dir=$(echo "$line" | awk -F':' '{print $2}')
        printf "%-35s | %s\n" \
            $site_name $site_dir
    done
    echo $MENU_SPACER
    echo
}

# get status for web servers
# return
# TR_SERVER - transformer server name
# TR_SITE - transformer site
# TR_CHOICE - possible choice for transformer server
get_transformer_status() {
    TR_SERVER=
    TR_SITE=
    TR_DIR=
    TR_CHOICE=

    # get info from ansible configuration
    local info=$($bx_host_script)
    local erro=$(echo "$info" | grep '^error:' | sed -e "s/^error://")
    local mesg=$(echo "$info" | grep '^message:' | sed -e "s/^message://")
    if [[ -n $erro ]]; then
        print_message \
            "$TRANSF010" \
            "$mesg" "" any_key
        exit
    fi

    # host:vm04:192.168.3.36:mgmt,mysql_master_1,transformer,web:1593762477_1HlCHyL4NS:vm04:sitename;/home/bitrix/ext_www/sitename
    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $info; do
        hostname=$(echo "$line" | awk -F':' '{print $2}')
        ipaddr=$(echo "$line" | awk -F':' '{print $3}')
        groups=$(echo "$line" | awk -F':' '{print $4}')

        if [[ $(echo "$groups" | grep -wc "transformer") -gt 0 ]]; then
            TR_SERVER="$hostname"
            TR_SITE="$(echo "$line" | awk -F':' '{print $7}' | \
                awk -F';' '{print $1}')"
            TR_DIR="$(echo "$line" | awk -F':' '{print $7}' | \
                awk -F';' '{print $2}')"
 
        fi
        if [[ $(echo $groups| grep -wc "mgmt") -gt 0  ]]; then
            TR_CHOICE="$hostname"
        fi
    done
    IFS=$IFS_BAK
    IFS_BAK=

    TR_INFO="$TR_SERVER:$TR_SITE:$TR_DIR:$TR_CHOICE"
}

cache_transfomer_status() {
    TR_INFO=
    TR_SERVERS_CACHE=$CACHE_DIR/tr_servers.cache             # cache file
    TR_SERVERS_CACHE_LT=3600                                         # live time for cache file in seconds

    test_cache_file $TR_SERVERS_CACHE $TR_SERVERS_CACHE_LT
    if [[ $? -gt 0 ]]; then
        get_transformer_status
        echo "$TR_INFO" > $TR_SERVERS_CACHE
    else
        TR_INFO=$(cat $TR_SERVERS_CACHE)

        TR_SERVER=$(echo "$TR_INFO" | awk -F':' '{print $1}')
        TR_SITE=$(echo "$TR_INFO" | awk -F':' '{print $2}')
        TR_DIR=$(echo "$TR_INFO" | awk -F':' '{print $3}')
        TR_CHOICE=$(echo "$TR_INFO" | awk -F':' '{print $4}')
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "TR_SERVER=$TR_SERVER"
        echo "TR_SITE=$TR_SITE"
        echo "TR_DIR=$TR_DIR"
        echo "TR_CHOICE=$TR_CHOICE"
    fi
}

print_transformer_status() {
    cache_transfomer_status
    
    if [[ -z $TR_SERVER ]]; then
        echo "$TRANSF011"
        return 1
    fi

    print_color_text "$TRANSF012"
    echo $MENU_SPACER
    printf "%-17s | %20s| %s\n" \
        "Hostname" "SiteName" "DocumentRoot"
    echo $MENU_SPACER

     printf "%-17s | %20s| %s\n" \
        "$TR_SERVER" "$TR_SITE" "$TR_DIR"
        
    echo $MENU_SPACER
    echo
}
