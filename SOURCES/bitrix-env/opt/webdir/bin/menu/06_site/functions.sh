#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

ansible_web_group=/etc/ansible/group_vars/bitrix-web.yml

bx_sites_script=$BIN_DIR/bx-sites
sites_menu=$BIN_DIR/menu/06_site

mysql_menu_dir=$BIN_DIR/menu/03_mysql
mysql_menu_fnc=$mysql_menu_dir/functions.sh

. $mysql_menu_fnc || exit 1

push_menu_dir=$BIN_DIR/menu/10_push
push_menu_fnc=$push_menu_dir/functions.sh

. $push_menu_fnc || exit 1

tr_menu_dir=$BIN_DIR/menu/11_transformer
tr_menu_fnc=$tr_menu_dir/functions.sh

# get_text variables
[[ -f $sites_menu/functions.txt   ]] && . $sites_menu/functions.txt

# check mysql password and client config before start site creation
check_site_options() {
    # test csync or lsyncd
    WEB_CLUSTER_TYPE=$(cat $ansible_web_group | grep -v "^$\|^#" | egrep '^fstype: ' | awk -F':' '{print $2}' | sed -e "s/\s\+//g")
    if [[ -z $WEB_CLUSTER_TYPE ]];
    then
        WEB_CLUSTER_STATUS=$(cat $ansible_web_group | grep -v "^$\|^#" | egrep '^cluster_web_configure: ' | awk -F':' '{print $2}' | sed -e "s/\s\+//g")
        if [[ $WEB_CLUSTER_STATUS == "enable" ]];
        then
            WEB_CLUSTER_TYPE=csync
        else
            WEB_CLUSTER_TYPE=lsync
        fi
    fi

    # test push server status
    cache_push_servers_status

    # test mysql passwords
    cache_mysql_servers_status

    [[ $DEBUG -gt 0 ]] && echo "MYSQL=$MYSQL_SERVERS"
    MASTER_NAME=$(echo "$MYSQL_SERVERS" | grep ":master:" | awk -F':' '{print $1}')
    MASTER_ROOT_PASSWD=$(echo "$MYSQL_SERVERS" | grep ":master:" | awk -F':' '{print $8}')
    MASTER_CLIENT_CNF=$(echo "$MYSQL_SERVERS" | grep ":master:" | awk -F':' '{print $9}')
    if [[ $MASTER_ROOT_PASSWD != "Y" ]];
    then
        print_color_text "Found MySQL service with empty root password: $MASTER_NAME"
        print_color_text "You can fix this by using second item in the MySQL menu." blue
        return 10
    fi

    if [[ $MASTER_CLIENT_CNF != "Y" ]];
    then
        print_color_text "Not found MySQL client config: $MASTER_NAME"
        print_color_text "You can fix this by using second item in the MySQL menu." blue
        return 11
    fi
}

# list all sites
# fill out
# POOL_SITES_KERNEL_LIST        - kernel sites with web access
# POOL_SITES_KERNEL_COUNT       - number of kernel sites with web access
# POOL_SITES_LINK_LIST          - link sites
# POOL_SITES_LINK_COUNT         - links count
# POOL_SITES_ERRORS_LIST        - sites with errors
# POOL_SITES_ERRORS_COUNT       - count sites with errors
get_pool_sites() {
    _process_inf=$($bx_sites_script -a list)
    _process_err=$(echo "$_process_inf" | grep '^error:' | sed -e "s/^error://")
    _process_msg=$(echo "$_process_msg" | grep '^message:' | sed -e "s/^message://")

    if [[ -n "$_process_err" ]];
    then
        POOL_SITES_KERNEL_COUNT=0
        POOL_SITES_LINK_COUNT=0
        POOL_SITES_ERRORS_COUNT=0
    else
        POOL_SITES_KERNEL_LIST=$(echo "$_process_inf" | grep '^bxSite:general' | sed -e "s/^bxSite:general://" | grep ':\(kernel\|ext_kernel\):' )
        POOL_SITES_LINK_LIST=$(echo "$_process_inf" | grep '^bxSite:general' | sed -e "s/^bxSite:general://" | grep ':link:' )
        POOL_SITES_ERRORS_LIST=$(echo "$_process_inf" | grep '^bxSite:status' | sed -e "s/^bxSite:status://" | grep ':error:')
        POOL_SITES_KERNEL_COUNT=$(echo "$POOL_SITES_KERNEL_LIST" | grep -vc '^$')
        POOL_SITES_LINK_COUNT=$(echo "$POOL_SITES_LINK_LIST" | grep -vc '^$')
        POOL_SITES_ERRORS_COUNT=$(echo "$POOL_SITES_ERRORS_LIST" | grep -vc '^$')
    fi
}

