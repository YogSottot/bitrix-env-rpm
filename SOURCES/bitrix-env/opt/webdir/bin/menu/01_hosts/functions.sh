#!/usr/bin/bash
#
BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

[[ -z $DEBUG ]] && DEBUG=0
HOSTS_FUNCTIONS=1
logo=$(get_logo)

hosts_menu=$BIN_DIR/menu/01_hosts
local_menu=$BIN_DIR/menu/02_local

# get_text variables
[[ -f $hosts_menu/functions.txt  ]] && \
    . $hosts_menu/functions.txt

[[ -f $local_menu/functions.sh ]] && \
   . $local_menu/functions.sh

bx_process_script=$BIN_DIR/bx-process               # wrapper for ansible which contains process
bx_monitor_script=$BIN_DIR/bx-monitor               # wrapper for ansible which contains monitoring
ansible_wrapper=$BIN_DIR/wrapper_ansible_conf       # wrapper for ansible which contains host manage

ansible_copy_keys=$BIN_DIR/ssh_keycopy              # expect script which can copy ssh key to host
ansible_changepwd=$BIN_DIR/ssh_chpasswd             # expect ecript which can change user password

# LOGS paths for notification
log_copy_keys=$LOGS_DIR/ssh_keycopy.log
log_changepwd=$LOGS_DIR/ssh_chpasswd.log

site_menu_dir=$BIN_DIR/menu/06_site
site_menu_fnc=$site_menu_dir/functions.sh
bx_sites_script=$BIN_DIR/bx-sites                   # wrapper for ansible which contains site action
. $site_menu_fnc || exit 1

# copy ssh key to the server
# fill out
# ANSIBLE_COPY_ERR
# ANSIBLE_COPY_MSG
copy_sshkey() {
    local ssh_server="$1"
    local ssh_user="$2"
    local ssh_password="$3"

    [[ -z "$ANSIBLE_SSHKEY_PUBLIC" ]] && get_ansible_sshkey

    # copy public key to remote server, use input password
    local copy_cmd="$ansible_wrapper -a copy"
    copy_cmd=$copy_cmd" -i $ssh_server -k $ANSIBLE_SSHKEY_PUBLIC"
    copy_cmd=$copy_cmd" -p $(printf "%q" "$ssh_password")"

    if [[ $DEBUG -gt 0 ]]; then
        echo "copy_cmd=$copy_cmd"
    fi
    ANSIBLE_COPY_INFO=$(eval "$copy_cmd")
    ANSIBLE_COPY_ERR=$(echo "$ANSIBLE_COPY_INFO" | grep '^error:' | sed -e 's/^error://')
    ANSIBLE_COPY_MSG=$(echo "$ANSIBLE_COPY_INFO" | grep '^message:' | sed -e 's/^message://')

    # debug info
    if [[ $DEBUG -gt 0 ]]; then
        echo "ANSIBLE_COPY_ERR=$ANSIBLE_COPY_ERR"
        echo "ANSIBLE_COPY_MSG=$ANSIBLE_COPY_MSG"
    fi

    [[ -n "$ANSIBLE_COPY_ERR" ]] && return 1
    return 0
}

# change user password via ssh 
# ANSIBLE_CHPWD_ERR
# ANSIBLE_CHPWD_MSG
# NEW_PASSWORD
change_password_viassh() {
    local ssh_server="$1"
    local ssh_user="$2"
    local current_password= "$3"

    ask_password_info "$ssh_user" "new_password"
    ask_password_rtn=$?
    [[ $ask_password_rtn -gt 0 ]] && exit 1

    local changepass_cmd="$ansible_wrapper -a pw -i $ssh_server"
    changepass_cmd=$changepass_cmd" -p $(printf "%q" "$current_password")"
    changepass_cmd=$changepass_cmd" -P $(printf "%q" "$new_password")"
    
    if [[ $DEBUG -gt 0 ]]; then
        echo "changepass_cmd=$changepass_cmd"
    fi
    ANSIBLE_CHPWD_INF=$(eval "$changepass_cmd")
    ANSIBLE_CHPWD_ERR=$(echo "$ANSIBLE_CHPWD_INF" | grep -e "^error:" | sed -e "s/^error://" )
    ANSIBLE_CHPWD_MSG=$(echo "$ANSIBLE_CHPWD_INF" | grep -e "^message:" | sed -e "s/^message://" )

    if [[ $DEBUG -gt 0 ]]; then
        echo "ANSIBLE_CHPWD_ERR=$ANSIBLE_CHPWD_ERR"
        echo "ANSIBLE_CHPWD_MSG=$ANSIBLE_CHPWD_MSG"
    fi

    [[ -n $ANSIBLE_CHPWD_MSG ]] && return 1
    NEW_PASSWORD=$(printf "%q" "$new_password")
    [[ $DEBUG -gt 0 ]] && echo "NEW_PASSWORD=$NEW_PASSWORD"
    return 0
}

