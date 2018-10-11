#!/bin/bash
# ntlm status
# menu uses next functions: 
# server_ntlm_status - information about host NTLM_STATUS
# ex.
# NTLMStatus:not_configured::::::
# 
# print_site_list_point_ntlm - information about sites point of view NTLM settings
# NONTLM_SITES - sites with is not configured for use LDAP/NTLM 
#set -x
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1
logo=$(get_logo)

# ask user for host domain options
# NTLM_DOMAIN
# NTLM_FQDN
# NTLM_DC
# NTLM_ADMIN
# NTLM_PWD
get_ntlm_options(){

    NTLM_HOST_SETTINGS=N
    NETBIOS_NAME_LIMIT=15                  # bytes
    NETBIOS_NAME_DEFAULT=$(hostname | awk -F'.' '{print $1}')       # netbios hostname
 
    # https://technet.microsoft.com/en-us/library/cc731383.aspx
    until [[ "$NTLM_HOST_SETTINGS" == "Y" ]]; do
        NTLM_DOMAIN=                                                # netbios domain name
        NTLM_FQDN=                                                  # full domain name
        NTLM_DC=                                                    # domain controller
        NTLM_HOST=                                                  # netbios name for host
        NTLM_ADMIN=
        NTLM_PWD=

        print_message "$SM0072" "" "" NTLM_DOMAIN
        if [[ -z "$NTLM_DOMAIN" ]]; then
            print_color_text "$SM0073" red
            continue
        fi

        print_message "$(get_text "$SM0074" "$NETBIOS_NAME_DEFAULT")" \
            "" "" NTLM_HOST "$NETBIOS_NAME_DEFAULT"
        test_hostname "$NTLM_HOST" 15
        [[ $test_hostname -eq 0 ]] && continue

        print_message "$SM0075" "" "" NTLM_FQDN
        if [[ -z "$NTLM_FQDN" ]]; then
            print_color_text "$SM0076" red
            continue
        fi

        print_message "$SM0077" "" "" NTLM_DC
        if [[ -z "$NTLM_DC" ]]; then
            print_color_text "$SM0078" red
            continue
        fi
    
        print_message "$SM0079" "" "" \
            NTLM_ADMIN Administrator
        if [[ -z "$NTLM_ADMIN" ]]; then
            print_color_text "$SM0080" red
            continue
        fi

        print_message "$SM0081" "" "-s" NTLM_PWD
        if [[ -n $NTLM_PWD ]]; then
            NTLM_PWD_FILE=$(mktemp $CACHE_DIR/.ntlmXXXXXXXX)
            echo "$NTLM_PWD" > $NTLM_PWD_FILE
        fi
        NTLM_HOST_SETTINGS=Y
    done

    print_color_text "$SM0082" green
    echo "$MENU_SPACER"
    printf "%-20s: %s\n" "$SM0083" "$NTLM_DOMAIN"
    printf "%-20s: %s\n" "$SM0084" "$NTLM_HOST"
    printf "%-20s: %s\n" "$SM0085" "$NTLM_FQDN"
    printf "%-20s: %s\n" "$SM0086" "$NTLM_DC"
    printf "%-20s: %s\n" "$SM0087" "$NTLM_ADMIN"
    if [[ $DEBUG -gt 0 ]]; then
        printf "%-20s: %s\n" "$SM0088" "$NTLM_PWD"
        printf "%-20s: %s\n" "$SM0089" "$NTLM_PWD_FILE"
    fi
    echo "$MENU_SPACER"
}