cache_pool_sites() {
    POOL_SITES_CACHE_LT=${1:-600}
    POOL_SITES_KERNEL_LIST=
    POOL_SITES_LINK_LIST=
    POOL_SITES_ERRORS_LIST=

    POOL_SITES_KERNEL_CACHE=$CACHE_DIR/sites_kernel.cache
    POOL_SITES_LINK_CACHE=$CACHE_DIR/sites_links.cache
    POOL_SITES_ERRORS_CACHE=$CACHE_DIR/sites_errors.cache

    test_cache_file $POOL_SITES_KERNEL_CACHE $POOL_SITES_CACHE_LT
    pool_kernel_cache=$?

    test_cache_file $POOL_SITES_LINK_CACHE $POOL_SITES_CACHE_LT
    pool_link_cache=$?

    test_cache_file $POOL_SITES_ERRORS_CACHE $POOL_SITES_CACHE_LT
    pool_error_cache=$?

    if [[ ( $pool_kernel_cache -gt 0 ) || ( $pool_link_cache -gt 0 ) || ( $pool_error_cache -gt 0 ) ]];
    then
        get_pool_sites
        echo "$POOL_SITES_KERNEL_LIST" > $POOL_SITES_KERNEL_CACHE
        echo "$POOL_SITES_LINK_LIST" > $POOL_SITES_LINK_CACHE
        echo "$POOL_SITES_ERRORS_LIST" > $POOL_SITES_ERRORS_CACHE
    else
        POOL_SITES_KERNEL_LIST=$(cat $POOL_SITES_KERNEL_CACHE)
        POOL_SITES_LINK_LIST=$(cat $POOL_SITES_LINK_CACHE)
        POOL_SITES_ERRORS_LIST=$(cat $POOL_SITES_ERRORS_CACHE)

        POOL_SITES_KERNEL_COUNT=$(echo "$POOL_SITES_KERNEL_LIST" | grep -vc '^$')
        POOL_SITES_LINK_COUNT=$(echo "$POOL_SITES_LINK_LIST" | grep -vc '^$')
        POOL_SITES_ERRORS_COUNT=$(echo "$POOL_SITES_ERRORS_LIST" | grep -vc '^$')
    fi
}

# Format database type
format_db_type() {
    local db_type="$1"
    
    case "$db_type" in
        "mysql")
            echo "MySQL"
            ;;
        "pgsql")
            echo "PostgreSQL"
            ;;
        *)
            echo "$db_type"
            ;;
    esac
}

# print error site info
print_pool_sites_error() {
    [[ -z "$POOL_SITES_ERRORS_COUNT" ]] && cache_pool_sites

    if [[ $POOL_SITES_ERRORS_COUNT -gt 0 ]];
    then
        print_color_text "Found $POOL_SITES_ERRORS_COUNT sites with errors:" red
        echo $MENU_SPACER
        printf "%-15s | %-15s | %s\n" "SiteName" "ErrorN" "ErrorMessage"
        echo $MENU_SPACER
        IFS_BAK=$IFS
        IFS=$'\n'
        for line in $POOL_SITES_ERRORS_LIST; do
            err_site_name=$(echo "$line" | awk -F':' '{print $1}')
            err_site_code=$(echo "$line" | awk -F"'" '{print $2}' | awk -F'|' '{print $1}')
            err_site_mess=$(echo "$line" | awk -F"'" '{print $2}' | awk -F'|' '{print $2}')
            printf "%-15s | %-15s | %s\n" "$err_site_name" "$err_site_code" "$err_site_mess"
        done
        IFS=$IFS_BAK
        IFS_BAK=
        echo $MENU_SPACER
        print_message "Press ENTER for exit:" "" "" any_key
    else
        echo "Not found sites with errors"
        print_message "Press ENTER for exit:" "" "" any_key
    fi
}

get_all_sites_list() {
    cache="${1}"
    exclude="${2:-ext_kernel}"

    cache_pool_sites $cache
    if [[ $exclude == "ext_kernel" ]];
    then
        POOL_SITES_KERNEL_LIST=$(echo "$POOL_SITES_KERNEL_LIST" | grep -v ':ext_kernel:')
    fi

    if [[ $exclude == "link" ]];
    then
        POOL_SITES_LIST="$POOL_SITES_KERNEL_LIST"
    else
        POOL_SITES_LIST="$POOL_SITES_KERNEL_LIST
$POOL_SITES_LINK_LIST"
    fi

    POOL_SITES_KERNEL_COUNT=$(echo "$POOL_SITES_KERNEL_LIST" | grep -vc '^$')
    POOL_SITES_COUNT=$(echo "$POOL_SITES_LIST" | grep -vc '^$')
}

