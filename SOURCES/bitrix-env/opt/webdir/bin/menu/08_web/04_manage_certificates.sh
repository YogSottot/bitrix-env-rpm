#!/usr/bin/bash
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
site_menu_dir=$BIN_DIR/menu/06_site
site_menu_fnc=$site_menu_dir/functions.sh
. $site_menu_fnc || exit 1

logo=$(get_logo)

sites_related_by_cert() {
    https_cert="${1}"
    [[ -z $https_cert ]] && return 255

    # get related status
    SITES_LINKED_BY_CERT=

    sites_https_info=$($bx_sites_script -a list | \
        grep ':https:' | grep -v ":$site_name:" | sed -e 's/^bxSite:https://' | \
        grep ":$https_cert:")
    if [[ -n $sites_https_info ]]; then
        SITES_LINKED_BY_CERT=$(echo "$sites_https_info" | awk -F':' '{printf "%s,", $1}')
    fi

    # push-server
    if [[ -z $PUSH_SSL ]]; then
        cache_push_servers_status
    fi
    if [[ $PUSH_SSL == "$https_cert" ]]; then
        SITES_LINKED_BY_CERT=$SITES_LINKED_BY_CERT"push-server,"
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "Related sites: $SITES_LINKED_BY_CERT"
    fi
}

# return
# 1     - LE
# 2     - Own
# 3     - Standart
# 255   - Site doesn't exist
# 0     - Not configured
site_https_status() {
    site_name="${1:-default}"
    cache_pool_sites
    POOL_SITES_KERNEL_LIST=$(echo "$POOL_SITES_KERNEL_LIST" | grep -v ':ext_kernel:')
    POOL_SITES_KERNEL_COUNT=$(echo "$POOL_SITES_KERNEL_LIST" | grep -vc '^$')

    POOL_SITES_LIST="$POOL_SITES_KERNEL_LIST
$POOL_SITES_LINK_LIST"
    if [[ $(echo "$POOL_SITES_LIST" | grep -c "^$site_name:") -eq 0 ]]; then
        return 255
    fi

    # get site status
    site_root=$(echo "$POOL_SITES_LIST" | grep "^$site_name:" | awk -F':' '{print $6}')
    site_https_info=$($bx_sites_script -a status --site $site_name -r $site_root | \
        grep ':https:' | sed -e 's/^bxSite:https://')
    https_cert=$(echo "$site_https_info" | awk -F':' '{print $4}' | \
        sed -e "s:/etc/nginx/::")
    https_key=$(echo "$site_https_info" | awk -F':' '{print $5}' | \
        sed -e "s:/etc/nginx/::")
    if [[ $DEBUG -gt 0 ]]; then
        echo "Site:  $site_name"
        echo "Root:  $site_root"
        echo "Cert:  $https_cert"
        echo "Key:   $https_key"
    fi

    if [[ ( $https_cert == "$https_key" ) && ( $https_cert == 'ssl/cert.pem' ) ]]; then
        return 3
    fi

    if [[ $(echo "$https_cert" | grep -wc "dehydrated") -gt 0 ]]; then
       sites_related_by_cert "$https_cert"
       return 1
    fi

    if [[ ( -n $https_cert ) && ( -n $https_key ) ]]; then
        return 2
    fi

    return 0
}

certs_status() {
    cert_path="${1}"
    [[ -z $cert_path ]] && return 255
    SITES_LIST=

    cert_info=$($bx_sites_script -a cert_status --certificate "$cert_path")
    site_certs_count=$(echo "$cert_info" | grep 'site_certs_count:' | awk -F':' '{print $2}')
    if [[ $site_certs_count -eq 0 ]]; then
        return 1
    fi
    SITES_LIST=$(echo "$cert_info" | grep 'site_certs:' | \
        awk -F':' '{print $3}')
    return 0
}