# add server idnetifier in configuration and configure monitoring settings
#add_server_to_pool(){
#    local host_ident=$1
#    local host_addr=$2
#
#    # add server to pool configuration file
#    local add_server_cmd="$ansible_wrapper -a add -H $host_ident -i $host_addr"
#    [[ $DEBUG -gt 0 ]] && echo "$add_server_cmd"
#
#    ANSIBLE_ADD_INFO=$(eval "$add_server_cmd")
#    ANSIBLE_ADD_ERR=$(echo "$ANSIBLE_ADD_INFO" | grep '^error:' | sed -e 's/^error://')
#    ANSIBLE_ADD_MSG=$(echo "$ANSIBLE_ADD_INFO" | grep '^message:' | sed -e 's/^message://')
#    if [[ $DEBUG -gt 0 ]]; then
#        echo "ANSIBLE_ADD_ERR=$ANSIBLE_ADD_ERR"
#        echo "ANSIBLE_ADD_MSG=$ANSIBLE_ADD_MSG"
#    fi
#    [[ -n "$ANSIBLE_ADD_ERR" ]] && return 1
#
#    # update monitoring
#    # Host::createHost: modification was successful, host_vars=yes, hosts=yes task_id=monitor_0786886321 task_pid=32039 task_status=running
#    task_id=$(echo "$ANSIBLE_ADD_MSG" | egrep -o "task_id=\S+" | awk -F'=' '{print $2}')
#    task_pid=$(echo "$ANSIBLE_ADD_MSG" | egrep -o "task_pid=\S+" | awk -F'=' '{print $2}')
#    task_status=$(echo "$ANSIBLE_ADD_MSG" | egrep -o "task_status=\S+" | awk -F'=' '{print $2}')
#    if [[ -n "$task_id" ]]; then
#        echo "Start job:"
#        printf "%-10s: %s\n" "JobID"  "$task_id"
#        printf "%-10s: %s\n" "PID"    "$task_pid"
#        echo "It will $_task_txt in the pool."
#        print_message "$HM0200" "" "" any_key
#    fi
#
#    return 0
#}

# delete it from ansible configuration
forget_server() {
    local host_ident="$1"

    cur_id=$(get_server_id "$host_ident")
    cur_id_rtn=$?
    #if [[ $cur_id_rtn -eq 1  ]]; then
    #    print_message "Press ENTER to exit" \ 
    #        "Server $host_ident was found but cannot be used due to configuration error" "" any_key
    #    return 1
    #
    if [[ $cur_id_rtn -eq 2 ]]; then
        print_message "$HM0200" "$(get_text "$HM0012" "$host_ident")" "" any_key
        return 1
    fi

    local forget_cmd="$ansible_wrapper -a forget_host"
    forget_cmd=$forget_cmd" --host $cur_id"
    if [[ $DEBUG -gt 0 ]]; then
        echo "forget_cmd=$forget_cmd"
    fi
    FORGET_INFO=$(eval "$forget_cmd")
    FORGET_ERR=$(echo "$FORGET_INFO" | grep '^error:' | sed -e 's/^error://')
    FORGET_MSG=$(echo "$FORGET_INFO" | grep '^message:' | sed -e 's/^message://')
    if [[ $DEBUG -gt 0 ]]; then
        echo "FORGET_ERR=$FORGET_ERR"
        echo "FORGET_MSG=$FORGET_MSG"
    fi
    [[ -n "$FORGET_ERR" ]] && return 1
    return 0
}