# print info for installed sites
# fill out variable
# SITES_LIST_WITH_NUMBER
print_pool_sites() {
    _filter_by_db=$1
    _only_kernel=$2

    cache_pool_sites
    [[ -z $_only_kernel ]] && _only_kernel="N"

    echo_db_kernel=$_filter_by_db
    [[ -z "$_echo_db_kernel" ]] && _echo_db_kernel="not filtered"

    # additional variables for filter by DBname
    _pool_filtered_kernel=$POOL_SITES_KERNEL_LIST
    _pool_filtered_link=$POOL_SITES_LINK_LIST

    if [[ -n "$_filter_by_db" ]];
    then
        _pool_filtered_kernel=$(echo "$_pool_filtered_kernel" | grep ":$_filter_by_db:")
        _pool_filtered_link=$(echo "$_pool_filtered_link" | grep ":$_filter_by_db:")
    fi
    _pool_filtered_kernel_count=$(echo "$_pool_filtered_kernel" | grep -vc '^$')
    _pool_filtered_link_count=$(echo "$_pool_filtered_link" | grep -vc '^$')
    SITES_LIST_WITH_NUMBER=""

    if [[ $_pool_filtered_kernel_count -gt 0 ]];
    then
        _db_list=""
        print_color_text "Found $_pool_filtered_kernel_count kernel sites:" blue
        echo $MENU_SPACER
        #printf "%3s| %-15s | %-11s | %-15s | %15s | %10s | %1s | %1s | %s\n" "ID" "SiteName" "DBType" "dbName" "Status" "Type" "S" "C" "DocumentRoot"
        printf "%3s| %-15s | %-11s | %-15s | %15s | %10s | %1s | %s\n" "ID" "SiteName" "DBType" "dbName" "Status" "Type" "C" "DocumentRoot"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'
        COUNT=1
        for line in $_pool_filtered_kernel
        do
            # default:sitemanager:kernel:finished:srv01.ksh.bx:/home/bitrix/www:utf-8:Y:N
            _site_id=$(echo "$line" | awk -F':' '{print $1}')  # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')  # dbname
            _site_tp=$(echo "$line" | awk -F':' '{print $3}')  # site type
            _site_st=$(echo "$line" | awk -F':' '{print $4}')  # status site installation
            _site_sr=$(echo "$line" | awk -F':' '{print $5}')  # full servername
            _site_rt=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_ch=$(echo "$line" | awk -F':' '{print $7}')  # charset
            #_site_sc=$(echo "$line" | awk -F':' '{print $8}')  # scale - old version
            _site_cl=$(echo "$line" | awk -F':' '{print $9}')  # cluster
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}')  # db_type (последнее поле)
            #printf "%3d| %-15s | %-11s | %-15s | %15s | %10s | %1s | %1s | %s\n" "$COUNT" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_st" "$_site_tp" "$_site_sc" "$_site_cl" "$_site_rt"
            printf "%3d| %-15s | %-11s | %-15s | %15s | %10s | %1s | %s\n" "$COUNT" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_st" "$_site_tp" "$_site_cl" "$_site_rt"
            _db_list=$_db_list"$_site_db
"
            SITES_LIST_WITH_NUMBER=$SITES_LIST_WITH_NUMBER"$COUNT:$_site_id:$_site_db:$_site_st:$_site_tp:$_site_rt:$_site_sr
"
            COUNT=$(($COUNT+1))
        done

        IFS=$IFS_BAK
        IFS_BAK=
        echo $MENU_SPACER

        _db_list=$(echo "$_db_list" | sed -e 's/\s\+$//' | sort | uniq)

        if [[ ( $_pool_filtered_link_count -gt 0 ) && ( "$_only_kernel" == "N" ) ]];
        then
            for _db_found in $_db_list; do
                _db_count=$(echo "$_pool_filtered_link" | grep -c ":$_db_found:")

                if [[ $_db_count -gt 0 ]];
                then
                    print_color_text "$_db_found: $_db_count link sites" green

                    _pool_db_links=$(echo "$_pool_filtered_link" | grep ":$_db_found:")
                    echo $MENU_SPACER
                    printf "%3s| %-15s | %-11s | %-15s | %15s | %10s | %s\n" "ID" "SiteName" "DBType" "dbName" "Status" "Type" "DocumentRoot"
                    echo $MENU_SPACER
                    IFS_BAK=$IFS
                    IFS=$'\n'
                    for line in $_pool_db_links
                    do
                        _site_id=$(echo "$line" | awk -F':' '{print $1}')  # short name for site
                        _site_db=$(echo "$line" | awk -F':' '{print $2}')  # dbname
                        _site_tp=$(echo "$line" | awk -F':' '{print $3}')  # site type
                        _site_st=$(echo "$line" | awk -F':' '{print $4}')  # status site installation
                        _site_sr=$(echo "$line" | awk -F':' '{print $5}')  # full servername
                        _site_rt=$(echo "$line" | awk -F':' '{print $6}')  # document root
                        _site_db_type=$(echo "$line" | awk -F':' '{print $NF}')  # db_type (последнее поле)
                        printf "%3d| %-15s | %-11s | %-15s | %15s | %10s | %s\n" "$COUNT" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_st" "$_site_tp" "$_site_rt"
                        SITES_LIST_WITH_NUMBER=$SITES_LIST_WITH_NUMBER"$COUNT:$_site_id:$_site_db:$_site_st:$_site_tp:$_site_rt:$_site_sr
