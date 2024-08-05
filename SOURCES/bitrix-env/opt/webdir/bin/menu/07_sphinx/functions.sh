#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

bx_process_script=$BIN_DIR/bx-process
bx_host_script=$BIN_DIR/wrapper_ansible_conf
bx_sphinx_script=$BIN_DIR/bx-sphinx

sphinx_menu_dir=$BIN_DIR/menu/07_sphinx

site_menu_dir=$BIN_DIR/menu/06_site
site_menu_fnc=$site_menu_dir/functions.sh
. $site_menu_fnc || exit 1

# get_text variables
[[ -f $sphinx_menu_dir/functions.txt   ]] && \
    . $sphinx_menu_dir/functions.txt


# get status for sphinx servers
# return
# SPHINX_SERVERS -list of sphinx servers
# SPHINX_SERVERS_CN
# NOSPHINX_SERVERS - list of servers whithout
# NOSPHINX_SERVERS_CN - 
get_sphinx_servers_status() {
    [[ -z "$POOL_SERVER_LIST" ]] && cache_pool_info

    [[ $DEBUG -gt 0 ]] && \
        echo "POOL_SERVER_LIST=$POOL_SERVER_LIST"
    SPHINX_SERVERS=
    SPHINX_SERVERS_CN=0
    NOSPHINX_SERVERS=
    NOSPHINX_SERVERS_CN=

    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $POOL_SERVER_LIST; do
        host_ident=$(echo "$line" | awk -F':' '{print $1}' | sed -e "s/^\s\+//")
        host_ip=$(echo "$line" | awk -F':' '{print $2}' | sed -e "s/^\s\+//")
        host_hostname=$(echo "$line" | awk -F':' '{print $5}' | sed -e "s/^\s\+//")
        sphinx_version=$(echo "$line" | awk -F':' '{print $15}' | sed -e "s/^\s\+//")

        if [[ $sphinx_version == "not_installed" ]]; then
            NOSPHINX_SERVERS_CN=$(( $NOSPHINX_SERVERS_CN + 1 ))
            SPHINX_SERVERS=$SPHINX_SERVERS"$host_hostname:$host_ip:$sphinx_version
"
        else
            SPHINX_SERVERS_CN=$(( $SPHINX_SERVERS_CN + 1 ))
            NOSPHINX_SERVERS=$NOSPHINX_SERVERS"$host_hostname:$host_ip:$sphinx_version
"
        fi

    done
    IFS=$IFS_BAK
    IFS_BAK=
}

cache_sphinx_servers_status() {
    SPHINX_SERVERS=
    SPHINX_SERVERS_CN=0
    NOSPHINX_SERVERS=
    NOSPHINX_SERVERS_CN=0
    SPHINX_SERVERS_CACHE=$CACHE_DIR/sphinx_servers_status.cache
    SPHINX_SERVERS_CACHE_LT=3600

    test_cache_file $SPHINX_SERVERS_CACHE $SPHINX_SERVERS_CACHE_LT
    if [[ $? -gt 0 ]]; then
        get_sphinx_servers_status
        echo "$SPHINX_SERVERS" > $SPHINX_SERVERS_CACHE
        echo "$NOSPHINX_SERVERS" >> $SPHINX_SERVERS_CACHE
    else
        SPHINX_SERVERS=$(cat $SPHINX_SERVERS_CACHE | grep -v "not_installed")
        NOSPHINX_SERVERS=$(cat $SPHINX_SERVERS_CACHE | grep "not_installed")
        SPHINX_SERVERS_CN=$(echo "$SPHINX_SERVERS" | grep -vc "^$")
        NOSPHINX_SERVERS_CN=$(echo "$NOSPHINX_SERVERS" | grep -vc "^$")
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "     SPHINX_SERVERS=$SPHINX_SERVERS"
        echo "  SPHINX_SERVERS_CN=$SPHINX_SERVERS_CN"
        echo "   NOSPHINX_SERVERS=$NOSPHINX_SERVERS"
        echo "NOSPHINX_SERVERS_CN=$NOSPHINX_SERVERS_CN"
    fi
}

print_sphinx_servers_status() {
    local type=${1:-all}

    cache_sphinx_servers_status
    if [[ $type == "sphinx" ]]; then
        if [[ $SPHINX_SERVERS_CN -eq 0 ]]; then
            echo "$SPH0208"
            echo
            return 1
        fi
    fi

    if [[ $type == "nosphinx" ]]; then
        if [[ $NOSPHINX_SERVERS_CN -eq 0 ]]; then
            echo "$SPH0209"
            echo
            return 1
        fi
    fi

    echo "$(get_text "$SPH0001" "$SPHINX_SERVERS_CN")"
    echo $MENU_SPACER
    printf "%-17s | %20s| %s\n" \
        "$SPH0002" "$SPH0003" "$SPH0004"
    echo $MENU_SPACER

    IFS_BAK=$IFS
    IFS=$'\n'
    if [[ ( $type == "all" ) || ( $type == "sphinx" ) ]]; then
        for line in $SPHINX_SERVERS; do
            echo "$line" | \
                awk -F':' '{printf "%-17s | %20s| %s\n", $1,$2,$3}'
        done
    fi

    if [[ ( $type == "all" ) || ( $type == "nosphinx" ) ]]; then
        for line in $NOSPHINX_SERVERS; do
            echo "$line" | \
                awk -F':' '{printf "%-17s | %20s| %s\n", $1,$2,$3}'
        done
    fi
    IFS=$IFS_BAK
    IFS_BAK=
    echo $MENU_SPACER
}