# clean options on the server and delete it from ansible configuration
#purge_server(){
#    local host_ident="$1"
#    local host_addr="$2"
#
#    cur_id=$(get_server_id "$host_ident")
#    cur_id_rtn=$?
#    if [[ $cur_id_rtn -eq 1  ]]; then
#        print_message "$HM0200" "$(get_text "$HM0013" "$host_ident")" "" any_key
#        return 1
#
#    elif [[ $cur_id_rtn -eq 2 ]]; then
#        print_message "$HM0200" "$(get_text "$HM0012" "$host_ident")"
#        return 1
#    fi
#
#    local delete_cmd="$ansible_wrapper -a del"
#    delete_cmd=$delete_cmd" --host $cur_id --ip $host_addr"
#    if [[ $DEBUG -gt 0 ]]; then
#        echo "delete_cmd=$delete_cmd"
#    fi
#    exec_pool_task "$delete_cmd" "remove host=$host_ident"
#}

# remove pool
remove_pool() {
    local delete_task="$ansible_wrapper -a delete_pool"
    [[ $DEBUG -gt 0 ]] && echo "cmd=$delete_task"
    DELETE_INFO=$(eval "$delete_task")
    DELETE_ERR=$(echo "$DELETE_INFO" | grep '^error:' | sed -e 's/^error://')
    DELETE_MSG=$(echo "$DELETE_INFO" | grep '^message:' | sed -e 's/^message://')

    if [[ $DEBUG -gt 0 ]]; then
        echo "DELETE_ERR=$DELETE_ERR"
        echo "DELETE_MSG=$DELETE_MSG"
    fi
    [[ -n "$DELETE_ERR" ]] && return 1
    return 0
}

test_main_module_for_php7() {
    cache_pool_sites
    MAIN_LOWER_VERSION="16.0.10"     # for all modules 16.5.0 
    MAIN_U=$(echo $MAIN_LOWER_VERSION | awk -F'.' '{print $1}')
    MAIN_M=$(echo $MAIN_LOWER_VERSION | awk -F'.' '{print $2}')
    MAIN_L=$(echo $MAIN_LOWER_VERSION | awk -F'.' '{print $3}')

    TEST_PHP7_PASS=
    TEST_PHP7_PASS_CNT=0
    TEST_PHP7_NOTPASS=
    TEST_PHP7_NOTPASS_CNT=0
    TEST_PHP7_SKIP=
    TEST_PHP7_SKIP_CNT=0
    TEST_PHP7_CNT=0
    IFS_BAK=$IFS
    IFS=$'\n'
    for line in $POOL_SITES_KERNEL_LIST; do
        TEST_PHP7_CNT=$(( $TEST_PHP7_CNT + 1 ))
        local t_site_name=$(echo "$line" | awk -F':' '{print $1}' | sed -e "s/\s\+//g")
        local t_site_status=$(echo "$line" | awk -F':' '{print $4}' | sed -e "s/\s\+//g")
        local t_main_vers=$(echo "$line" | awk -F':' '{print $13}' | sed -e "s/\s\+//g")
        if [[ $DEBUG -gt 0 ]]; then
            echo "+++++++++"
            echo "$t_site_name -> $t_main_vers"
        fi
        # we estimate only complete installation
        if [[ $t_site_status == "finished" ]]; then
            if [[ $t_main_vers == "" ]]; then
                TEST_PHP7_SKIP="$TEST_PHP7_SKIP $t_site_name"
                TEST_PHP7_SKIP_CNT=$(( $TEST_PHP7_SKIP_CNT + 1  ))
            else
                local t_u_ver=$(echo $t_main_vers | awk -F'.' '{print $1}')
                local t_m_ver=$(echo $t_main_vers | awk -F'.' '{print $2}')
                local t_l_ver=$(echo $t_main_vers | awk -F'.' '{print $3}')

                if [[ $t_u_ver -gt $MAIN_U ]]; then
                    TEST_PHP7_PASS="$TEST_PHP7_PASS $t_site_name"
                    TEST_PHP7_PASS_CNT=$(( $TEST_PHP7_PASS_CNT + 1 ))
                elif [[ $t_u_ver -eq $MAIN_U ]]; then
                    if [[ $t_m_ver -gt $MAIN_M ]]; then
                        TEST_PHP7_PASS="$TEST_PHP7_PASS $t_site_name"
                        TEST_PHP7_PASS_CNT=$(( $TEST_PHP7_PASS_CNT + 1  ))
                    elif [[ $t_m_ver -eq $MAIN_M ]]; then
                        if [[ $t_l_ver -gt $MAIN_L ]]; then
                            TEST_PHP7_PASS="$TEST_PHP7_PASS $t_site_name"
                            TEST_PHP7_PASS_CNT=$(( $TEST_PHP7_PASS_CNT + 1   ))
                        else
                            TEST_PHP7_NOTPASS="$TEST_PHP7_NOTPASS $t_site_name/$t_main_vers"
                            TEST_PHP7_NOTPASS_CNT=$(( $TEST_PHP7_NOTPASS_CNT +1 ))
                        fi
                    else
                        TEST_PHP7_NOTPASS="$TEST_PHP7_NOTPASS $t_site_name/$t_main_vers"
                        TEST_PHP7_NOTPASS_CNT=$(( $TEST_PHP7_NOTPASS_CNT +1  ))
                    fi
                else
                    TEST_PHP7_NOTPASS="$TEST_PHP7_NOTPASS $t_site_name/$t_main_vers"
                    TEST_PHP7_NOTPASS_CNT=$(( $TEST_PHP7_NOTPASS_CNT +1   ))
                fi
            fi
       else
           # errors and not_installed sites
           TEST_PHP7_SKIP="$TEST_PHP7_SKIP $t_site_name"
           TEST_PHP7_SKIP_CNT=$(( $TEST_PHP7_SKIP_CNT + 1 ))
       fi
   done
   IFS=$IFS_BAK
   IFS_BAK=

   if [[ $DEBUG -gt 0 ]]; then
       echo "$HM0014($TEST_PHP7_PASS_CNT): $TEST_PHP7_PASS"
       echo "$HM0015($TEST_PHP7_NOTPASS_CNT): $TEST_PHP7_NOTPASS"
       echo "$HM0016($TEST_PHP7_SKIP_CNT): $TEST_PHP7_SKIP"
   fi

   [[ $TEST_PHP7_NOTPASS_CNT -gt 0 ]] && return 2
   [[ $TEST_PHP7_SKIP_CNT -gt 0 ]] && return 1
   return 0
}