"
                        COUNT=$(($COUNT+1))
                    done
                    IFS_BAK=$IFS
                    IFS=$'\n'
                    echo $MENU_SPACER
                fi
            done
        fi
        print_color_text "Note:" blue
        #echo "S - scale module   (Y = installed, N = not installed)"
        echo "C - cluster module (Y = installed, N = not installed)"
        echo
    else
        echo "Not found installed sites in the pool"
    fi
}

# get site information
get_site_info() {
    site_name=$1
    site_root=$2
    type_info=$3

    [[ -z $_type_info ]] && _type_info=general
    site_info_inf=$($bx_sites_script -a status -s $site_name -r $site_root)
    site_info_err=$(echo "$site_info_inf" | grep "^error:" | sed -e 's/error://')
    site_info_msg=$(echo "$site_info_inf" | grep "^message:" | sed -e 's/message://')
    site_info_dat=$(echo "$site_info_inf" | grep "^bxSite:$type_info:" | sed -e "s/bxSite://")
    if [[ -n "$site_info_err" ]];
    then
        print_message "Press ENTER for exit" "$site_info_msg" "" any_key
        exit
    fi
}

# print info about services enabled on site in cron
print_site_list_point_cron() {
    cache_pool_sites
    if [[ $POOL_SITES_KERNEL_COUNT -gt 0 ]];
    then
        print_color_text "Found $POOL_SITES_KERNEL_COUNT kernel sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %-15s | %15s | %5s | %s\n" "SiteName" "DBType" "dbName" "Status" "Cron" "DocumentRoot"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'
        POOL_SITES_CRON_SERVICES_LIST=""
        for line in $POOL_SITES_KERNEL_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8
            _site_id=$(echo "$line" | awk -F':' '{print $1}')  # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')  # dbname
            _site_st=$(echo "$line" | awk -F':' '{print $4}')  # status site installation
            _site_root=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}') 
            _site_info=$($bx_sites_script -a status --site $_site_id -r $_site_root | grep ':cron:' | sed -e 's/^bxSite:cron://')
            # ext_share:dbcp:enable:/etc/cron.d/bx_dbcp
            _site_cron=$(echo "$_site_info" | awk -F':' '{print $3}' | sed -e 's/enable/Y/;s/disable/N/;')
            printf "%-15s | %-11s | %-15s | %15s | %5s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_st" "$_site_cron" "$_site_root"
        done
        IFS_BAK=$IFS
        IFS=$'\n'
        echo $MENU_SPACER
    else
        print_color_text "Not found kernel sites on the server" blue
    fi
}

# fill out COMPOSITE_ERROR
get_composite_errors() {
    local process_inf=$($bx_sites_script -a list)
    # bxSite:composite_error:default:Fatal error: Call to undefined function json_encode() in /vagrant/env/opt/webdir/bin/composite.php on line 14
    COMPOSITE_ERRORS=$(echo "$process_inf" | grep -w composite_error)
    COMPOSITE_ERRORS_MESSAGE=
    COMPOSITE_ERRORS_CNT=0
    if [[ -n "$COMPOSITE_ERRORS" ]];
    then
        IFS_BAK=$IFS
        IFS=$'\n'
        for error in $COMPOSITE_ERRORS; do
            site_name=$(echo "$error" | awk -F':' '{print $3}')
            error_message=$(echo "$error" | sed -e "s/bxSite:composite_error:$site_name://")
            COMPOSITE_ERRORS_MESSAGE="
-> Site $site_name: $error_message"

            COMPOSITE_ERRORS_CNT=$(( $COMPOSITE_ERRORS_CNT+1 ))
        done
        IFS=$IFS_BAK
        IFS_BAK=

        return 1
    fi
    return 0
}

# print info about composite settings in nginx configs
print_site_list_point_composite() {
    get_all_sites_list 1

    if [[ $POOL_SITES_COUNT -gt 0 ]];
    then
        print_color_text "Found $POOL_SITES_COUNT sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %-15s | %10s | %9s | %5s | %s\n" "SiteName" "DBType" "dbName" "Type" "Composite" "Nginx" "Storage"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'
        for line in $POOL_SITES_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8:Y:Y:Y:N:files
            _site_id=$(echo "$line" | awk -F':' '{print $1}')   # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')   # dbname
            _site_type=$(echo "$line" | awk -F':' '{print $3}') # type: kernel, ext_kernel
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}')
            composite_status=$(echo "$line" | awk -F':' '{print $10}')
            nginx_composite=$(echo "$line" | awk -F':' '{print $11}')
            composite_storage=$(echo "$line" | awk -F':' '{print $12}')
            printf "%-15s | %-11s | %-15s | %10s | %9s | %5s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_type" "$composite_status" "$nginx_composite" "$composite_storage"
        done
        IFS_BAK=$IFS
        IFS=$'\n'
        echo $MENU_SPACER

        get_composite_errors
        get_composite_errors_rtn=$?
        if [[ $get_composite_errors_rtn -gt 0 ]];
        then
            print_color_text "$COMPOSITE_ERRORS_CNT errors while parsing composite config:" red
            echo "$COMPOSITE_ERRORS_MESSAGE"
        fi
    else
        print_color_text "Not sites on the server" blue
    fi
}