# ask for NTLM_SITE, check it:
# -- not empty
# -- NTLM configration options in database
# -- LDAP Module
ntlm_site_name(){

    start_ntlm_config=0
    # ask about sites
    print_message "$SM0090" "$SM0091" "" NTLM_SITE default
    if [[ -z $NTLM_SITE ]]; then
        print_message "$CS0101" "$SM0092" "" any_key
        exit
    fi

    if [[ $DEBUG -gt 0 ]]; then
        echo $MENU_SPACER
        echo "$SM0093$NONTLM_SITES"
        echo $MENU_SPACER
        echo "$SM0094$NTLM_SITES"
        echo $MENU_SPACER
    fi

    if_ntlm_empty_setting=$(echo "$NONTLM_SITES" | grep -c "^$NTLM_SITE:")
    if_ntlm_exist_setting=$(echo "$NTLM_SITES" | grep -c "^$NTLM_SITE:")
    if [[ $DEBUG -gt 0 ]]; then
        echo "noldap=$if_ntlm_empty_setting ldap=$if_ntlm_exist_setting"
    fi

    # site exist in the list; NTLM is enabled on the site
    if [[ ( $if_ntlm_empty_setting -eq 0 ) && ( $if_ntlm_exist_setting -eq 1 ) ]]; then
        print_message "$SM0096" \
            "$SM0095" "" any_key n

        [[ $(echo "$any_key" | grep -wic "Y") -gt 0 ]] && start_ntlm_config=1
        # get additional site info
        site_dir=$(echo "$NTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $3}')
        site_db=$(echo "$NTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $2}')
        site_ntlm_rewrite=$(echo "$NTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $4}')
        site_ntlm_use=$(echo "$NTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $5}')
        site_ldap_mod=$(echo "$NTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $6}')

    # site exist in the list; NTLM is not enabled on the site
    elif [[ ( $if_ntlm_empty_setting -eq 1 ) && ( $if_ntlm_exist_setting -eq 0 ) ]]; then
        start_ntlm_config=1
        site_dir=$(echo "$NONTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $3}')
        site_db=$(echo "$NONTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $2}')
        site_ntlm_rewrite=$(echo "$NONTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $4}')
        site_ntlm_use=$(echo "$NONTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $5}')
        site_ldap_mod=$(echo "$NONTLM_SITES" | grep "^$NTLM_SITE:" | awk -F':' '{print $6}')

    # site not found
    else
        print_message "$CS0101" \
            "$(get_text "$SM0034" "$NTLM_SITE")" \
            "" any_key
        exit 1
    fi
    if [[ $DEBUG -gt 0 ]]; then 
        echo "Site=$NTLM_SITE dir=$site_dir db=$site_db"
        echo "LDAPMod=$site_ldap_mod NTLMUse=$site_ntlm_use NTLMRewrite=$site_ntlm_rewrite"
        echo "Flag start_ntlm_config=$start_ntlm_config"
    fi

    # test if NTLM module is enabled for site
    if [[ "$site_ldap_mod" != "Y" ]]; then
        print_message "$CS0101" \
            "$(get_text "$SM0097" "$NTLM_SITE")" \
            "" any_key
        exit
    fi
}

# start process for create/replace NTLM settings
ntlm_create() {
 
    # test current AD status for host
    [[ -z "$NTLM_STATUS" ]] && server_ntlm_status "skip"

    ntlm_create=Y
    if [[ "$NTLM_STATUS" == "configured" ]]; then
        ntlm_create=N
        print_message "$SM0098" "$SM0099" "" ntlm_create N
    fi

    if [[ $(echo "$ntlm_create" | grep -iwc 'Y') -gt 0 ]]; then
        # get host settings
        get_ntlm_options
        ntlm_task="$bx_sites_script -a ntlm"
        ntlm_task=$ntlm_task" --ntlm_domain=$NTLM_DOMAIN --ntlm_fqdn=$NTLM_FQDN"
        ntlm_task=$ntlm_task" --ntlm_ads=$NTLM_DC"
        ntlm_task=$ntlm_task" --ntlm_login=$NTLM_ADMIN"
        ntlm_task=$ntlm_task" --password_file=$NTLM_PWD_FILE"
        ntlm_task=$ntlm_task" --ntlm_host=$NTLM_HOST"

        # get site name
        ntlm_site_name

        # start configuration process
        if [[ $start_ntlm_config -eq 1 ]]; then
            ntlm_task=$ntlm_task" --database=$site_db --root=$site_dir"

            print_message "$SM0100" "" "" _domain_confirm 'n'
            if [[ $(echo "$_domain_confirm" | grep -iwc 'y') -gt 0 ]]; then
                [[ $DEBUG -gt 0 ]] && echo "$ntlm_task"
                exec_pool_task "$ntlm_task" "$SM0101"
            fi
        fi
    fi
    NTLM_MENU_SELECT=
}

# Add apache NTLM configuration to the site; NTLM already configured on the server
ntml_site_config() {

    ntlm_task="$bx_sites_script -a ntlm_update"

    # get site name
    ntlm_site_name
  
    if [[ $start_ntlm_config -eq 1 ]]; then
        ntlm_task=$ntlm_task" --database=$site_db --root=$site_dir"

        print_message "$SM0100" "" "" _domain_confirm 'n'
        if [[ $(echo "$_domain_confirm" | grep -iwc 'y') -gt 0 ]]; then
            [[ $DEBUG -gt 0 ]] && echo "$ntlm_task"
            exec_pool_task "$ntlm_task" "$SM0101"
        fi
    else
        [[ $DEBUG -gt 0 ]] && print_message "$CS0101" "" "" any_key
    fi
    NTLM_MENU_SELECT=
}

# print host menu
sub_menu() {
    menu_00="$SM0201"
    menu_01="$SM0102" # configure new NTLM settings for server and one site
    menu_02="$SM0103"       # add existen NTLM settings to a site

    MENU_SELECT=
    until [[ -n "$MENU_SELECT" ]]; do
        menu_logo="$SM0104"
        print_menu_header

        # menu
        print_site_list_point_ntlm # NONTLM_SITES = site:site_dir site1:site_dir1
        server_ntlm_status         # NTLM_STATUS  = configured|not_configured
        get_task_by_type site POOL_SITE_TASK_LOCK POOL_SITE_TASK_INFO
        print_task_by_type site "$POOL_SITE_TASK_LOCK" "$POOL_SITE_TASK_INFO"
        

        if [[ $POOL_MYSQL_TASK_LOCK -eq 1 ]]; then
            menu_list="\n$menu_00"
        else
            if [[ ( "$NTLM_STATUS" == "configured" ) && ( -n $NONTLM_SITES ) ]]; then
                menu_list="\n$menu_01\n$menu_02\n$menu_00"
            else
                menu_list="\n$menu_01\n$menu_00"
            fi 
        fi
        print_menu

        print_message "$SM0205" '' '' MENU_SELECT

        # process selection
        case "$MENU_SELECT" in
            "1") ntlm_create;;                # configure new NTLM settings for server and one site
            "2") ntml_site_config;;           # add existen NTLM settings to a site
            "0") exit ;;
            *)   error_pick;;
        esac
    
        MENU_SELECT=
    done
}

sub_menu