#   ${upperVersion}${middleVersion} in return code
#   255 - not supported case
# PHP_MESSAGE - error message if return code is 255
# PHP_VERSION - current php version
test_php_version() {
    local host_ident="${1:-localhost}"
    local host_info="$2"                # bx_variables for hosts (requested ones and can be reused)

    PHP_MESSAGE=
    PHP_VERSION=
    if [[ $DEBUG -gt 0 ]]; then
        echo "host_ident=$host_ident"
        echo "host_info=$host_info"
    fi

    # if we don't pass variable to the function we will request data
    if [[ -z "$host_info" ]]; then
        host_info=$($ansible_wrapper -a bx_info -H $host_ident)
        PHP_VERSION=$(echo "$host_info" | awk -F':' '{print $8}')
    else
        PHP_VERSION=$(echo "$host_info" | awk -F':' '{print $13}')
    fi

    # php package is not found in the system
    if [[ -z $PHP_VERSION ]]; then
        PHP_MESSAGE="$(get_text "$HM0017" "php")"
        return 255
    fi

    # split php version 5.4.32 to separate values
    local php_upper=$(echo "$PHP_VERSION" | awk -F'.' '{print $1}')
    local php_middle=$(echo "$PHP_VERSION" | awk -F'.' '{print $2}')
    local php_lower=$(echo "$PHP_VERSION" | awk -F'.' '{print $3}')

    local php_union=${php_upper}${php_middle}

    # return 56 or 70
    return $php_union
}