# print info about enable or disable https
print_site_list_point_https() {
    get_all_sites_list

    if [[ $POOL_SITES_COUNT -gt 0 ]];
    then
        print_color_text "There are $POOL_SITES_COUNT sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %-15s | %10s | %1s | %-20s | %s\n" "SiteName" "DBType" "dbName" "Type" "S" "Certificate" "Key"
        echo $MENU_SPACER
        IFS_BAK=$IFS
        IFS=$'\n'
        for line in $POOL_SITES_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8
            _site_id=$(echo "$line" | awk -F':' '{print $1}')   # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')   # dbname
            _site_type=$(echo "$line" | awk -F':' '{print $3}') # type: kernel, ext_kernel
            _site_st=$(echo "$line" | awk -F':' '{print $4}')   # status site installation
            _site_root=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}') 
            _site_info=$($bx_sites_script -a status --site $_site_id -r $_site_root | grep ':https:' | sed -e 's/^bxSite:https://')
            # default:sitemanager:disable:/etc/nginx/ssl/cert.pem:/etc/nginx/ssl/cert.pem:/etc/nginx/bx/conf/ssl.conf
            https_cert=$(echo "$_site_info" | awk -F':' '{print $4}' | sed -e "s:/etc/nginx/::")
            https_key=$(echo "$_site_info" | awk -F':' '{print $5}' | sed -e "s:/etc/nginx/::")
             _https_enable=$(echo "$_site_info" | awk -F':' '{print $3}' | sed -e 's/enable/Y/;s/disable/N/;' )
            printf "%-15s | %-11s | %-15s | %10s | %1s | %-20s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_type" "$_https_enable" "$https_cert" "$https_key"
        done
        IFS=$IFS_BAK
        IFS_BAK=
        echo $MENU_SPACER
        print_color_text "Note:" blue
        echo "S - Only HTTPS access to the server (N = turned off, Y = turned on)"
        echo
    else
        print_color_text "Not sites on the server" blue
    fi

    # push server need certificate
    cache_push_servers_status
    if [[ $PUSH_SERVERS_CNT -eq 0 ]];
    then
        PUSH_STREAM_SERVER=$(echo "$PUSH_SERVERS" | awk -F':' '/Nginx-PushStreamModule/{print $2}')
        PUSH_SSL_CONFIG=/etc/nginx/bx/conf/ssl-push.conf

        if [[ -n $PUSH_STREAM_SERVER ]];
        then
            PUSH_SSL=Unknown
            PUSH_KEY=Unknown
            PUSH_TYPE=Unknown
            PUSH_SSL_FILE=$PUSH_SSL_CONFIG

            if [[ ( -f $PUSH_SSL_CONFIG ) && ( $(file $PUSH_SSL_CONFIG | grep -c "symbolic link to") -gt 0 ) ]];
            then
                PUSH_SSL_FILE=$(file $PUSH_SSL_CONFIG | grep  "symbolic link to" | awk '{print $NF}' | sed -e "s/[\`']//g")
                DIR_PUSH_SSL_FILE=$(dirname $PUSH_SSL_FILE)
                BN_PUSH_SSL_FILE=$(basename $PUSH_SSL_FILE)
                [[ $DIR_PUSH_SSL_FILE == "." ]] && DIR_PUSH_SSL_FILE=/etc/nginx/bx/conf
                PUSH_SSL_FILE="${DIR_PUSH_SSL_FILE}/${BN_PUSH_SSL_FILE}"
            fi

            if [[ ${PUSH_SSL_FILE} == '/etc/nginx/bx/conf/ssl.conf' ]];
            then
                PUSH_SSL=/etc/nginx/ssl/cert.pem
                PUSH_KEY=/etc/nginx/ssl/cert.pem
                PUSH_TYPE=Default
            else
                PUSH_SSL=$(grep -v '^$\|^#' $PUSH_SSL_FILE | grep 'ssl_certificate\s\+' | awk '{print $2}' | sed -e 's/;$//')
                PUSH_KEY=$(grep -v '^$\|^#' $PUSH_SSL_FILE | grep 'ssl_certificate_key\s\+' | awk '{print $2}' | sed -e 's/;$//')
                PUSH_TYPE=Custom
            fi

            print_color_text "Found push-configuration:" blue
            echo $MENU_SPACER
                printf "%-15s | %-30s | %s\n" "SiteName" "Certificate" "Key"
            echo $MENU_SPACER
                printf "%-15s | %-30s | %s\n" "push-server" "$PUSH_SSL" "$PUSH_KEY"
            echo $MENU_SPACER
        fi
    fi
}