sites_https_status() {
    site_list="${1:-default}"
    sites_https_status_rtn=0
    sites_https_cnt=0

    IFS_BAK=$IFS
    IFS=','
    for sn in $site_list; do
        sn=$(echo "$sn" | sed -e "s/\s\+//g")
        if [[ $sn == "push-server" ]]; then
            continue
        fi
        site_https_status "$sn"
        site_https_status_rtn=$?
        [[ $site_https_status_rtn -gt $sites_https_status_rtn ]] && sites_https_status_rtn=$site_https_status_rtn
        sites_https_cnt=$(( $sites_https_cnt + 1 ))
    done
    IFS=$IFS_BAK
    IFS_BAK=
    return $sites_https_status_rtn
}

configure_le() {
    print_message "$WEB0037" "$WEB0038" '' SITE_NAME "default"
    print_message "$WEB0039" "$WEB0040" '' DNS_NAMES
    print_message "$WEB0041" '' '' EMAIL

    if [[ -z $DNS_NAMES ]]; then
        print_message "$WEB0200" $WEB0042 "" any_key
        return 1
    fi

    if [[ -z $EMAIL ]]; then
        print_message "$WEB0200" "$WEB0043" "" any_key
        return 1
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo "Site:  $SITE_NAME"
        echo "DNS:   $DNS_NAMES"
        echo "Email: $EMAIL"
    fi

    sites_https_status "$SITE_NAME"
    site_https_status_rtn=$?
    if [[ $DEBUG -gt 0 ]]; then
        echo "Check:  $site_https_status_rtn"
    fi

    if [[ $site_https_status_rtn -eq 255 ]]; then
        print_message "$WEB0200" "$WEB0044 $SITE_NAME" "" any_key
        return 1
    fi

    if [[ $(echo "$SITE_NAME" | grep -c "push-server" ) && $sites_https_cnt -eq 0 ]]; then
        print_message  "$WEB0068" "$WEB0069" "" any_key
        return 1
    fi

    if [[ ( $site_https_status_rtn -eq 1 ) || ( $site_https_status_rtn -eq 2 ) ]]; then
        print_message "$WEB0045" "Sites: $SITE_NAME" "" any_key "n"
    else
        print_message "$WEB0046" "Sites: $SITE_NAME" "" any_key "y"
    fi

    if [[ $(echo "$any_key" | grep -wci "y") -gt 0 ]]; then
        task_exec="$bx_sites_script -a configure_le --site \"$SITE_NAME\" -r $site_root"
        task_exec="$task_exec --email \"$EMAIL\" --dns \"$DNS_NAMES\""
        [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
        exec_pool_task "$task_exec" "$WEB0047"
    fi
}

configure_own_cert() {
    NGINX_CERT_DIR=/etc/nginx/certs
    print_message "$WEB0037" "$WEB0038" '' SITE_NAME "default"

    sites_https_status "$SITE_NAME"
    site_https_status_rtn=$?
    if [[ $DEBUG -gt 0 ]]; then
        echo "Check:  $site_https_status_rtn"
    fi

    if [[ $site_https_status_rtn -eq 255 ]]; then
        print_message "$WEB0200" "$WEB0044 $SITE_NAME" "" any_key
        return 1
    fi

    print_color_text "$(get_text "$WEB0048" "$NGINX_CERT_DIR")"
    print_message "$WEB0049" "" "" PrivateKey
    print_message "$WEB0050" "" "" Certificate
    print_message "$WEB0051" "" "" CertificateChain

    if [[ $DEBUG -gt 0 ]]; then
        echo "Site:              $SITE_NAME"
        echo "Private Key:       $PrivateKey"
        echo "Certificate:       $Certificate"
        echo "Certificate Chain: $CertificateChain"
    fi

    # test options
    if [[ ( -z $PrivateKey ) || ( -z $Certificate ) ]]; then
        print_message "$WEB0200" "$WEB0052" "" any_key
        return 1
    fi

    if [[ ! ( -f $PrivateKey ) && ! ( -f $NGINX_CERT_DIR/$PrivateKey ) ]]; then
        print_message "$WEB0200" "$WEB0053 $PrivateKey" "" any_key
        return 1
    fi

    if [[ ! ( -f $Certificate ) && ! ( -f $NGINX_CERT_DIR/$Certificate ) ]]; then
        print_message "$WEB0200" "$WEB0054 $Certificate" "" any_key
        return 1
    fi

    if [[ ( -n $CertificateChain ) && ( ! ( -f $CertificateChain ) && ! ( -f $NGINX_CERT_DIR/$CertificateChain ) ) ]]; then
        print_message "$WEB0200" "$WEB0055 $CertificateChain" "" any_key
        return 1
    fi

    if [[ ( $site_https_status_rtn -eq 1 ) || ( $site_https_status_rtn -eq 2 ) ]]; then
        print_message "$WEB0045" "Sites: $SITE_NAME" "" any_key "n"
    else
        print_message "$WEB0046" "Sites: $SITE_NAME" "" any_key "y"
    fi

    if [[ $(echo "$any_key" | grep -wci "y") -gt 0 ]]; then
        task_exec="$bx_sites_script -a configure_cert --site \"$SITE_NAME\" -r $site_root"
        task_exec="$task_exec --private_key $PrivateKey"
        task_exec="$task_exec --certificate $Certificate"
        [[ -n $CertificateChain ]] && task_exec="$task_exec --certificate_chain $CertificateChain"

        [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
        exec_pool_task "$task_exec" "$WEB0056"
    fi
}

reset_cert() {
    NGINX_CERT_DIR=/etc/nginx/certs
    print_message "$WEB0070" "" "" CERT_PATH

    certs_status "$CERT_PATH"
    if [[ $? -gt 0 ]]; then
        print_message "$WEB0200" "$(get_text "$WEB0072" "$CERT_PATH")"
        return 1
    fi

    if [[ $CERT_PATH == "/etc/nginx/ssl/cert.pem" ]]; then
        print_message "$WEB0200" "$(get_text "$WEB0073" "$SITES_LIST")"
        return 1
    fi

    SITE_NAME="$SITES_LIST"

    sites_https_status "$SITE_NAME"
    site_https_status_rtn=$?
    if [[ $DEBUG -gt 0 ]]; then
        echo "Check:  $site_https_status_rtn"
    fi

    if [[ $site_https_status_rtn -eq 255 ]]; then
        print_message "$WEB0200" "$WEB0044 $SITE_NAME" "" any_key
        return 1
    fi

#    if [[ $(echo "$SITE_NAME" | grep -wc "push-server") -gt 0 && -n "$PUSH_TYPE" && $PUSH_TYPE == "Custom" ]]; then
#        site_https_status_rtn=1
#    fi

    if [[ ( $site_https_status_rtn -eq 1 ) || ( $site_https_status_rtn -eq 2 ) ]]; then
        print_message "$WEB0057" "Sites: $SITE_NAME" "" any_key "n"
    else
        print_message "$WEB0200" "$WEB0058 Sites: $SITE_NAME" "" any_key
        return 1
    fi

    if [[ $(echo "$any_key" | grep -wci "y") -gt 0 ]]; then
        task_exec="$bx_sites_script -a reset_cert --site \"$SITE_NAME\""

        [[ $DEBUG -gt 0 ]] && echo "task_exec=$task_exec"
        exec_pool_task "$task_exec" "$WEB0157"
    fi
}

sub_menu() {
    menu_00="$WEB0201"
    menu_01="$WEB0158"
    menu_02=" $WEB0059"
    menu_03=" $WEB0060"

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$WEB0056"
        print_menu_header

        # print sites
        #set -x
        print_site_list_point_https

        # task info
        get_task_by_type '(mysql|site)' POOL_TASK_LOCK POOL_TASK_INFO
        print_task_by_type '(mysql|site)' "$POOL_TASK_LOCK" "$POOL_TASK_INFO"

        # background task or not found free servers in the pool
        if [[ ( $POOL_TASK_LOCK -eq 1 ) ]]; then
            menu_list="$menu_00"
        else
            menu_list="$menu_01\n\t\t$menu_02\n\t\t$menu_03\n\t\t $menu_00"
        fi

        print_menu

        if [[ $POOL_TASK_LOCK -gt 0 ]]; then
            print_message "$WEB0202" '' '' MENU_SELECT 0
        else
            print_message "$WEB0205" '' '' MENU_SELECT
        fi

        case "$MENU_SELECT" in
            0) exit ;;
            1) configure_le ;;
            2) configure_own_cert ;;
            3) reset_cert ;;
        esac
        MENU_SELECT=
    done
}

sub_menu