php_conditions() {
    # test versions
    # unsupported version
    if [[ $php_upper -lt 5 ]]; then
        PHP_MESSAGE="$(get_text "$HM0018" "$php_upper.$php_middle")"

    # php 5.x versions
    elif [[ $php_upper -eq 5 ]]; then
        
        # Unsupported PHP version (<5.3)
        if [[ $php_middle -lt 3 ]]; then
            PHP_MESSAGE="$(get_text "$HM0018" "$php_upper.$php_middle")"
            return 255

        # 5.3
        # PHP package can be updated to version 5.4
        elif [[ $php_middle -eq 3 ]]; then
            PHP_MESSAGE=$(get_text "$HM0019" "5.4")

        # 5.4; PHP package can be updated to version 5.6
        elif [[ $php_middle -eq 4 ]]; then
            PHP_MESSAGE=$(get_text "$HM0019" "5.6")
        
        # 5.5 && 5.6; PHP package can be updated to version
        elif [[ $php_middle -gt 4 ]]; then
            PHP_MESSAGE=$(get_text "$HM0019" "7.0")

        # Cannot get/recognize PHP package version; something odd
        else
            PHP_MESSAGE="$HM0020"
            return 255
        fi

    # 7.x; PHP package can be downgraded to version
    elif [[ $php_upper -eq 7 ]]; then
        PHP_MESSAGE="$(get_text "$HM0021" "5.6")"

    # something else
    else
        PHP_MESSAGE="$HM0020"
        return 255
    fi
}

# return
#   ${upperVersion}${middleVersion} in return code
#   255 - not supported case
# MYSQL_MESSAGE - error message if return code is 255
# MYSQL_VERSION - current mysql version
test_mysql_version() {
    local host_ident="${1:-localhost}"
    local host_info="$2"                # bx_variables for hosts (requested ones and can be reused)

    MYSQL_MESSAGE=
    MYSQL_VERSION=
    if [[ $DEBUG -gt 0 ]]; then
        echo "host_ident=$host_ident"
        echo "host_info=$host_info"
    fi

    # if we don't pass variable to the function we will request data
    if [[ -z "$host_info" ]]; then
        host_info=$($ansible_wrapper -a bx_info -H $host_ident)
        MYSQL_VERSION=$(echo "$host_info" | awk -F':' '{print $7}')
    else
        MYSQL_VERSION=$(echo "$host_info" | awk -F':' '{print $12}')
    fi

    # php package is not found in the system
    if [[ -z $MYSQL_VERSION ]]; then
        MYSQL_MESSAGE="$(get_text "$HM0017" "mysql")"
        return 255
    fi

    # split php version 5.4.32 to separate values
    local mysql_upper=$(echo "$MYSQL_VERSION" | awk -F'.' '{print $1}')
    local mysql_middle=$(echo "$MYSQL_VERSION" | awk -F'.' '{print $2}')
    local mysql_lower=$(echo "$MYSQL_VERSION" | awk -F'.' '{print $3}')

    local mysql_union="${mysql_upper}${mysql_middle}"

    # return version of mysql server 56; 57 and etc.
    return $mysql_union
}

mysql_conditions() {
    # test versions
    # unsupported version of MySQL server
    if [[ $mysql_upper -lt 5 ]]; then
        MYSQL_MESSAGE="$(get_text "$HM0022" "$mysql_upper.$mysql_middle")"
        return 255

    # Mysql 5.x versions
    elif [[ $mysql_upper -eq 5 ]]; then

        # Unsupported MySQL version (5.0)
        if [[ $mysql_middle -lt 1 ]]; then
            MYSQL_MESSAGE="$(get_text "$HM0022" "$mysql_upper.$mysql_middle")"
            return 255

        # 5.1 ; MySQL package can be updated to version 5.5
        elif [[ $mysql_middle -eq 1 ]]; then
            MYSQL_MESSAGE="$(get_text "$HM0023" "5.5")"

        # 5.5; "MySQL package can be updated to version 5.7
        elif [[ $mysql_middle -eq 5 ]]; then
            MYSQL_MESSAGE="$(get_text "$HM0023" "5.7")"


        # 5.6; "MySQL package can be updated to version 5.7"
        elif [[ $mysql_middle -eq 6 ]]; then
            MYSQL_MESSAGE="$(get_text "$HM0023" "5.7")"

        # 5.7; "MySQL package can be updated to version 8.0"
        elif [[ $mysql_middle -eq 7 ]]; then
            MYSQL_MESSAGE="$(get_text "$HM0023" "8.0")"

        # something else
        else
            MYSQL_MESSAGE="$HM0024"
            return 255
        fi

    # MySQL is 8.0 version; nothing to do
    # The latest supported version of MySQL is already installed on the server
    elif [[ $mysql_upper -eq 8 ]]; then
            MYSQL_MESSAGE="$HM0025 ($mysql_upper.$mysql_middle)"

    # something else
    # Unsupported MySQL version
    else
        MYSQL_MESSAGE="$(get_text "$HM0022" "$mysql_upper.$mysql_middle")"
        return 255
    fi
}