# print info about services email information
print_site_list_point_email() {
    get_all_sites_list

    if [[ $POOL_SITES_COUNT -gt 0 ]];
    then
        print_color_text "Found $POOL_SITES_COUNT sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %-15s | %5s | %15s | %5s | %s\n" "SiteName" "DBType" "dbName" "Email" "Server" "TLS" "From"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'
        for line in $POOL_SITES_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8
            _site_id=$(echo "$line" | awk -F':' '{print $1}')  # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')  # dbname
            _site_st=$(echo "$line" | awk -F':' '{print $4}')  # status site installation
            _site_root=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}')
            _site_info=$($bx_sites_script -a status --site $_site_id -r $_site_root | grep ':email:' | sed -e 's/^bxSite:email://')
            # cp.ksh.bx:dbcp:cp.ksh.bx:bob@example.org:192.168.0.25:26:bob@example.org:*************:on
            _site_email=$(echo "$_site_info" | awk -F':' '{print $4}')
            _email_serv=$(echo "$_site_info" | awk -F':' '{print $5}')
            _email_port=$(echo "$_site_info" | awk -F':' '{print $6}')
            _email_tls=$(echo "$_site_info" | awk -F':' '{print $9}')
            _email_status=N
            [[ -n "$_site_email" ]] && _email_status=Y
            [[ -n "$_email_port" ]] && _email_serv="$_email_serv:$_email_port"
            printf "%-15s | %-11s | %-15s | %5s | %15s | %5s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_email_status" "$_email_serv" "$_email_tls" "$_site_email"
        done
        IFS_BAK=$IFS
        IFS=$'\n'
        echo $MENU_SPACER
    else
        print_color_text "Not sites on the server" blue
    fi
}

# print info about services backup
print_site_list_point_backup() {
    cache_pool_sites
    if [[ $POOL_SITES_KERNEL_COUNT -gt 0 ]];
    then
        print_color_text "Found $POOL_SITES_KERNEL_COUNT kernel sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %-15s | %4s | %15s | %18s | %s\n" "SiteName" "DBType" "dbName" "Back" "CronTime" "LastBackup" "BackupDir"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'
        POOL_SITES_CRON_SERVICES_LIST=""
        for line in $POOL_SITES_KERNEL_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8
            _site_id=$(echo "$line" | awk -F':' '{print $1}')  # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')  # dbname
            _site_root=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}')
            _site_info=$($bx_sites_script -a status --site $_site_id -r $_site_root | grep ':backup:' | sed -e 's/^bxSite:backup://')
            # default:sitemanager:enable:v5:/home/bitrix/backup/archive:10:23:*:*:*
            _site_backup=$(echo "$_site_info" | awk -F':' '{print $3}' | sed -e 's/enable/Y/;s/disable/N/;')
            if [[ "$_site_backup" == "Y" ]];
            then
                _backup_dir=$(echo "$_site_info" | awk -F':' '{print $5}')
                _backup_cron=$(echo "$_site_info" | awk -F':' '{printf "%s:%s:%s:%s:%s",$6,$7,$8,$9,$10}')
                list_archive=$(find $_backup_dir -name "www_backup_${_site_db}*.tar.gz")
                _backup_last=
                if [[ -n "$list_archive" ]];
                then
                    last_archive_time=0
                    for file in $list_archive; do
                        mtime=$(stat -c %Y $file)
                        [[ $mtime -gt $last_archive_time ]] && last_archive_time=$mtime
                    done
                    _backup_last=$(date -d @$last_archive_time +"%d/%m/%Y %H:%M")
                fi
            else
                _backup_dir=
                _backup_cron=
                _backup_last=
            fi
            printf "%-15s | %-11s | %-15s | %4s | %15s | %18s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_backup" "$_backup_cron" "$_backup_last" "$_backup_dir"
        done
        IFS_BAK=$IFS
        IFS=$'\n'
        echo $MENU_SPACER
    else
        print_color_text "Not found kernel sites on the server" blue
    fi
}

# print info about services xmppd and smtpd
print_site_list_point_cronservices() {
    cache_pool_sites
    if [[ $POOL_SITES_KERNEL_COUNT -gt 0 ]];
    then
        print_color_text "Found $POOL_SITES_KERNEL_COUNT kernel sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %-15s | %10s | %10s | %s\n" "SiteName" "DBType" "dbName" "XMMPD" "SMTPD" "DocumentRoot"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'
        POOL_SITES_CRON_SERVICES_LIST=""
        for line in $POOL_SITES_KERNEL_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8
            _site_id=$(echo "$line" | awk -F':' '{print $1}')  # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')  # dbname
            _site_root=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}')
            _site_info=$($bx_sites_script -a status --site $_site_id -r $_site_root | grep ':cron_services:' | sed -e 's/^bxSite:cron_services://')
            # ext_www:sitemanager:enabled:smtpd
            _site_cron=$(echo "$_site_info" | awk -F':' '{print $3}' | sed -e 's/enabled/Y/;s/disabled/N/;')
            _site_xmmpd=N
            _site_smtpd=N
            if [[ "$_site_cron" == "Y" ]];
            then
                [[ $(echo "$_site_info" | awk -F':' '{print $4}' | grep -wc 'xmppd') -gt 0 ]] && _site_xmmpd=Y
                [[ $(echo "$_site_info" | awk -F':' '{print $4}' | grep -wc 'smtpd') -gt 0 ]] && _site_smtpd=Y
            fi
            printf "%-15s | %-11s | %-15s | %10s | %10s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_xmmpd" "$_site_smtpd" "$_site_root"
        done
        IFS_BAK=$IFS
        IFS=$'\n'
        echo $MENU_SPACER
    else
        print_color_text "Not found kernel sites on the server" blue
    fi
}

# get information about server in domain or not
# fill out NTLM_STATUS
server_ntlm_status() {
    skip_print=$1
    NTLM_STATUS=

    # NTLMStatus:not_configured::::::
    _ntlm_info=$($bx_sites_script -a ntlm_status)
    _ntlm_status=$(echo "$_ntlm_info" | grep -w 'NTLMStatus' | awk -F':' '{print $2}')

    if [[ -z "$skip_print" ]];
    then
        if [[ "$_ntlm_status" == "configured" ]];
        then
            _ntlm_domain=$(echo "$_ntlm_info" | grep -w 'NTLMStatus' | awk -F':' '{print $3}')
            _ntlm_ldap=$(echo "$_ntlm_info" | grep -w 'NTLMStatus' | awk -F':' '{printf "%s:%s",$4,$5}')
            _ntlm_realm=$(echo "$_ntlm_info" | grep -w 'NTLMStatus' | awk -F':' '{print $6}')
            _ntlm_kdc=$(echo "$_ntlm_info" | grep -w 'NTLMStatus' | awk -F':' '{print $7}')
            _ntlm_offset=$(echo "$_ntlm_info" | grep -w 'NTLMStatus' | awk -F':' '{print $8}')
            print_color_text "                 NTLM auth already configured:" green
            echo $MENU_SPACER
            printf "\t\t%-15s: %s\n" " Domain" "$_ntlm_domain"
            printf "\t\t%-15s: %s\n" " LDAP Server" "$_ntlm_ldap"
            printf "\t\t%-15s: %s\n" " Realm" "$_ntlm_realm"
            printf "\t\t%-15s: %s\n" " KDC" "$_ntlm_kdc"
            printf "\t\t%-15s: %s\n" " TimeOffset" "$_ntlm_offset"
            echo $MENU_SPACER
        else
            print_color_text "                 NTLM auth does't configured on the server $(hostname)" blue
        fi
    fi
    NTLM_STATUS=$_ntlm_status
}

# print info about ntlm
# NONTLM_SITES - sites that not use NTLM
print_site_list_point_ntlm() {
    cache_pool_sites
    NONTLM_SITES=         # sites which doesn't use NTLM; enable rewrite for NTLM auth is enable
    NTLM_SITES=           # opposite one
    if [[ $POOL_SITES_KERNEL_COUNT -gt 0 ]];
    then
        print_color_text "                 Found $POOL_SITES_KERNEL_COUNT kernel sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %-15s | %7s | %7s | %8s | %s\n" "SiteName" "DBType" "dbName" "LDAPMod" "UseNTLM" "LDAPAuth" "DocumentRoot"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'
        POOL_SITES_CRON_SERVICES_LIST=""
        for line in $POOL_SITES_KERNEL_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8
            _site_id=$(echo "$line" | awk -F':' '{print $1}')  # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')  # dbname
            _site_root=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}') 
            _site_info=$($bx_sites_script -a status --site $_site_id -r $_site_root | grep ':ntlm:' | sed -e 's/^bxSite:ntlm://')
            # default:sitemanager:N:N:Y
            # option: bitrixvm_auth_support
            site_ntlm_bv=$(echo "$_site_info" | awk -F':' '{print $3}')
            # option: use_ntlm
            site_ntlm_use=$(echo "$_site_info" | awk -F':' '{print $4}')
            site_ldap_module=$(echo "$_site_info" | awk -F':' '{print $5}')
            printf "%-15s | %-11s | %-15s | %7s | %7s | %8s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$site_ldap_module" "$site_ntlm_use" "$site_ntlm_bv" "$_site_root"
            if [[ $site_ntlm_bv == "N" ]];
            then
                NONTLM_SITES=$NONTLM_SITES"$_site_id:$_site_db:$_site_root:$site_ntlm_bv:$site_ntlm_use:$site_ldap_module