get_php_min_ver_in_pool() {
    [[ -z $POOL_SERVER_LIST ]] && cache_pool_info
    [[ -z $BITRIX_ENV_TYPE ]] && get_os_type

    PHP_MIN_VERSION=256              #  error 

    IS_PHP_ERROR=0
    PHP_MESSAGES=

    IFS_BAK=$IFS
    IFS=$'\n'
    for srv_info in $POOL_SERVER_LIST; do
        srv_name=$(echo "$srv_info" | awk -F':' '{print $1}')
        
        # 255, 51, 55, 56, 57
        test_php_version "$srv_name" "$srv_info"
        php_version=$?

        [[ $DEBUG -gt 0 ]] && echo "$srv_name => PHP version is $php_version"

        # Find the smallest version of php in the pool
        [[ $php_version -lt $PHP_MIN_VERSION ]] && PHP_MIN_VERSION=$php_version

        # Save errors
        if [[ $php_version -eq 255 ]]; then
            IS_PHP_ERROR=1
            PHP_MESSAGES="$PHP_MESSAGES
 $srv_name => PHP ERROR: $PHP_MESSAGE"
        fi
    done
    IFS=$IFS_BAK
    IFS_BAK=

    # error on on servers is error for all
    [[ $IS_PHP_ERROR -gt 0 ]] && return 255

    # return php minmum version
    return $PHP_MIN_VERSION
}

get_mysql_min_ver_in_pool() {
    [[ -z $POOL_SERVER_LIST ]] && cache_pool_info
    [[ -z $BITRIX_ENV_TYPE ]] && get_os_type

    MYSQL_MIN_VERSION=256              #  error 

    IS_MYSQL_ERROR=0
    MYSQL_MESSAGES=
    MYSQL_INSTANCES=0

    # get mysql and php version and create union pool infomation;
    # minimum php version in the pool + minimum mysql version in the pool
    IFS_BAK=$IFS
    IFS=$'\n'
    for srv_info in $POOL_SERVER_LIST; do
        srv_name=$(echo "$srv_info" | awk -F':' '{print $1}')
        itis_mysql=$(echo "$srv_info" | grep -c mysql)
        [[ $itis_mysql -gt 0 ]] && MYSQL_INSTANCES=$(( $MYSQL_INSTANCES + 1 ))

        # 255, 51, 55, 56, 57
        test_mysql_version "$srv_name" "$srv_info"
        mysql_version=$?

         [[ $DEBUG -gt 0 ]] && echo "$srv_name => MYSQL version is $mysql_version"

        # Find the smallest version of php in the pool
        [[ $mysql_version -lt $MYSQL_MIN_VERSION ]] && \
            MYSQL_MIN_VERSION=$mysql_version

        # Save errors
        if [[ $mysql_version -eq 255 ]]; then
            IS_MYSQL_ERROR=1
            MYSQL_MESSAGES="$MYSQL_MESSAGES
 $srv_name => MYSQL ERROR: $MYSQL_MESSAGE"
        fi
     
    done
    IFS=$IFS_BAK
    IFS_BAK=
 
    # error on on servers is error for all
    [[ $IS_MYSQL_ERROR -gt 0 ]] && return 255

    # return mysql minmum version
    return $MYSQL_MIN_VERSION
}

# return 
# minimum ${mysqlVersion}${phpVersion}
#   255 => upgrade is not possible
# CLUSTER_MESSAGE - reason why not
# CLUSTER_RTN  - version on all cluster host is the same or not