"
            else
                NTLM_SITES=$NTLM_SITES"$_site_id:$_site_db:$_site_root:$site_ntlm_bv:$site_ntlm_use:$site_ldap_module
"
            fi
        done
        IFS_BAK=$IFS
        IFS=$'\n'
        echo $MENU_SPACER
    else
        print_color_text "                 Not found kernel sites on the server" blue
    fi
}

# print info about site options
print_site_list_point_options() {
    get_all_sites_list

    if [[ $POOL_SITES_COUNT -gt 0 ]];
    then
        print_color_text "Found $POOL_SITES_COUNT sites:" blue
        echo $MENU_SPACER
        printf "%-15s | %-11s | %10s | %4s | %4s | %4s | %15s | %s\n" "SiteName" "DBType" "dbName" "Type" "IGA" "NCSS" "NCTF" "DCTF"
        # ignore_client_abort - IGA
        # nginx_custom_site_settings - NCSS
        # nginx_custom_temp_files - NCTF
        # dbconn_temp_files - DCTF
        echo $MENU_SPACER
        IFS_BAK=$IFS
        IFS=$'\n'
        for line in $POOL_SITES_LIST; do
            # default:sitemanager:kernel:finished:shop.ksh.bx:/home/bitrix/www:utf-8
            _site_id=$(echo "$line" | awk -F':' '{print $1}')   # short name for site
            _site_db=$(echo "$line" | awk -F':' '{print $2}')   # dbname
            _site_type=$(echo "$line" | awk -F':' '{print $3}') # type: kernel, ext_kernel
            _site_st=$(echo "$line" | awk -F':' '{print $4}')   # status site installation
            _site_root=$(echo "$line" | awk -F':' '{print $6}')  # document root
            _site_db_type=$(echo "$line" | awk -F':' '{print $NF}')
            _site_all_info=$($bx_sites_script -a status --site $_site_id -r $_site_root)
            _site_configs=$(echo "$_site_all_info" | grep 'bxSite:configs:' | sed -e 's/^bxSite:configs://')
            _site_custom=$(echo "$_site_all_info" | grep 'bxSite:custom_options:' | sed -e 's/^bxSite:custom_options://')
            #default:s1.conf:ssl.s1.conf:/etc/nginx/bx/site_avaliable:/etc/nginx/bx/site_enabled:/etc/httpd/bx/conf/default.conf:/home/bitrix/www:/tmp/php_sessions/www:/tmp/php_upload/www:off
            # bxSite:custom_options:sitename.bitrix:on:on:/home/bitrix/.bx_temp/dbksh770
            _proxy_ignore_client_abort=$(echo "$_site_configs" | awk -F':' '{print $10}')
            _nginx_custom_settings=$(echo "$_site_custom" | awk -F':' '{print $2}')
            _nginx_bx_temp_files_dir_conf=$(echo "$_site_custom" | awk -F':' '{print $3}')
            _dbconn_bx_temp_files_dir=$(echo "$_site_custom" | awk -F':' '{print $4}' | sed -e "s:/home/bitrix/.bx_temp/::")
            printf "%-15s | %-11s | %-10s | %4s | %4s | %4s | %15s | %s\n" "$_site_id" "$(format_db_type $_site_db_type)" "$_site_db" "$_site_type" "$_proxy_ignore_client_abort" "$_nginx_custom_settings" "$_nginx_bx_temp_files_dir_conf" "$_dbconn_bx_temp_files_dir"
        done
        IFS_BAK=$IFS
        IFS=$'\n'
        echo $MENU_SPACER
        echo $SM0143
        echo "$SM0144"
        echo "$SM0145"
        echo "$SM0146"
        echo "$SM0147"
        echo $MENU_SPACER
    else
        print_color_text "Not sites on the server" blue
    fi
}

test_directory() {
    dir="${1}"

    if [[ -z "$dir"  ]];
    then
        print_message "$CS0101" "$SM0001" "" any_key
        return 1
    fi

    if [[ ! -d "$dir"  ]];
    then
        print_message "$CS0101" "$(get_text "$SM0002" "$dir")" "" any_key
        return 1
    fi

    return 0
}

test_sitename() {
    name="${1}"
    exclude="${2}"

    if [[ -z "$name"  ]];
    then
        print_message "$CS0101" "$SM0033" "" any_key
        return 1
    fi

    if [[ -n $exclude ]];
    then
        get_all_sites_list 3600 $exclude
    else
        get_all_sites_list
    fi
    [[ $DEBUG -gt 0  ]] && echo "POOL_SITES_LIST=$POOL_SITES_LIST"

    is_site=$(echo "$POOL_SITES_LIST" | grep -c "^$name:")
    if [[ $is_site -eq 0 ]];
    then
        print_message "$CS0101" "$(get_text "$SM0034" "$name")" "" any_key
        return 1
    fi

    return 0
}