# Blocking conditions for update
# 1. There are servers that are not connected to the master
test_upgrade_on_cluster() {
    [[ -z $POOL_SERVER_LIST ]] && cache_pool_info
    [[ -z $BITRIX_ENV_TYPE ]] && get_os_type
    CLUSTER_MESSAGE=
    CLUSTER_RTN=0          #  default mimimum supported version 
    CLUSTER_HOSTS=

    # There are servers that are not connected to the master
    if [[ -n "$POOL_UNU_SERVER_LIST" ]]; then
        server_list=$(echo "$POOL_UNU_SERVER_LIST" | \
            awk -F':' '{printf "%s, ", $1}' | sed -e 's/, $//')
        CLUSTER_MESSAGE=$(get_text "$HM0026" "$server_list")
        return 255

    fi

    get_mysql_min_ver_in_pool
    mysql_min_version=$?
    if [[ $mysql_min_version -eq 255 ]]; then
        CLUSTER_RTN=255
        CLUSTER_MESSAGE="$CLUSTER_MESSAGE
  $MYSQL_MESSAGES"
    fi

    get_php_min_ver_in_pool
    php_min_version=$?
    if [[ $php_min_version -eq 255 ]];then
        CLUSTER_RTN=255
        CLUSTER_MESSAGE="$CLUSTER_MESSAGE
  $MYSQL_MESSAGE"
    fi

    # test main module version
    if [[ $(echo "$php_min_version" | grep -c '5[456]') -gt 0 ]]; then
        test_main_module_for_php7
        test_main_module_for_php7_rtn=$?
        # Bitrix main module version __OPT1__ or better is required to use PHP
        if [[ $test_main_module_for_php7_rtn -gt 1 ]]; then
            CLUSTER_MESSAGE="$(get_text "$HM0029" "$MAIN_LOWER_VERSION")"
            CLUSTER_MESSAGE=$CLUSTER_MESSAGE"
$HM0030: $TEST_PHP7_NOTPASS"
            CLUSTER_RTN=255
        # "Cannot get the 'main' module version for these sites: "
        elif [[ $test_main_module_for_php7_rtn -gt 0 ]]; then
            CLUSTER_MESSAGE="$HM0031"
            CLUSTER_MESSAGE=$CLUSTER_MESSAGE"
$TEST_PHP7_SKIP"
            CLUSTER_RTN=255
        fi
    fi
    CLUSTER_VERSION="${mysql_min_version}${php_min_version}"
    return $CLUSTER_RTN
}

print_mysql_php_version() {
    local filter_hname="${1}"

    [[ -z "$POOL_SERVER_LIST" ]] && cache_pool_info

    print_header "Versions of installed software: MySQL and PHP."
    echo "$MENU_SPACER"
    printf "%-25s| %-20s | %4s | %7s | %7s | %7s | %s \n" "ServerName" "NetAddress" "Conn" "Ver" "MySQL" "PHP" "Roles"
    echo "$MENU_SPACER"

    PHP_VERSION=
    MYSQL_VERSION=

    IFS_BAK=$IFS
    IFS=$'\n'
    for hinfo in $POOL_SERVER_LIST; do
        hname=$(echo "$hinfo" | awk -F':' '{print $1}')
        hip=$(echo "$hinfo" | awk -F':' '{print $2}')
        hroles=$(echo "$hinfo" | awk -F':' '{print $3}')
        hconn=$(echo "$hinfo" | awk -F: '{print $7}')
        hvmver=$(echo "$hinfo" | awk -F':' '{print $8}')
        hmysql=$(echo "$hinfo" | awk -F: '{print $13}')
        hphp=$(echo "$hinfo" | awk -F: '{print $14}')

        if [[ -z "${filter_hname}" || ${filter_hname} == "all" ]]; then
            printf "%-25s| %-20s | %4s | %7s | %7s | %7s | %s \n" "$hname" "$hip" "$hconn" "$hvmver" "$hmysql" "$hphp" "$hroles"
            # get mysql version from master server
            if [[ $(echo "$hroles" | grep "mysql_master" -c) -gt 0 ]]; then
                MYSQL_VERSION=$(echo "$hmysql" | awk -F. '{printf "%s%s",$1,$2}' )
            fi
            # get php version from main web server
            if [[ $(echo "$hroles" | grep "mgmt" -c) -gt 0 ]]; then
                PHP_VERSION=$(echo "$hphp" | awk -F. '{printf "%s%s",$1,$2}')
            fi
        else
            if [[ ${filter_hname} == "${hname}" ]]; then
                printf "%-25s| %-20s | %4s | %7s | %7s | %7s | %s \n" "$hname" "$hip" "$hconn" "$hvmver" "$hmysql" "$hphp" "$hroles"
                MYSQL_VERSION=$(echo "$hmysql" | awk -F. '{printf "%s%s",$1,$2}' )
                PHP_VERSION=$(echo "$hphp" | awk -F. '{printf "%s%s",$1,$2}')
            fi
        fi
    done
    echo "$MENU_SPACER"

    IFS=$IFS_BAK
}
