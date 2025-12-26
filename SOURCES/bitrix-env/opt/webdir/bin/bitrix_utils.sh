#!/usr/bin/bash
#
export LANG=en_US.UTF-8
export TERM=linux
export NOLOCALE=yes

BASE_DIR=/opt/webdir
LOGS_DIR=$BASE_DIR/logs
TEMP_DIR=$BASE_DIR/temp
CACHE_DIR=$BASE_DIR/tmp
BIN_DIR=$BASE_DIR/bin
bx_process_script=$BIN_DIR/bx-process
bx_sites_script=$BIN_DIR/bx-sites
ansible_wrapper=$BIN_DIR/wrapper_ansible_conf
FAKE_PASSWORD=XXXXXXXXXXXX

[[ -z $LOGS_FILE ]] && LOGS_FILE=$LOGS_DIR/pool_menu.log
MENU_SPACER="------------------------------------------------------------------------------------------------------"

[[ -z $LINK_STATUS  ]] && LINK_STATUS=1
[[ ! -d $CACHE_DIR  ]] && mkdir -m 700 $CACHE_DIR

# get_text variables
[[ -f $BIN_DIR/bitrix_utils.txt ]] && \
        . $BIN_DIR/bitrix_utils.txt

get_text() {
    local txt="${1}"
    local opt1="${2}"
    local opt2="${3}"

    if [[ -n $opt1 && -z "${opt1##*/*}" ]];
    then
        opt1=$(echo "$opt1" | sed -e "s:/:\\\/:g")
    fi
    if [[ -n $opt2 && -z "${opt2##*/*}" ]];
    then
        opt2=$(echo "$opt2" | sed -e "s:/:\\\/:g")
    fi

    echo "$txt" | sed -e "s/__OPT1__/$opt1/;s/__OPT2__/$opt2/;"
}

# get ip address of host
get_ip_addr() {
    # get firt ip address for host
    ip -f inet -o addr show | cut -d\  -f 7 | cut -d/ -f 1 | grep -v '127\.0\.0\.1' | head -1
}

print_color_text() {
    _color_text="$1"
    _color_name="$2"
    _echo_opt="$3"
    [[ -z "$_color_name" ]] && _color_name='green'
    _color_number=38

    case "$_color_name" in
	green)    _color_number=32 ;;
	blue)     _color_number=34 ;;
	red)      _color_number=31 ;;
	cyan)     _color_number=36 ;;
	magenta)   _color_number=35 ;;
	*)        _color_number=39 ;;
    esac

    echo -en "\\033[1;${_color_number}m"
    echo $_echo_opt "$_color_text"
    echo -en "\\033[0;39m"
}

# save information in log file
print_log() {
    _log_message=$1
    _log_file=$2
    if [[ -n "$_log_file" ]];
    then
        log_date=$(date +'%Y-%m-%dT%H:%M:%S')
        # exclude test domain
        printf "%-14s: %6d: %s\n" "$log_date" "$$" "$_log_message" >> $_log_file
    else
        printf "%-14s: %6d: %s\n" "$log_date" "$$" "$_log_message"
    fi
}

get_os_type() {
    # os and version
    ROCKY_RELEASE_FILE=/etc/rocky-release
    ALMA_RELEASE_FILE=/etc/almalinux-release
    ORACLE_RELEASE_FILE=/etc/oracle-release
    CENTOS_RELEASE_FILE=/etc/centos-release
    if [ -f "${ROCKY_RELEASE_FILE}" ];
    then
	OS1=$(awk '{print $1}' ${ROCKY_RELEASE_FILE} | xargs echo -n)
	OS2=$(awk '{print $2}' ${ROCKY_RELEASE_FILE} | xargs echo -n)
	OS=${OS1}' '${OS2} # Rocky Linux
	OS_VERSION=$(awk '{print $4}' ${ROCKY_RELEASE_FILE} | awk -F'.' '{print $1}') # 9
	OS_TYPE=$(cat ${ROCKY_RELEASE_FILE} | grep Rocky -c) # 1
    fi
    if [ -f "${ALMA_RELEASE_FILE}" ];
    then
	OS=$(awk '{print $1}' ${ALMA_RELEASE_FILE} | xargs echo -n) # AlmaLinux
	OS_VERSION=$(awk '{print $3}' ${ALMA_RELEASE_FILE} | awk -F'.' '{print $1}') # 9
	OS_TYPE=$(cat ${ALMA_RELEASE_FILE} | grep AlmaLinux -c) # 1
    fi
    if [ -f "${ORACLE_RELEASE_FILE}" ];
    then
	OS1=$(awk '{print $1}' ${ORACLE_RELEASE_FILE} | xargs echo -n)
	OS2=$(awk '{print $2}' ${ORACLE_RELEASE_FILE} | xargs echo -n)
	OS=${OS1}' '${OS2} # Oracle Linux
	OS_VERSION=$(awk '{print $5}' ${ORACLE_RELEASE_FILE} | awk -F'.' '{print $1}') # 9
	OS_TYPE=$(cat ${ORACLE_RELEASE_FILE} | grep Oracle -c) # 1
    fi
    if [ -f "${CENTOS_RELEASE_FILE}" ];
    then
	OS1=$(awk '{print $1}' ${CENTOS_RELEASE_FILE} | xargs echo -n)
	OS2=$(awk '{print $2}' ${CENTOS_RELEASE_FILE} | xargs echo -n)
	OS=${OS1}' '${OS2} # CentOS Stream
	OS_VERSION=$(awk '{print $4}' ${CENTOS_RELEASE_FILE} | awk -F'.' '{print $1}') # 9
	OS_TYPE=$(cat ${CENTOS_RELEASE_FILE} | grep CentOS -c) # 1
    fi
    # is OpenVZ installation
    IS_OPENVZ=$( [[ -f /proc/user_beancounters  ]] && echo 1 || echo 0  )
    # Hardware type
    HW_TYPE=general
    [[ $IS_OPENVZ -gt 0  ]] && HW_TYPE=openvz
    # x86_64 or i386
    IS_X86_64=$(uname -a | grep -wc 'x86_64')
    [[ -f /etc/profile ]] && BITRIX_ENV_TYPE=$(grep BITRIX_ENV_TYPE /etc/profile | awk -F'=' '{print $2}')
    [[ -z $BITRIX_ENV_TYPE ]] && BITRIX_ENV_TYPE=general
}

# set logo
get_logo() {
    logo="$BU0001"
    [[ -z $BITRIX_ENV_TYPE ]] && get_os_type
    if [[ $BITRIX_ENV_TYPE == "crm" ]];
    then
	logo="$BU0002"
    fi

    logov=$(egrep -o 'BITRIX_VA_VER=[0-9\.]+'  /root/.bash_profile | awk -F'=' '{print $2}' )
    export BITRIX_VA_VER=$logov
    export BITRIX_ENV_TYPE

    echo -e $logo " version "$logov
}

print_header() {
    _header_text=$1
    echo -e '\t\t' "$_header_text"
    echo
}

print_verbose() {
    _verbose_type=$1
    _verbose_message=$2
    [[ -z $VERBOSE ]] && VERBOSE=0
    if [[ $VERBOSE -gt 0 ]];
    then
	print_color_text "$_verbose_type" green -n
	echo ": $_verbose_message"
    fi
}

# error message for all possible menus
error_pick() {
    notice_message="$BU2001" ;
}

# print error message
# as we use cycles, must make sure that the user sees an error
print_message() {
    _input_message=${1}       # prompt in read output
    _print_message=${2}       # colored text like a notice
    _input_format=${3}        # can add option to read 
    _input_key=${4}           # saved variable name
    _input_default=${5}       # default value for variable
    _read_input_key=
    _notset_input_key=0       # printf change empty string

    [[ -z "$_input_message" ]] && _input_message="$BU1001"

    # print notice message
    [[ -n "$_print_message" ]] && print_color_text "$_print_message" blue -e
    echo

    # get variable value from user
    # -r If this option is given, backslash does not act as an escape character
    read $_input_format -r -p "$_input_message" _read_input_key
    if [[ -z "$_read_input_key" ]];
    then
        _notset_input_key=1
        [[ -n "$_input_default" ]] && _notset_input_key=2
        [[ $DEBUG -gt 0 ]] && echo "$BU2002; _notset_input_key=$_notset_input_key"
    else
        # %q - print the associated argument shell-quoted, reusable as input
        _read_input_key=$(printf "%q" "$_read_input_key")
    fi

    # if empty set variable to default value
    if [[ $_notset_input_key -eq 2 ]];
    then
        [[ $DEBUG -gt 0 ]] && echo "_input_key="$_input_default
        eval "$_input_key="$_input_default
    else
        eval "$_input_key="$_read_input_key
        [[ $DEBUG -gt 0 ]] && echo "_input_key="$_read_input_key
    fi
    echo
}

# password can't be empty
ask_password_info() {
    _password_key=$1
    _password_val=$2

    print_color_text "$BU0003" red
    echo
    _password_set=0
    _limit_request=3
    _current_tequest=0
    local _password_1=
    local _password_2=
    until [[ ( $_current_tequest -gt $_limit_request ) || ( $_password_set -eq 1 ) ]]; do
        _current_tequest=$(( $_current_tequest+1 ))
        print_message "$(get_text "$BU0004" "$_password_key")" "" "-s" _password_1
        print_message "$(get_text "$BU0005" "$_password_key")" "" "-s" _password_2
        echo
        [[  ( -n "$_password_1" )  &&  ( "$_password_1" = "$_password_2" ) ]] && _password_set=1
        if [[ "$_password_1" != "$_password_2" ]];
        then
            print_color_text "$BU2003" red
            _password_1=
            _password_2=
        fi
        if [[ -z "$_password_1" ]];
        then
            print_color_text "$BU2004" red
        fi
    done

    if [[ $_password_set -eq 1 ]];
    then
        _password_1=$(printf "%q" "$_password_1")
        eval "$_password_val="$_password_1
        return 0
    else
        print_message "$BU1001" "$BU2005" "" any_key
        return 1
    fi
}

# client settings
get_client_settings() {
    client_settings_file=/etc/ansible/ansible-roles
    IN_POOL=0
    if [[ -f $client_settings_file ]];
    then
	host_data=$(grep -v '^#' $client_settings_file)
	CLIENT_ID=$(echo "$host_data"     | grep '^host_id '        | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')      # login of host for basic auth on master
	CLIENT_PASSWD=$(echo "$host_data" | grep '^host_pass '      | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')      # password of host for basic auth on master
	CLIENT_INT=$(echo "$host_data"    | grep '^host_ether '     | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')      # management interface name
	CLIENT_IP=$(echo "$host_data"     | grep '^host_netaddr '   | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')      # management ip address
	MASTER_IP=$(echo "$host_data"     | grep '^master_netaddr ' | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')      # master ip address
	MASTER_NAME=$(echo "$host_data"   | grep '^master '         | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')      # master name
	MASTER_PORT=$(echo "$host_data"   | grep '^master_port '    | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')
	CLIENT_NAME=$(echo "$host_data"   | grep '^hostname '       | awk -F'=' '{print $2}' | sed -e 's/^\s\+//;s/\s\+$//')      # master name
	IS_MASTER=$(echo "$host_data"     | grep '^groups' | grep -cwi 'bitrix-mgmt')
	IS_PUSH=$(echo "$host_data"       | grep '^groups' | grep -cwi 'bitrix-push')
	IN_POOL=1
    fi
}

# get information about pool configuration
# output:
#  short_name:net_address:role1,role2,..:host_id:bx_conn:bx_version:bx_passwd:ip1,ip2...
# example:
#  h01w:h01w.bx:mgmt,mysql_master_1,web:1397225355:4.4-51
#
# NOTICE: error stops the execution of the script!!!!
# fill out variable POOL_SERVER_LIST
# fill out variable POOL_UNU_SERVER_LIST ( contains out of day servers )
get_pool_info() {
    pool_data=$($ansible_wrapper -a view)

    # test error 
    err=$(echo "$pool_data" | grep '^error:'   | sed -e "s/^error://" )
    # test message
    msg=$(echo "$pool_data" | grep '^message:' | sed -e "s/^message://")
    # exit if error found
    if [[ -n "$err" ]]; then
        print_message "$BU2006" "$msg" "" any_key
        exit 1
    fi
    POOL_SERVER_LIST=""             # working servers
    POOL_UNU_SERVER_LIST=""         # unused servers

    # add host info to output
    data=$(echo "$pool_data" | grep '^host:' | sed -e "s/^host://")

    IFS_BAK=$IFS
    IFS=$'\n'
    for srv_info in $data; do

        srv_name=$(echo $srv_info | awk -F':' '{print $1}')

        # get additional information
        # /opt/webdir/bin/wrapper_ansible_conf -a bx_info -H h01w
        # bx_variables:h01w:4.4-51:Apr 01, 2014:eth0=192.168.1.193,eth1=10.1.0.3:5.5.40:5.4.34
        srv_bx_info=$($ansible_wrapper -a bx_info -H $srv_name)
        srv_err=$(echo "$srv_bx_info" | grep '^error:'   | sed -e "s/^error://")
        srv_msg=$(echo "$srv_bx_info" | grep '^message:' | sed -e "s/^message://")
    
        srv_conn="N"            # connected to server or not by ssh
        srv_vers="unk"          # version of bitrix env, that installed on the server
        srv_base_ver="unk"      # main part of version (for test)
        srv_pwd="unk"           # need to change bitrix password
        srv_net="unk"           # ip address on the server
        srv_bx_uid="unk"        # uid for user bitrix
        srv_bx_php='unk'        # php version on the server
        srv_bx_mysql='unk'      # mysql version on the server
        srv_bx_sph='unk'        # sphinx version
        srv_bx_pgsql='unk'      # postgresql version
        [[ -z "$srv_err" ]] && srv_conn="Y"
        srv_menu_info=

        if [[ -z $srv_err ]];
        then
            srv_conn="Y"
            srv_vers=$(     echo "$srv_bx_info" | awk -F':' '{print $3}')
            srv_base_ver=$( echo "$srv_vers"    | awk -F'.' '{print $1}')
            srv_pwd_info=$( echo "$srv_bx_info" | awk -F':' '{print $4}' | grep -ic 'must be changed')
            srv_bx_mysql=$( echo "$srv_bx_info" | awk -F':' '{print $7}')
            srv_bx_php=$(   echo "$srv_bx_info" | awk -F':' '{print $8}')
            srv_bx_sph=$(   echo "$srv_bx_info" | awk -F':' '{print $14}')
            srv_bx_pgsql=$( echo "$srv_bx_info" | awk -F':' '{print $15}')

            # test root password
            if [[ $srv_pwd_info -gt 0 ]];
            then
                srv_pwd="error"
            else
                srv_pwd="ok"
            fi
            
            srv_net=$(echo "$srv_bx_info" | awk -F':' '{print $5}')
            srv_bx_uid=$(echo "$srv_bx_info" | awk -F':' '{print $6}')

            srv_menu_info="$srv_info:$srv_conn:$srv_vers:$srv_pwd:$srv_net:$srv_bx_uid"
            srv_menu_info=$srv_menu_info":$srv_base_ver:$srv_bx_mysql:$srv_bx_php:$srv_bx_sph:$srv_bx_pgsql"
 
            if [[ ( $srv_base_ver -ge 5 ) && ( $srv_pwd == "ok" ) ]];
            then
               POOL_SERVER_LIST=$POOL_SERVER_LIST"
$srv_menu_info"
            else
                srv_menu_info=
            fi
        fi

        if [[ -z $srv_menu_info ]];
        then
            srv_error_descr=""
            if [[ $srv_base_ver -lt 5 ]];
            then
                srv_error_descr="version,"
            fi

            if [[ $srv_pwd != "ok" ]];
            then
                srv_error_descr=$srv_error_descr"password,"
            fi

            if [[ $srv_conn != 'Y' ]];
            then
                srv_error_descr=ssh_connection
            fi

            srv_error_descr=$(echo "$srv_error_descr" | sed -e 's/,$//')
            srv_menu_info="$srv_info:$srv_conn:$srv_vers:$srv_pwd:$srv_net:$srv_bx_uid:$srv_error_descr"
            POOL_UNU_SERVER_LIST=$POOL_UNU_SERVER_LIST"
$srv_menu_info"
        fi
    done
}

cache_pool_info() {
    POOL_UNU_SERVER_LIST=
    POOL_SERVER_LIST=
    POOL_SERVERS_CACHE=$CACHE_DIR/pool_servers.cache
    POOL_UNUSED_CACHE=$CACHE_DIR/pool_unused.cache
    POOL_CACHE_TTL=3600

    test_cache_file $POOL_SERVERS_CACHE $POOL_CACHE_TTL
    test_cache_servers=$?
    test_cache_file $POOL_UNUSED_CACHE $POOL_CACHE_TTL
    test_cache_unused=$?

    # not create cache while ansible-playbook running
    is_ansible_running
    if [[ $? -gt 0 ]];
    then
        get_pool_info
        return 0
    fi

    if [[ ( $test_cache_servers -gt 0 ) || ( $test_cache_unused -gt 0 ) || ( $DEBUG -gt 0 ) ]];
    then
        get_pool_info
        echo "$POOL_SERVER_LIST" > $POOL_SERVERS_CACHE
        echo "$POOL_UNU_SERVER_LIST" > $POOL_UNUSED_CACHE
    else
        POOL_UNU_SERVER_LIST=$(cat $POOL_UNUSED_CACHE)
        POOL_SERVER_LIST=$(cat $POOL_SERVERS_CACHE)
    fi
}

# get ansible ssh key
# fill out variables:
# ANSIBLE_SSHKEY_PRIVATE
# ANSIBLE_SSHKEY_PUBLIC
get_ansible_sshkey() {
    pool_sshkey_info=$($ansible_wrapper -a key)  # get sshkey that used in the pool
    pool_sshkey_error=$(echo "$pool_sshkey_info" | grep '^error:' | sed -e 's/^error://')
  
    # test error
    if [[ -n "$pool_sshkey_error" ]];
    then
        print_message "$BU1001" "$BU2007" "" any_key
        exit
    fi

    ANSIBLE_SSHKEY_PRIVATE=$(echo "$pool_sshkey_info" | grep '^info:sshkey:' | sed -e 's/^info:sshkey://')
    ANSIBLE_SSHKEY_PUBLIC=$ANSIBLE_SSHKEY_PRIVATE".pub"

    # test if file exists
    for _sshkey in $ANSIBLE_SSHKEY_PRIVATE $ANSIBLE_SSHKEY_PUBLIC; do
        if [[ ! -f $ANSIBLE_SSHKEY_PRIVATE ]];
        then
            print_message "$BU1001" "$(get_text "$BU2008" $_sshkey)" "" any_key
        fi
    done
}

# prints formatted output for POOL_SERVER_LIST
# ex.
# h01w:h01w.bx:mgmt,mysql_master_1,web:1397293177:Y:5.0-2:ok:eth0=192.168.1.193,eth1=10.1.0.4 
# m02:192.168.2.17::1397293301:Y:5.0-0:ok:eth0=192.168.2.17,eth1=10.1.0.2
#
print_pool_info() {
    srv_rols_exclude=$1    # exclude server with defined role
    srv_rols_include=$2    # include only servers with defined role

    if [[ -z "$POOL_SERVER_LIST" ]];
    then
        cache_pool_info
    fi
    #echo "$POOL_SERVER_LIST"
    #exit
  
    print_header "$BU0006"
    echo "$MENU_SPACER"
    printf "%-25s| %-20s | %4s | %7s | %10s | %3s | %s \n" "ServerName" "NetAddress" "Conn" "Ver" "Passwords" "Uid" "Roles"
    echo "$MENU_SPACER"
    IFS_BAK=$IFS
    IFS=$'\n'
    for srv_info in $POOL_SERVER_LIST; do
        # 1 - vm04.ksh.bx:
        # 2 - 172.17.10.104:
        # 3 - mgmt,mysql_master_1,web:
        # 4 - 1503919366_V37FzFyfwD:
        # 5 - vm04.ksh.bx:
        # 6 - tranformer options
        # 7 - Y
        # 8 - 7.1-0:
        # 9 - ok:
        # 10 - enp0s3=10.0.2.15,enp0s8=172.17.10.104,enp0s9=192.168.100.36:
        # 11 - 600:
        # 12 - 7:
        # 13 - 5.7.18
        # 14 - 7.0.19:
        # 15 - not_installed
        srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # server identifier in ansible inventory
        srv_neta=$(echo "$srv_info" | awk -F':' '{print $2}') # netaddress
        srv_rols=$(echo "$srv_info" | awk -F':' '{print $3}') # server roles
        srv_time=$(echo "$srv_info" | awk -F':' '{print $4}' | awk -F'_' '{print $1}') # creation time
        srv_date=$(date -d @$srv_time +"%d-%m-%Y")
        hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
        srv_conn=$(echo "$srv_info" | awk -F':' '{print $7}') # server connected to pool or not
        srv_bver=$(echo "$srv_info" | awk -F':' '{print $8}') # version virt env on server
        srv_bpwd=$(echo "$srv_info" | awk -F':' '{print $9}') # bitrix user password status
        srv_bips=$(echo "$srv_info" | awk -F':' '{print $10}') # host interfaces and ip address
        srv_buid=$(echo "$srv_info" | awk -F':' '{print $11}') # uid for bitrix user
        srv_base_ver=$(echo "$srv_info" | awk -F':' '{print $12}') # version of bitrix-env
        is_printed=0
        if [[ -n "$srv_rols_exclude" ]];
        then
            [[ $(echo "$srv_rols" | grep -c "$srv_rols_exclude") -eq 0 ]] && is_printed=1
        else
            if [[ -n "$srv_rols_include" ]];
            then
                [[ $(echo "$srv_rols" | grep -c "$srv_rols_include") -gt 0 ]] && is_printed=1
            else
                is_printed=1
            fi
        fi

        if [[ $is_printed -gt 0 ]];
        then
            printf "%-25s| %-20s | %4s | %7s | %10s | %3s | %s \n" "$hostname" "$srv_neta" "$srv_conn" "$srv_bver" "$srv_bpwd" "$srv_buid" "$srv_rols"
        fi
    done
    IFS=$IFS_BAK
    IFS_BAK=
    echo "$MENU_SPACER"

    # print unused servers
    if [[ -n "$POOL_UNU_SERVER_LIST" ]];
    then
        echo
        print_color_text "$BU0007" red
        echo "$MENU_SPACER"
        printf "%-25s| %-20s | %s \n" "ServerName" "NetAddress" "Errors"
        echo "$MENU_SPACER"
        IFS_BAK=$IFS
        IFS=$'\n'
 
        for srv_info in $POOL_UNU_SERVER_LIST; do
            srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # short server name
            srv_neta=$(echo "$srv_info" | awk -F':' '{print $2}') # netaddress
            hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
            srv_bver=$(echo "$srv_info" | awk -F':' '{print $7}') # version virt env on server
            srv_error_descr=$(echo "$srv_info" | awk -F':' '{print $11}') # uid for bitrix user
            printf "%-25s| %-20s" "$hostname" "$srv_neta"
            err_r=1
            for err in $(echo "$srv_error_descr" | sed -e 's/,/\n/g'); do
                if [[ "$err" == "password" ]];
                then
                    err_message="$BU2009"
                elif [[ "$err" == "version" ]];
                then
                    err_message="$BU2010"
                elif [[ "$err" == "ssh_connection" ]];
                then
                    err_message="$BU2011"
                else
                    err_message=$err
                fi

                if [[ $err_r -eq 1 ]];
                then
                    printf " | %02d. %s\n" "$err_r" "$err_message"
                else
                    printf "%-25s| %-20s | %02d. %s\n" "" "" "$err_r" "$err_message"
                fi

                err_r=$(($err_r+1))
            done
        done
        IFS=$IFS_BAK
        IFS_BAK=
        echo "$MENU_SPACER"
    fi
}

# execute background task and print information about status
exec_pool_task() {
    _task_exe=$1
    _task_txt=$2

    _task_inf=$(eval $_task_exe)
    _task_err=$(echo "$_task_inf" | grep '^error:' | sed -e "s/^error://")
    _task_msg=$(echo "$_task_inf" | grep '^message:' | sed -e "s/^message://")
    _task_dat=$(echo "$_task_inf" | grep '^info:' | sed -e "s/^info://")
  
    if [[ -n "$_task_err" ]];
    then
        print_message "$(get_text "$BU2012" "$_task_txt")" "$_task_msg" "" any_key
        exit 1
    fi

    _task_id=$(echo "$_task_dat" | awk -F':' '{print $2}')
    _task_pid=$(echo "$_task_dat" | awk -F':' '{print $3}')
    _task_status=$(echo "$_task_dat" | awk -F':' '{print $6}')

    echo "$BU2014"
    printf "%-10s: %s\n" "$BU2015" "$_task_id"
    printf "%-10s: %s\n" "$BU2016" "$_task_pid"
    printf "%-10s: %s\n" "$BU2017" "$_task_status"
    echo "$(get_text "$BU2013" "$_task_txt")"
    _task_exe=
    _task_txt=
    print_message "$BU1001" "" "" any_key
}

# get list of running tasks filter by type
get_task_by_type() {
    _task_type=$1
    _task_info_lock=$2
    _task_info_var=$3
 
    _process_inf=$($bx_process_script -a list -t $_task_type)
    _process_err=$(echo "$_process_inf" | grep '^error:' | sed -e "s/^error://")
    _process_msg=$(echo "$_process_msg" | grep '^message:' | sed -e "s/^message://")
    _process_data=$(echo "$_process_inf" | grep '^info:' | sed -e "s/^info://" | grep -i 'running')

    eval "$_task_info_lock=0"
    eval "$_task_info_var='$_process_data'"
    [[ -n "$_process_data" ]] && eval "$_task_info_lock=1"
}

# print running task information for human
print_task_by_type() {
    _p_task_type=$1
    _p_task_lock=$2
    _p_task_info=$3

    if [[ -z "$_p_task_lock" ]];
    then
        get_task_by_type "$_p_task_type" "_p_task_info" "_p_task_lock"
    fi

    if [[ $_p_task_lock -eq 1 ]];
    then
        print_color_text "$(get_text "$BU0063" "$_p_task_type")" red

        echo "$MENU_SPACER"
        printf "%-25s| %-25s | %s\n" "$BU0008" "$BU0009" "$BU0010"
        echo "$MENU_SPACER"

        IFS_BAK=$IFS
        IFS=$'\n'
        for line in $_p_task_info; do
            _task_iden=$(echo $line| awk -F':' '{print $2}')      # task id
            _task_time=$(echo $line| awk -F':' '{print $4}')    # task started at
            _task_date=$(date -d @$_task_time +"%d/%m/%Y %H:%M")
            _task_step=$(echo $line| awk -F':' '{print $NF}')   # current operations
            printf "%-25s| %-25s | %s\n" "$_task_iden" "$_task_date" "$_task_step"
        done
        IFS=$IFS_BAK
        IFS_BAK=

        # test
        echo $MENU_SPACER
        print_color_text "$BU1001" red
    fi
}

# get information about network interfaces which is configured on the server
get_local_network() {
    local check_link_status="${1:-1}"   # test link status: 0 - don't check; 1 - check
    EXCLUDE_INT='\(lo\)'                # exclude interface names
    NONHW_INT='\(ppp\)'                 # exclude test of interface status by ethtool
    HOST_NETWORK=0                      # number of IP addresses on the host
    HOST_INT_COUNT=0                    # number interfaces with IP address on the host
    HOST_NETWORK_INFO=                  # list of information about interfaces on the host
                                        # id#interface_name#mac_address#ipv4 ...
    HOST_IPS=                           # list of matches between the interfaces and IP addresses: int1=ip1 ...    
    
    # CLIENT_INT/CLIENT_IP
    get_client_settings
    [[ $DEBUG -gt 0 ]] && echo "Test link status=$check_link_status"

    # test openssl installation
    OPENVZ_INSTALL=$([[ -f /proc/user_beancounters  ]] && echo 1 || echo 0)

    local ip_link_list=$(ip link show | egrep -o '^[0-9]+:\s+\S+' | sed "s/^\s\+//;s/\s\+$//;s/://g;s/@.*//g" | awk '{printf "%s\n", $2}' | grep -v "$EXCLUDE_INT")
    [[ $DEBUG -gt 0 ]] && echo "ip_link_list=$ip_link_list"
    local int_count=$(echo "$ip_link_list" | wc -l)

    # test network interfaces
    if [[ $int_count -eq 0 ]];
    then
        print_color_text "$BU2018" red -e
        return 1
    fi
  
    # header
    print_color_text "$BU0012" green
    echo "$MENU_SPACER"
    printf "%10s | %10s | %12s | %20s | %s\n" "$BU0013" "$BU0014" "$BU0015" "$BU0016" "$BU0017"
    echo "$MENU_SPACER"

    # process interfaces
    local int_name=
    # eth0, eth1, eth2
    for int_name in $ip_link_list; do
        local int_speed="not_defined"
        local int_link="yes"
        local int_mac="void"
        local int_data=$(ip addr show $int_name | sed -e 's/^\s\+//')

        # test inetrfaces, exclude non-hardware interfaces and openvz interfaces
        if [[ ( $(echo "$int_name" | grep -c "$NONHW_INT") -eq 0 ) && ( $OPENVZ_INSTALL -eq 0 ) ]];
        then
            ethtool_info=$(ethtool $int_name | egrep -o '(Speed|Link detected):\s+\S+')
            int_speed=$(echo "$ethtool_info" | awk -F':' '/Speed/{print $2}' | sed -e 's/://g;s/\s\+//g;')
            int_link=$( echo "$ethtool_info" | awk -F':' '/Link/{print $2}'  | sed -e 's/://g;s/\s\+//g;' )
            int_mac=$(echo "$int_data" | egrep -o "ether\s+\S+" | awk '{print $2}')
            [[ $DEBUG -gt 0 ]] && echo "+ int_name=$int_name"
        else
            [[ $DEBUG -gt 0 ]] && echo "- int_name=$int_name"
        fi

        if [[ ( $check_link_status -eq 1 ) && ( "$int_link" != "yes" ) ]];
        then
            [[ $DEBUG -gt 0 ]] && echo "$(get_text "$BU2019" "$int_name" "$int_link")"
            continue
        fi

        # test sub-interfaces
        # eth0:1 or eth0 - several times
        local int_subs=$(echo "$int_data" | grep '^inet\s\+' | awk '{print $NF}')
        local int_subs_count=$(echo "$int_subs" | wc -l)
        local int_subs_unique=$(echo "$int_subs" | sort | uniq -c | sed -e "s/^\s\+//;s/\s\+$//;s/\s\+/=/")

        [[ $DEBUG -gt 0 ]] && echo "--> int_speed=$int_speed int_link=$int_link int_mac=$int_mac int_subs_count=$int_subs_count"
    
        # processing sub interfaces; different records in HOST_NETWORK_INFO and HOST_IPS lists
        if [[ $int_subs_count -gt 1 ]];
        then
            local sub_name=
            for sub_name_info in $int_subs_unique; do
                sub_cnt=$(echo "$sub_name_info" | awk -F'=' '{print $1}')
                sub_name=$(echo "$sub_name_info" | awk -F'=' '{print $2}')
                local sub_addr=$(echo "$int_data" | grep "$sub_name$" | egrep -o "inet [0-9\.]+" | awk '{print $2}')

                # IPADDR2/PREFIX2 in sysconfig file
                if [[ $sub_cnt -gt 1 ]];
                then
                    sub_id=0
                    local sa=
                    for sa in $sub_addr; do
                        [[ $sub_id -gt 0 ]] && continue
                        [[ $DEBUG -gt 0  ]] && echo "----> sub_name=${sub_name}/$sub_id sub_addr=$sa"
                        if [[ ( -n $sa ) && ( $(echo "$sa" | awk -F'.' '{print $1}') -ne 127 ) ]];
                        then
                            HOST_INT_COUNT=$(($HOST_INT_COUNT+1))
                            HOST_IPS=$HOST_IPS"$sub_name=$sa "
                            HOST_NETWORK=$(($HOST_NETWORK+1))
                            HOST_NETWORK_INFO=$HOST_NETWORK_INFO"$HOST_INT_COUNT#$sub_name#$int_mac#$sa "

                            if [[ $sub_name == "$CLIENT_INT" ]];
                            then
                                status_int=primary
                                if [[ $sa != "$CLIENT_IP" ]]; then
                                    status_int="primary changed"
                                fi
                                printf "%10s | %10s | %12s | %20s | %s ($status_int)\n" "$sub_name" "$int_link" "$int_speed" "$int_mac" "$sa"
                            else
                                printf "%10s | %10s | %12s | %20s | %s\n" "$sub_name" "$int_link" "$int_speed" "$int_mac" "$sa"
                            fi
                        fi
                        sub_id=$(( $sub_id + 1 ))
                    done
                else
                    [[ $DEBUG -gt 0 ]] && echo "----> sub_name=$sub_name sub_addr=$sub_addr"

                    # ip address is found
                    if [[ ( -n $sub_addr ) && ( $(echo "$sub_addr" | awk -F'.' '{print $1}') -ne 127 ) ]];
                    then
                        HOST_INT_COUNT=$(($HOST_INT_COUNT+1))
                        HOST_IPS=$HOST_IPS"$sub_name=$sub_addr "
                        HOST_NETWORK=$(($HOST_NETWORK+1))
                        HOST_NETWORK_INFO=$HOST_NETWORK_INFO"$HOST_INT_COUNT#$sub_name#$int_mac#$sub_addr "
 
                        if [[ $sub_name == "$CLIENT_INT" ]];
                        then
                            status_int=primary
                            if [[ $sub_addr != "$CLIENT_IP" ]];
                            then
                                status_int="primary changed"
                            fi
                             printf "%10s | %10s | %12s | %20s | %s ($status_int)\n" "$sub_name" "$int_link" "$int_speed" "$int_mac" "$sub_addr"
                         else
                            printf "%10s | %10s | %12s | %20s | %s\n" "$sub_name" "$int_link" "$int_speed" "$int_mac" "$sub_addr"
                        fi
                    fi
                    # ip address is not found => skip
                    # Notice: need to add support for inet6 
                fi
            done
        else
            local int_addr=$(echo "$int_data" | grep "$int_name$" | egrep -o "inet [0-9\.]+" | awk '{print $2}')
            # ip address is found
            if [[ ( -n $int_addr ) && ( $(echo "$int_addr" | awk -F'.' '{print $1}') -ne 127 ) ]];
            then
                HOST_INT_COUNT=$(($HOST_INT_COUNT+1))
                HOST_IPS=$HOST_IPS"$int_name=$int_addr "
                HOST_NETWORK=$(($HOST_NETWORK+1))
                HOST_NETWORK_INFO=$HOST_NETWORK_INFO"$HOST_INT_COUNT#$int_name#$int_mac#$int_addr "
 
                if [[ $int_name == "$CLIENT_INT" ]];
                then
                    status_int=primary
                    if [[ $int_addr != "$CLIENT_IP" ]];
                    then
                        status_int="primary changed"
                    fi
                    printf "%10s | %10s | %12s | %20s | %s ($status_int)\n" "$int_name" "$int_link" "$int_speed" "$int_mac" "$int_addr"
                else
                    printf "%10s | %10s | %12s | %20s | %s\n" "$int_name" "$int_link" "$int_speed" "$int_mac" "$int_addr"
                fi
            fi
            # ip address is not found => skip
            # Notice: need to add support for inet6 
        fi
    done
    echo "$MENU_SPACER"

    # skip final spaces
    HOST_IPS=$(echo "$HOST_IPS" | sed -e 's/\s\+$//')
    HOST_NETWORK_INFO=$(echo "$HOST_NETWORK_INFO" | sed -e 's/\s\+$//')
    # return 0
}

# get site password file; there is 2 options:
# my_cnf - my.cnf file for mysql connect
# password_file - plain text file with one string - password
get_site_my_connect() {
    local _site_name="${1}"
    local _site_root="${2}"
    local _tmpdir="${3:-/opt/webdir/tmp}"
    local _file_type="${4:-my_cnf}"

    $bx_sites_script -a $_file_type --site "$_site_name" -r "$_site_root" --tmpdir $_tmpdir | grep '^bxSite:db:'
}

# create random string
create_random_string() {
    randLength=8
    rndStr=</dev/urandom tr -dc A-Za-z0-9 | head -c $randLength
    echo $rndStr
}

# test password on localhost and start change process
test_passw_bitrix_localhost() {
    test_pwd=$(chage -l bitrix)
  
    _test_Last_password_change=$(echo "$test_pwd" | awk -F':' '/Last password change/{print $2}' | sed 's/^\s\+//;s/\s\+$//;')

    if [[ $(echo "$_test_Last_password_change" | grep -ic 'password must be changed') -gt 0 ]];
    then
        [[ $DEBUG -eq 0 ]] && clear
        print_color_text "$BU0018" red
        passwd bitrix
        if [[ $? -gt 0 ]];
        then
            print_message "$BU1001" "$BU0018" "" any_key
            exit 1
        fi
    fi
}

# send client setting to master
update_client_settings() {
    client_address="${1}"

    http_url="https://$MASTER_IP:$MASTER_PORT/change?client_ip=$client_address"
    http_cmd="/usr/bin/curl -s"
    http_conn_time=10
    http_max_time=30
    http_user_agent="Updater/$CLIENT_NAME"
    _update_temp=/tmp/update_$(date +%s)
    curl --fail --silent --show-error -A $http_user_agent --connect-timeout $http_conn_time --max-time $http_max_time --user $CLIENT_ID:$CLIENT_PASSWD --insecure --write-out "http_code=%{http_code}" $http_url > $_update_temp 2>&1
    curl_exit=$?

    if [[ $curl_exit -gt 0 ]];
    then
	print_log "curl return error code=$curl_exit: $(head -1 $_update_temp)" $LOGS_FILE
	UPDATE_SEND=0
	# test returned code: 401 (incorrect host login and password)
	[[ $curl_exit -eq 22 ]] && UPDATE_SEND=255
	rm -f $_update_temp
    else
	UPDATE_SEND=1
	rm -f $_update_temp
    fi
    #echo $UPDATE_SEND
}

# save master settings in master log
update_master_settings() {
    master_address="${1}"
    master_id="${2}"

    #print_log "$ansible_wrapper -a update_network --host_id $master_id -i $master_address" $LOGS_FILE

    update_inf=$($ansible_wrapper -a update_network --host_id $master_id -i $master_address)
    update_err=$(echo "$update_inf" | grep '^error:' | sed -e 's/^error://')
    if [[ -z "$update_err" ]];
    then
	UPDATE_SEND=1
    else
	UPDATE_SEND=0
    fi
}

# test sites configuration before start create mysql cluster
# STOP_BY_KERNELS - doesn't create cluster because kernel sites > 1
# STOP_BY_SCALE   - doesn't create cluster because there are sites without scale module
# STOP_BY_CLUSTER - doesn't create cluster because there are sites without scale module
test_sites_config() {
  sites_test=$($bx_sites_script -a cluster_test)

  STOP_BY_KERNELS=$(echo "$sites_test" | awk -F':' '/:general:/{print $3}')
  STOP_BY_CLUSTER=$(echo "$sites_test" | awk -F':' '/:general:/{print $4}')
  STOP_BY_SCALE=$(echo "$sites_test" | awk -F':' '/:general:/{print $5}')

  STOP_ALL_CONDITIONS=0
  if [[ $STOP_BY_KERNELS -gt 1 ]];
  then
    print_color_text "$BU0019" blue
    print_color_text "$(get_text "$BU0020" "$STOP_BY_KERNELS")" red
    echo $MENU_SPACER
    printf "%20s | %s\n" "$BU0021" "$BU0022"
    echo $MENU_SPACER
    for def in $(echo "$sites_test" | awk -F':' '/:kernels:/{print $3}' | sed -e 's/;/ /g;'); do
      printf "%20s | %s\n" "$(echo $def | awk -F'=' '{print $1}')" "$(echo $def | awk -F'=' '{print $2}')"
    done
    echo $MENU_SPACER
    STOP_ALL_CONDITIONS=$(( $STOP_ALL_CONDITIONS+1 ))
  fi

  if [[ $STOP_BY_SCALE -gt 0 ]];
  then
    print_color_text "$BU0023" blue
    print_color_text "$(get_text "$BU0024" $STOP_BY_SCALE)" red
    echo $MENU_SPACER
    printf "%20s | %s\n" "$BU0021" "$BU0022"
    echo $MENU_SPACER
    for def in $(echo "$sites_test" | awk -F':' '/:scale:/{print $3}' | sed -e 's/;/ /g;'); do
      printf "%20s | %s\n" "$(echo $def | awk -F'=' '{print $1}')" "$(echo $def | awk -F'=' '{print $2}')"
    done
    echo $MENU_SPACER
    STOP_ALL_CONDITIONS=$(( $STOP_ALL_CONDITIONS+1 ))
  fi

  if [[ $STOP_BY_CLUSTER -gt 0 ]];
  then
    print_color_text "$BU0025" blue
    print_color_text "$(get_text "$BU0026" $STOP_BY_CLUSTER)" red
    echo $MENU_SPACER
    printf "%20s | %s\n" "$BU0021" "$BU0022"
    echo $MENU_SPACER
    for def in $(echo "$sites_test" | awk -F':' '/:cluster:/{print $3}' | sed -e 's/;/ /g;'); do
      printf "%20s | %s\n" "$(echo $def | awk -F'=' '{print $1}')" "$(echo $def | awk -F'=' '{print $2}')"
    done
    echo $MENU_SPACER
    STOP_ALL_CONDITIONS=$(( $STOP_ALL_CONDITIONS+1 ))
  fi
}

# https://tools.ietf.org/html/rfc1034
# http://tools.ietf.org/html/rfc1123
# http://en.wikipedia.org/wiki/Hostname
# The standard characters are: 
#   the numbers from 0 through 9, 
#   uppercase and lowercase letters from A through Z, 
#   and the hyphen (-) character. 
# Computer names cannot consist entirely of numbers.
# Preferred name syntax
# 1. test for accepted chars
# 2. test string length (for netbios name)
# IP: egrep '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}'
test_hostname() {
    q_host="${1}"
    q_size="${2:-0}"
    q_type="${3:-1}"

    # now we forget about  63 octets long
    hostname_regexp='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
    test_hostname=0
    localhost_names='^(localhost|localhost.localdom|localhost.localdomain|ip6-localhost|ip6-loopback)'
    number_names='^[0-9]+$'

    # test hostname 
    if [[ -z "${q_host}" ]];
    then
        [[ $q_type -gt 0 ]] && print_message "$BU1002" "$BU2020" "" any_key
        return 255
    fi

    # test initial host name regexp
    if [[ $(echo "${q_host}" | egrep -c "$hostname_regexp" ) -gt 0 ]];
    then
        # test localhost aliases
        if [[ $(echo "${q_host}" | egrep -c "$localhost_names") -gt 0 ]];
        then
            [[ $q_type -gt 0 ]] && print_message "$BU1002" "$(get_text "$BU2021" "$q_host")" "" any_key
            return 2
        # test names cannot consist entirely of numbers.
        elif [[ $(echo "${q_host}" | egrep -c "$number_names") -gt 0 ]];
        then
             [[ $q_type -gt 0 ]] && print_message "$BU1002" "$(get_text "$BU2022" "$q_host")" "" any_key
             return 3
        fi

        # alil test passed
        # if limit size defined, check it
        if [[ ${q_size} -gt 0 ]] 2> /dev/null;
        then
            len_hostname=$(echo -n "${q_host}" | wc -c)
            # hostname `test` 
            # len 4
            if [[ $DEBUG -gt 0 ]];
            then
                echo "Len Hostname: ${len_hostname}"
                echo "Limit: ${q_size}"
            fi
            # all ok
            if [[ ${len_hostname} -le ${q_size} ]];
            then
                    test_hostname=1
            else
               [[ $q_type -gt 0 ]] && print_message "$BU1002" "$(get_text "$BU2023" "$q_host" "$q_size")" "" "" any_key
               return 1
            fi
        fi
        test_hostname=1
    else
        if [[ $q_type -gt 0 ]];
        then
            print_color_text "$BU0027"
            echo "$BU0028"
            echo 
            print_message "$BU1002" "$(get_text "$BU2024" "$q_host")" "" any_key
        fi
        return 1
    fi
    return 0
}

# test cache file
# return 0      - cache file exists and relevant
# return 1      - cache file doesn't exist
# return 2      - cache file is expired
# return 255    - unknown error
test_cache_file() {
    local cache_file="${1}"
    local cache_lv="${2:-7200}"

    # test file existense
    [[ ! -f $cache_file  ]] && return 1

    # test file modification time
    local cache_tm=$(stat -c %Y $cache_file)
    local tm=$(date +%s)
    local diff=$(( $tm - $cache_tm ))
    [[ $diff -gt $cache_lv ]] && return 2

    # return good answer
    return 0
}

# test bitrix-env new version
test_bitrix_update() {
    [[ -z $OS_VERSION ]] && get_os_type

    local bitrix_update_cache=$CACHE_DIR/bitrix_update.cache
    local bitrix_update_lv=86400
    local bitrix_rtn=0

    test_cache_file $bitrix_update_cache
    if [[ $? -gt 0 ]];
    then
        # VMBITRIX_9.0
        if [[ $OS_VERSION -eq 9 ]];
        then
            dnf makecache > /dev/null 2>&1
            dnf check-update | grep -c '^bitrix-env' > $bitrix_update_cache 2> /dev/null
        elif [[ $OS_VERSION -eq 7 ]];
        then
            yum makecache fast > /dev/null 2>&1
            yum check-update | grep -c '^bitrix-env' > $bitrix_update_cache 2> /dev/null
        else
            yum makecache fast > /dev/null 2>&1
            yum check-update | grep -c '^bitrix-env' > $bitrix_update_cache 2> /dev/null
        fi
    fi
    return $(cat $bitrix_update_cache)
}

# print menu
print_menu() {
    IFS_BAK=$IFS
    IFS=$'\n'
    echo -e "\t\t" "$BU0029"
    for menu_item in $menu_list; do
        echo -e "\t\t" $menu_item
    done
    IFS=$IFS_BAK
    IFS_BAK=
}

log_to_file() {
    log_message="${1}"
    notice="${2:-INFO}"
    printf "%20s: %5s [%s] %s\n" "$(date +"%Y/%m/%d %H:%M:%S")" \
        $$ "$notice" "$log_message" >> $LOGS_FILE
    [[ $DEBUG -gt 0 || $VERBOSE -gt 0 ]] && printf "%20s: %5s [%s] %s\n" \
        "$(date +"%Y/%m/%d %H:%M:%S")" $$ "$notice" "$log_message" 1>&2
    return 0
}

# CentOS7 + CentOS Stream 9:
# mysql-community-server => mysql-community
# Percona-Server-server  => percona
# percona-server-server  => percona
# MariaDB-server         => MariaDB
# mariadb-server         => mariadb
# Centos6:
# mysql-server           => mysql
get_mysql_package() {
    [[ -n $MYSQL_PACKAGE ]] && return 0

    PACKAGES_LIST=$(rpm -qa)
    MYSQL_PACKAGE=not_installed
    MYSQL_SERVICE=not_installed
    MYSQL_VERSION=not_installed
    if [[ $(echo "$PACKAGES_LIST" | grep -c '^mysql-community-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=mysql-community-server
        MYSQL_SERVICE=mysqld
    # Percona 5.6 && 5.7
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^Percona-Server-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=Percona-Server-server
        MYSQL_SERVICE=mysqld
    # Percona Server 8.0 && Percona Server 8.4
    elif [[ $(echo "$PACKAGES_LIST" | grep -c 'percona-server-server') -gt 0  ]];
    then
        MYSQL_PACKAGE=percona-server-server
        MYSQL_SERVICE=mysqld
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^MariaDB-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=MariaDB-server
        MYSQL_SERVICE=mariadb
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^mariadb-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=mariadb-server
        MYSQL_SERVICE=mariadb
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^mysql-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=mysql-server
        MYSQL_SERVICE=mysqld
    else
        return 1
    fi
    MYSQL_VERSION=$(rpm -qa --queryformat '%{version}' ${MYSQL_PACKAGE}* | head -1 | awk -F'.' '{printf "%d.%d", $1,$2}' )
    MYSQL_MID_VERSION=$(echo "$MYSQL_VERSION" | awk -F'.' '{print $2}')
    MYSQL_UNI_VERSION=$(echo "$MYSQL_VERSION" | awk -F'.' '{printf "%s%s", $1,$2}')

    # mysql status
    [[ -z $OS_VERSION ]] && get_os_type
    MYSQL_STATUS=

    # VMBITRIX_9.0
    if [[ $OS_VERSION -eq 9 ]];
    then
        systemctl is-active $MYSQL_SERVICE > /dev/null 2>&1
        status_rtn=$?
    elif [[ $OS_VERSION -eq 7 ]];
    then
        systemctl is-active $MYSQL_SERVICE > /dev/null 2>&1
        status_rtn=$?
    else
	MYSQL_INIT_SCRIPT=/etc/init.d/mysqld
        MYSQL_SERVICE_NAME=mysqld
        if [[ -f /etc/init.d/mysql ]];
        then
            MYSQL_INIT_SCRIPT=/etc/init.d/mysql
            MYSQL_SERVICE_NAME=mysql
        fi
        $MYSQL_INIT_SCRIPT status | grep -wc running > /dev/null 2>&1
        status_rtn=$?
    fi

    if [[ $status_rtn -gt 0 ]];
    then
        MYSQL_STATUS="stopped"
    else
        MYSQL_STATUS="running"
    fi
}

my_start() {
    [[ -z $MYSQL_STATUS ]] && get_mysql_package
    [[ -z $OS_VERSION ]] && get_os_type

    [[ $MYSQL_STATUS == "running" ]] && return 0

    # VMBITRIX_9.0
    if [[ $OS_VERSION -eq 9 ]];
    then
        systemctl start $MYSQL_SERVICE
    elif [[ $OS_VERSION -eq 7 ]];
    then
        systemctl start $MYSQL_SERVICE
    else
        service mysqld start
    fi
}

# copy-paste from mysql_secure_installation; you can find explanation in that script
basic_single_escape() {
    echo "$1" | sed 's/\(['"'"'\]\)/\\\1/g'
}

# generate random password
randpw() {
    local len="${1:-20}"
    local pt="${2:-0}"
    if [[ $pt -eq 0 ]];
    then
        </dev/urandom tr -dc '?!@&\-_+@%=.,;/0-9a-zA-Z' | head -c$len; echo ""
    elif [[ $pt -ge 10 ]];
    then
        </dev/urandom tr -dc '\-_+=0-9a-zA-Z' | head -c$len; echo ""
    else
        </dev/urandom tr -dc '0-9a-z' | head -c$len; echo ""
    fi
}

# generate client mysql config
my_config() {
    local cfg="${1:-$MYSQL_CNF}"
    echo "# mysql bvat config file" > $cfg
    echo "[client]" >> $cfg
    echo "user=root" >> $cfg
    local esc_pass=$(basic_single_escape "$MYSQL_ROOTPW")
    echo "password='$esc_pass'" >> $cfg
    echo "socket=/var/lib/mysqld/mysqld.sock" >> $cfg
}

# run query
my_query() {
    local query="${1}"
    local cfg="${2:-$MYSQL_CNF}"
    [[ -z $query ]] && return 1

    local tmp_f=$(mktemp /tmp/XXXXX_command)
    echo "$query" > $tmp_f
    mysql --defaults-file=$cfg < $tmp_f >> $LOGS_FILE 2>&1
    mysql_rtn=$?

    rm -f $tmp_f
    return $mysql_rtn
}

# query and result
my_select() {
    local query="${1}"
    local cfg="${2:-$MYSQL_CNF}"
    [[ -z $query ]] && return 1

    local tmp_f=$(mktemp /tmp/XXXXX_command)
    echo "$query" > $tmp_f
    mysql --defaults-file=$cfg < $tmp_f
    mysql_rtn=$?

    rm -f $tmp_f
    return $mysql_rtn
}

my_additional_security() {
    # delete anonymous users
    my_query "DELETE FROM mysql.user WHERE User='';"
    [[ $? -eq 0 ]] && print_color_text "$BU0030"

    # remove remote root
    my_query "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    [[ $? -eq 0 ]] && print_color_text "$BU0031"

    # remove test database
    my_query "DROP DATABASE test;"
    [[ $? -eq 0 ]] && print_color_text "$BU0032"

    my_query "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
    [[ $? -eq 0 ]] && print_color_text "$BU0033"

    # flush privileges
    my_query "FLUSH PRIVILEGES;"
    [[ $? -eq 0 ]] && print_color_text "$BU0034"
}

update_site_settings() {
    local path=${1:-/home/bitrix/www/bitrix/.settings.php}
    tmp_path=$path.tmp

    [[ -z $BX_PASSWORD ]] && return 2
    [[ -z $BX_USER ]] && return 2
    [[ ! -f $path ]] && return 1
    #cp -f $path $path.bak
    log_to_file "$(get_text "$BU0036" "$path")"

    #  'login' => '__LOGIN__',
    #  'password' => '__PASSWORD__',
    login_line=$(grep -n "'login'" $path | awk -F':' '{print $1}')
    if [[ -z $login_line ]];
    then
        log_to_file "$(get_text "$BU2025" "$path")"
        exit 1
    fi
    esc_pass=$(basic_single_escape $BX_PASSWORD)

    {
        head -n $(( $login_line-1 )) $path
        echo "        'login'    => '$BX_USER',"
        echo "        'password' => '$esc_pass'," 
        tail -n +$(( $login_line+2 )) $path
    } > $tmp_path
    mv -f $tmp_path $path
    chown bitrix:bitrix $path
    chmod 640 $path
    log_to_file "$(get_text "$BU0035" "$path")"
}

update_site_dbconn() {
    local path=${1:-/home/bitrix/www/bitrix/php_interface/dbconn.php}
    tmp_path=$path.tmp

    [[ -z $BX_PASSWORD ]] && return 2
    [[ -z $BX_USER ]] && return 2
    [[ ! -f $path ]] && return 1
    #cp -f $path $path.bak
    log_to_file "$(get_text "$BU0036" "$path")"

    login_line=$(grep -n "DBLogin" $path | awk -F':' '{print $1}')
    if [[ -z $login_line ]];
    then
        log_to_file "$BU2025"
        exit 1
    fi
    esc_pass=$(basic_single_escape $BX_PASSWORD)

    {
        head -n $(( $login_line-1 )) $path
        echo "\$DBLogin = '$BX_USER';"
        echo "\$DBPassword = '$esc_pass';"
        tail -n +$(( $login_line+2 )) $path
    } > $tmp_path
    mv -f $tmp_path $path
    chown bitrix:bitrix $path
    chmod 640 $path
    log_to_file "$(get_text "$BU0035" "$path")"
}

# create mysql account and database for default site
# MYSQL_USER_BASE
update_site_mysql_data() {
    user_select="${1}"

    user_tmp=$(mktemp /tmp/XXXXXX_user)
    BX_PASSWORD=
    BX_USER=

    # process for existen user
    if [[ -n $user_select ]];
    then
        BX_USER="$user_select"

    # process for new one
    # generate new user
    else
        user_id=0

        # choose user name
        # test if it free; user1, user2 .. user20 => exit
        test_limits=20
        while [[ ( -z $BX_USER ) && ( $test_limits -gt 0 ) ]]; do
            test_user="${MYSQL_USER_BASE}${user_id}"
            log_to_file "$(get_text "$BU0037" "$test_user")"
            my_select "SELECT User FROM mysql.user WHERE User='$test_user'" > $user_tmp 2>&1
            if [[ $? -gt 0 ]];
            then
                log_to_file "$BU2026"
                cat $user_tmp >> $LOGS_FILE
                rm -f $user_tmp
                exit
            fi
            # if temporary file contains username than request return value and user exists
            is_user=$(cat $user_tmp | grep -wc "$test_user")

            [[ $is_user -eq 0 ]] && BX_USER="$test_user"

            user_id=$(( $user_id + 1 ))
            test_limits=$(( $test_limits - 1 ))
        done

        if [[ -z $BX_USER ]];
        then
            log_to_file "$BU2027"
            rm -f $user_tmp
            exit 1
        fi

        log_to_file "$(get_text "$BU0038" "$BX_USER")"
    fi
    
    # create/update user
    my_query="CREATE"
    [[ -n $user_select ]] && my_query="ALTER"
    BX_PASSWORD=$(randpw)
    esc_db_password=$(basic_single_escape $BX_PASSWORD)
    local sql_query="$my_query USER '$BX_USER'@'localhost' IDENTIFIED BY '$esc_db_password';"
    local sql_query_log="$my_query USER '$BX_USER'@'localhost' IDENTIFIED BY '$FAKE_PASSWORD';"

    log_to_file "Starting query=$my_query for user=$BX_USER"
    my_query "$sql_query" > $user_tmp 2>&1

    if [[ $? -gt 0 ]];
    then
        log_to_file "-- query: $sql_query_log"
        cat $user_tmp >> $LOGS_FILE
        rm -f $user_tmp
        exit 1
    fi
    log_to_file "++ query: $sql_query_log"

    # grant access
    my_query "GRANT ALL PRIVILEGES ON $BX_DB.* TO '$BX_USER'@'localhost';" >$user_tmp 2>&1
    if [[ $? -gt 0 ]];
    then
        log_to_file "$(get_text "$BU2028" "$BX_USER" "$BX_DB")"
        cat $user_tmp >> $LOGS_FILE
        rm -f $user_tmp
        exit 1
    fi
    log_to_file "$(get_text "$BU0039" "$BX_USER" "$BX_DB")"

    # delete temporary file
    rm -f $user_tmp
}

my_generate_rootpw() {
    [[ -z $MYSQL_VERSION ]] && get_mysql_package
    # start mysql
    my_start

    log_to_file "$(get_text "$BU0040" "$MYSQL_VERSION" "$MYSQL_MID_VERSION")"

    if [[ ! -f $MYSQL_CNF ]];
    then
        log_to_file "$(get_text "$BU0041" "$MYSQL_CNF")"
        if [[ $MYSQL_UNI_VERSION -ge 57 ]];
        then
            MYSQL_LOG_FILE=/var/log/mysqld.log
            MYSQL_ROOTPW=$(grep 'temporary password' $MYSQL_LOG_FILE | awk '{print $NF}')
            MYSQL_ROOTPW_TYPE=temporary
        else
            MYSQL_ROOTPW=
            MYSQL_ROOTPW_TYPE=empty
        fi

        # test root has empty password
        local my_temp=$MYSQL_CNF.temp
        my_config "$my_temp"
        my_query "status;" "$my_temp"
        [[ $? -gt 0 ]] && return 1

        mysql_update_config=$my_temp
    else
        log_to_file "$(get_text "$BU0042" "$MYSQL_CNF")"
        my_query "status;"
        [[ $? -gt 0 ]] && return 2
        MYSQL_ROOTPW_TYPE=saved
        cp -f $MYSQL_CNF $MYSQL_CNF.temp
        mysql_update_config=$MYSQL_CNF.temp
    fi
    log_to_file "$(get_text "$BU0043" "$MYSQL_ROOTPW_TYPE")"

    # generate root password and update mysql settings
    MYSQL_ROOTPW=$(randpw)
    local esc_pass=$(basic_single_escape "$MYSQL_ROOTPW")
    
    # default mysql 8.0
    local update_sql="ALTER USER 'root'@'localhost' IDENTIFIED BY '$esc_pass'; \
        FLUSH PRIVILEGES;"
    local update_sql_log="ALTER USER 'root'@'localhost' IDENTIFIED BY '$FAKE_PASSWORD';"
 
    if [[ $MYSQL_UNI_VERSION -le 57 ]];
    then
        update_sql="UPDATE mysql.user SET Password=PASSWORD('$esc_pass') \
        WHERE User='root'; FLUSH PRIVILEGES;"
        update_sql_log="UPDATE mysql.user SET Password=PASSWORD('$FAKE_PASSWORD') \
        WHERE User='root';"
    fi

    my_query "$update_sql" "$mysql_update_config"
    my_query_rtn=$?

    if [[ $my_query_rtn -eq 0 ]];
    then
        log_to_file "+ query: $update_sql_log"
        log_to_file "$BU0044"
        rm -f $mysql_update_config
    else
        log_to_file "- query: $update_sql_log"
        log_to_file "$BU0045"
        rm -f $mysql_update_config
        return 1
    fi

    # create /root/.my.cnf and save settings
    my_config
    log_to_file "$BU0046"

    # configure additional options
    my_additional_security
    log_to_file "$BU0047"
    return 0
}

my_generate_sitepw() {
    local site_dir="${1:-/home/bitrix/www}"
    local site_dbcon="$site_dir/bitrix/php_interface/dbconn.php"
    local site_settings="$site_dir/bitrix/.settings.php"
    local site_db=$(cat $site_dbcon | grep -v '^#\|^$\|^;' | \
        grep -w DBName | awk -F'=' '{print $2}' | sed -e 's/"//g;s/;//;s/\s\+//')

    [[ -f $site_dbcon && -f $site_settings ]]  || return 1
    [[ -z $site_db ]] && return 1
    BX_DB="$site_db"

    # test root login in config files
    dbconn_info=$(cat $site_dbcon | grep -v '\(^$\|^;\|^#\)' | grep -w "DBLogin")
    settings_info=$(cat $site_settings | grep -v '\(^$\|^;\|^#\)' | grep -w "login")
    
    # only for deafult site
    # 'login'    => 'bitrix0'
    # there is root account in dbconn.php or settings.php
    is_root_dbcon=$(echo "$dbconn_info" | grep -wc "root")
    is_root_settings=$(echo "$settings_info"  | grep -wc "root")

    # there is bitrix account in dbconn.php or settings.php
    is_bitrix_dbcon=$(echo "$dbconn_info" | grep -c "bitrix")
    is_bitrix_settings=$(echo "$settings_info"  | grep -c "bitrix")

    BX_USER=
    
    # if user found in dbconn; get it name from it 
    if [[ $is_bitrix_dbcon -gt 0 ]];
    then
        BX_USER=$(echo "$dbconn_info" | awk -F'=' '{print $2}' | \
            sed -e "s/^\s\+//;s/\s\+$//" | sed -e "s/^'//;s/;$//;s/'$//")
        log_to_file "There is user=$BX_USER in conf=dbconn.php"
    else
        # TODO!!! Get from settings.php
        [[ ( $is_root_dbcon -eq 0 ) && ( $is_root_settings -eq 0 ) ]] && return 1
    fi

    # generate user settings
    update_site_mysql_data "$BX_USER"

    # create db, if not exist
    [[ ! -d "/var/lib/mysql/$site_db" ]] && my_query "CREATE DATABASE $site_db"

    # update configs
    update_site_dbconn "$site_dbcon"
    update_site_settings "$site_settings"
}

#check postgresql package version
postgresql_package() {
    PACKAGES_LIST=$(rpm -qa)

    POSTGRESQL_PACKAGE=not_installed
    POSTGRESQL_SERVICE=not_installed
    POSTGRESQL_VERSION=not_installed

    if [[ $(echo "$PACKAGES_LIST" | grep -c '^postgresql-server') -gt 0 ]];
    then
        POSTGRESQL_PACKAGE=postgresql-server
        POSTGRESQL_SERVICE=postgresql
    else
        return 1
    fi

    POSTGRESQL_VERSION=$(rpm -qa --queryformat '%{version}' ${POSTGRESQL_PACKAGE}* | head -1)
    POSTGRESQL_UNI_VERSION=$(echo "$POSTGRESQL_VERSION" | awk -F'.' '{print $1}')
}

#interface for postgresql service
service_postgresql() {
    local action=$1
    local restart_rtn=0
    [[ -z $action ]] && return 1

    postgresql_package || exit 1

    if [[ ${OS_VERSION} -ne 9 ]];
    then
        log_to_file "Service $POSTGRESQL_SERVICE not supported on this OS version"
        return 0
    fi

    if [[ "$action" == "status" ]];
    then
        systemctl is-active $POSTGRESQL_SERVICE > /dev/null 2>&1
        return $?
    elif [[ $action == "enable" ]];
    then
        systemctl enable $POSTGRESQL_SERVICE >> $LOGS_FILE 2>&1
        restart_rtn=$?
    elif [[ ( $action == "stop" ) || ( $action == "restart" ) ]];
    then
        systemctl $action $POSTGRESQL_SERVICE >> $LOGS_FILE 2>&1
        restart_rtn=$?
    else
        systemctl $action $POSTGRESQL_SERVICE >> $LOGS_FILE 2>&1
        restart_rtn=$?
    fi

    if [[ $restart_rtn -gt 0 ]];
    then
        log_to_file "Cannot $action for pgsql service" "ERROR"
        exit 1
    else
        log_to_file "Service $POSTGRESQL_SERVICE is \"${action}ed\""
    fi
}

#create pgpass file
create_pgpass_file() {
    local password="${1}"

    touch "$PGSQL_PASS"
    chmod 600 "$PGSQL_PASS"

    echo "localhost:5432:*:postgres:${password}" > "$PGSQL_PASS"

    if [[ $? -ne 0 ]];
    then
        log_to_file "Failed to create PostgreSQL password file" "ERROR"
        return 1
    fi

    log_to_file "PostgreSQL password file created successfully"
    return 0
}

#replace all authentication methods with password
update_pgsql_config() {
    local pg_hba_conf="/var/lib/pgsql/data/pg_hba.conf"
    
    if [[ ! -f $pg_hba_conf ]];
    then
        log_to_file "PostgreSQL config file $pg_hba_conf not found" "ERROR"
        return 1
    fi

    local tmp_conf=$(mktemp /tmp/pg_hba.XXXXX)

    sed -e 's/\([ \t]\)ident\([ \t]*$\)/\1password\2/' \
        -e 's/\([ \t]\)peer\([ \t]*$\)/\1password\2/' \
        "$pg_hba_conf" > "$tmp_conf"

    if [[ $? -ne 0 ]];
    then
        log_to_file "Failed to update PostgreSQL authentication methods" "ERROR"
        rm -f "$tmp_conf"
        return 1
    fi

    mv "$tmp_conf" "$pg_hba_conf"
    
    chown postgres:postgres "$pg_hba_conf"
    chmod 600 "$pg_hba_conf"

    service_postgresql restart

    return $?
}

#instruction:
#pgsql_query "SELECT * FROM table"
#pgsql_query "SELECT * FROM table" "postgres" (execute as postgres user)
pgsql_query() {
    local query="${1}"
    local run_as="${2}"
    local tmp_f=$(mktemp /tmp/XXXXX_pgsql_command)

    [[ -z $query ]] && return 1

    if ! service_postgresql status;
    then
        log_to_file "PostgreSQL service is not running" "ERROR"
        rm -f $tmp_f
        return 1
    fi

    if [[ ! -f $PGSQL_PASS ]];
    then
        log_to_file "PostgreSQL password file $PGSQL_PASS not found" "ERROR"
        return 1
    fi

    echo "$query" > $tmp_f

    if [[ -n "$run_as" ]];
    then
        chown postgres:postgres $tmp_f
        sudo -u "$run_as" psql -f $tmp_f >> $LOGS_FILE 2>&1
    else
        psql -U postgres -f $tmp_f >> $LOGS_FILE 2>&1
    fi
    
    local pgsql_rtn=$?

    rm -f $tmp_f

    return $pgsql_rtn
}

#end postgres functions
update_settings_option() {
    local option="${1}"
    local value="${2}"
    local path="${3:-/home/bitrix/www/bitrix/.settings.php}"

    tmp_path=$path.tmp

    [[ -f $path ]] || return 1
    log_to_file "$(get_text "$BU0036" "$path")"

    # get 
    option_line=$(grep -n "'$option'" $path | awk -F':' '{print $1}')
    if [[ -z $option_line ]];
    then
        log_to_file "$(get_text "$BU202501" "$option" "$path")"
        exit 1
    fi
    esc_value=$(basic_single_escape ${value})

    {
        head -n $(( $option_line - 1 )) $path
        echo "        '$option'    => '$esc_value',"
        tail -n +$(( $option_line+1 )) $path
    } > $tmp_path

    log_to_file "Replace file $path by $tmp_path"
    mv -f $tmp_path $path
    chown bitrix:bitrix $path
    chmod 640 $path
    log_to_file "$(get_text "$BU003501" "$option" "$path")"
}

update_crypto_key() {
    local site_dir="${1:-/home/bitrix/www}"
    local site_settings="$site_dir/bitrix/.settings.php"

    [[ -f $site_settings ]]  || return 1
    secure_key=$(randpw 32 1)
    update_settings_option "crypto_key" "$secure_key"
}

generate_push() {
    [[ -z $OS_VERSION ]] && get_os_type

    if [[ -f /etc/sysconfig/push-server-multi ]];
    then
        # delete current key
        sed -i "/SECURITY_KEY/d" /etc/sysconfig/push-server-multi && log_to_file "$BU0048"

        # generate configs && generate SECURITY_KEY in /etc/sysconfig/push-server-multi
        /usr/bin/push-server-multi reset > /dev/null 2>&1
        log_to_file "$BU0049"

        # get variables from config file
        . /etc/sysconfig/push-server-multi

        # VMBITRIX_9.0
        if [[ $OS_VERSION -ge 7 ]];
        then
            log_to_file "$BU0050"
            # delete current one
            sed -i "/BX_PUSH_SECURITY_KEY/d" /etc/httpd/bx/conf/00-environment.conf
            echo "SetEnv BX_PUSH_SECURITY_KEY $SECURITY_KEY" >> /etc/httpd/bx/conf/00-environment.conf
        else
            log_to_file "Update /etc/sysconfig/httpd"
            sed -i "/BX_PUSH_SECURITY_KEY/d" /etc/sysconfig/httpd
            echo "BX_PUSH_SECURITY_KEY=$SECURITY_KEY" >> /etc/sysconfig/httpd
        fi

        # settings file
        update_settings_option "signature_key" "$SECURITY_KEY"

        # restart apache
	if [[ $OS_VERSION -ge 7 ]];
	then
            systemctl restart httpd.service > /dev/null 2>&1
        else
            service httpd restart > /dev/null 2>&1
        fi
    fi
}

update_bitrix_password() {
    BITRIXTMP=$(mktemp /tmp/.password_XXXXXXX)
    # generate password
    randpw 10 > $BITRIXTMP

    # update user
    cat $BITRIXTMP | passwd --stdin bitrix >> $LOGS_FILE 2>&1
    log_to_file "$BU0051"

    # this password is working for the first logon
    chage -d0 bitrix >> $LOGS_FILE 2>&1

    # delete temporary file
    rm -f $BITRIXTMP
}

# change issue message (that used in login screen)
update_issue() {
    /opt/webdir/bin/bx_motd > /etc/issue.new 2>/dev/null
    mv -f /etc/issue.new /etc/issue
    chmod 640 /etc/issue
}


update_root_password() {
    ROOTPASSWORD=/root/ROOT_PASSWORD
    # generate password
    ROOTPW=$(randpw 12 1)

    # update user
    log_to_file "$BU0052"
    echo -n "$ROOTPW" | passwd --stdin root  >> $LOGS_FILE 2>&1
    echo -n "$ROOTPW" > $ROOTPASSWORD

    # this password is working for the first logon
    chage -d0 root >> $LOGS_FILE 2>&1

    # add cleaner to .bash_profile file
    if [[ $(grep -c /opt/webdir/bin/rpm_package/cleaner.sh /root/.bash_profile) -eq 0 ]];
    then
        echo /opt/webdir/bin/rpm_package/cleaner.sh >> /root/.bash_profile
        log_to_file "$BU0053"
    fi

    update_issue
}

generate_hostname() {
    ask_user="${1:-0}"
    hostident="${2}"
    # get hostname
    if [[ -z $hostident ]];
    then
        USED_HOSTNAME=$(hostname)
    else
        USED_HOSTNAME="${hostident}"
    fi

    test_hostname "$USED_HOSTNAME" 0 0 
    test_hostname_rtn=$?
    if [[ $test_hostname_rtn -gt 0 ]];
    then
        if [[ $ask_user -gt 0 ]];
        then
            read -r -p "$BU0056" USED_HOSTNAME
            [[ -z $USED_HOSTNAME  ]] && USED_HOSTNAME=server1
        else
            USED_HOSTNAME=server1
        fi
    fi
    log_to_file "$(get_text "$BU0057" "$USED_HOSTNAME")"
}

generate_int_and_ip() {
    ask_user="${1:-0}"

    # get host interfaces
    get_local_network 1> /dev/null 2>&1
    if [[ $HOST_NETWORK -gt 0  ]];
    then
        # use the first interface
        USED_INT=
        USED_IP=
        for info in $HOST_IPS; do
            [[ -n $USED_INT ]] && \
                continue
            USED_INT=$(echo $info | awk -F'=' '{print $1}')
            USED_IP=$(echo $info | awk -F'=' '{print $2}')
        done
    else
        log_to_file "$BU2029"
        return 1
    fi
    log_to_file "$(get_text "$BU0055" "$USED_INT" "$USED_IP")"
}

waiting_ansible_task() {
    taskId="${1}"

    [[ -z $taskId ]] && return 1

    pidFile=/opt/webdir/temp/$taskId/pid
    statusFile=/opt/webdir/temp/$taskId/status
    checkFile=/opt/webdir/temp/$taskId/.test

    if [[ ! -f $pidFile ]];
    then
        log_to_file "Cannot find pidFile=$pidFile"
        return 1
    fi
    pidNum=$(cat $pidFile)
    if [[ -z $pidNum ]];
    then
        log_to_file "Empty PID number in file=$pidFile"
        return 1
    fi

    taskFinished=0
    wait_timeout=0
    limit_timeout=1800
    sleep_time=120
    while [[ $taskFinished -eq 0 ]]; do
        if [[ $wait_timeout -gt $limit_timeout ]];
        then
            log_to_file "The waiting time is maximum=$limit_timeout sec, \
                we are completing the execution."
            return 1
        fi

        pgrep -F $pidFile -l >$checkFile 2>&1
        pgrep_rtn=$?
        # return 1 if there is no process
        if [[ $pgrep_rtn -eq 0 ]];
        then
            # process_name
            process_name=$(awk '{print $2}' $checkFile)
            log_to_file "There is running process=$process_name pid=$pidNum for task=$taskId: waiting"

            # waiting and create maximum waiting time
            sleep $sleep_time
            wait_timeout=$(( $wait_timeout + $sleep_time ))
            continue
        fi

        # there is no process; test if there is final status in status
        is_play_recap=$(cat $statusFile | grep -c 'PLAY RECAP')

        # no status information; may be process if failed by memory condition on host
        if [[ $is_play_recap -eq 0 ]];
        then
            log_to_file "It looks like the process pid=$pidNum \
                crashed without completing its work."
            return 1
        fi

        # get status from status file
        host_status=$(cat $statusFile | grep 'PLAY RECAP' -A1  | tail -n1)
        host_unreachable=$(echo "$host_status" | egrep -o 'unreachable=[0-9]+' | \
            awk -F'=' '{print $2}')
        host_failed=$(echo "$host_status" | egrep -o 'failed=[0-9]+' | \
            awk -F'=' '{print $2}')
        if [[ $host_unreachable -gt 0 || $host_failed -gt 0 ]];
        then
            log_to_file "Errors occurred during the playbook execution (taskId=$taskId). \
                Details can be found in the file=$statusFile"
            return 1
        fi

        log_to_file "PLaybook (taskId=$taskId) execution completed, no errors found."
        return 0
    done
}

generate_ansible_inventory() {
    ask_user="${1:-0}"
    bitrix_type="${2:-general}"
    hostident="${3}"
    log_to_file "$BU0054"

    # create info about host interface
    generate_int_and_ip ${ask_user}

    # gernerate hostname
    generate_hostname ${ask_user} ${hostident}

    gen_temp_file=$(mktemp /tmp/generate.XXXXXX)

    # start creation pool
    /opt/webdir/bin/wrapper_ansible_conf \
        -a create --bitrix_type $bitrix_type \
        -H $USED_HOSTNAME -I $USED_INT > $gen_temp_file 2>&1
    if [[ $? -gt 0 ]];
    then
        log_to_file "Cannot create pool configuration; host=$USED_HOSTNAME interface=$USED_INT"
        log_to_file "$(cat $gen_temp_file)"
        rm -f $gen_temp_file
        #return 1
        exit
    fi
    taskId=$(cat $gen_temp_file | egrep -o "task_id=[a-z0-9_]+" | \
        awk -F'=' '{print $2}')
    if [[ -z $taskId ]];
    then
        log_to_file "No taskId value found in the output of the  pool creation command."
        rm -f gen_temp_file
        #return 1
        exit
    fi

    log_to_file "Waiting for the pool configuration command to complete taskId=$taskId."
    waiting_ansible_task $taskId || exit

    log_to_file "Pull configuration is complete. You can change it ./menu.sh"

    # configure push server
    # info:bxDaemon:pushserver_7401067151:12944:1720176682::running:::
    /opt/webdir/bin/bx-sites -a push_configure_nodejs \
        -H $USED_HOSTNAME > $gen_temp_file 2>&1
    if [[ $? -gt 0 ]];
    then
        log_to_file "Cannot create push-server configuration; host=$USED_HOSTNAME"
        log_to_file "$(cat $gen_temp_file)"
        rm -f $gen_temp_file
        #return 1
        exit
    fi
    taskId=$(cat $gen_temp_file | egrep -o 'pushserver_[0-9]+')
    if [[ -z $taskId ]];
    then
        log_to_file "No taskId value found in the output of the \
            push-server configuration command."
        rm -f gen_temp_file
        #return 1
        exit
    fi

    log_to_file "Waiting for the push-server configuration command to complete taskId=$taskId."
    waiting_ansible_task $taskId || exit

    log_to_file "Push configuration is complete. You can change it ./menu.sh"

}

delete_packer_user() {
    id vbox >/dev/null 2>&1
    if [[ $? -eq 0 ]];
    then
        userdel --force --remove vbox
    fi
}

create_pool_on_install() {
    ask_user="${1:-0}"
    bitrix_type="${2:-general}"
    hostident="${3}"
    log_to_file "$BU0054"

    # get host interfaces
    get_local_network 1> /dev/null 2>&1
    if [[ $HOST_NETWORK -gt 0  ]];
    then
        # use the first interface
        USED_INT=
        USED_IP=
        for info in $HOST_IPS; do
            if [[ -z $USED_INT ]];
            then
                USED_INT=$(echo $info | awk -F'=' '{print $1}')
                USED_IP=$(echo $info | awk -F'=' '{print $2}')
            fi
        done
    else
        log_to_file "$BU2029"
        return 1
    fi
    log_to_file "$(get_text "$BU0055" "$USED_INT" "$USED_IP")"

    # get hostname
    if [[ -z $hostident ]];
    then
        USED_HOSTNAME=$(hostname)
    else
        USED_HOSTNAME="${hostident}"
    fi

    test_hostname "$USED_HOSTNAME" 0 0
    test_hostname_rtn=$?
    if [[ $test_hostname_rtn -gt 0 ]];
    then
        if [[ $ask_user -gt 0 ]];
        then
            read -r -p "$BU0056" USED_HOSTNAME
            [[ -z $USED_HOSTNAME  ]] && USED_HOSTNAME=server1
        else
            USED_HOSTNAME=server1
        fi
    fi
    log_to_file "$(get_text "$BU0057" "$USED_HOSTNAME")"

    # create pool task
    $ansible_wrapper -a create --bitrix_type $bitrix_type -H $USED_HOSTNAME -I $USED_INT >> $LOGS_FILE 2>&1
    if [[ $? -gt 0 ]];
    then
        return 1
    fi
    log_to_file "$BU0058"
}

run_push_server_on_install() {
    ask_user="${1:-0}"
    bitrix_type="${2:-general}"
    hostident="${3}"
    log_to_file "$BU3001"

    # get host interfaces
    get_local_network 1> /dev/null 2>&1
    if [[ $HOST_NETWORK -gt 0  ]];
    then
        # use the first interface
        USED_INT=
        USED_IP=
        for info in $HOST_IPS; do
            if [[ -z $USED_INT ]];
            then
                USED_INT=$(echo $info | awk -F'=' '{print $1}')
                USED_IP=$(echo $info | awk -F'=' '{print $2}')
            fi
        done
    else
        log_to_file "$BU2029"
        return 1
    fi
    log_to_file "$(get_text "$BU3002" "$USED_INT" "$USED_IP")"

    # get hostname
    if [[ -z $hostident ]];
    then
        USED_HOSTNAME=$(hostname)
    else
        USED_HOSTNAME="${hostident}"
    fi

    test_hostname "$USED_HOSTNAME" 0 0
    test_hostname_rtn=$?
    if [[ $test_hostname_rtn -gt 0 ]];
    then
        if [[ $ask_user -gt 0 ]];
        then
            read -r -p "$BU0056" USED_HOSTNAME
            [[ -z $USED_HOSTNAME  ]] && USED_HOSTNAME=server1
        else
            USED_HOSTNAME=server1
        fi
    fi
    log_to_file "$(get_text "$BU3003" "$USED_HOSTNAME")"

    # run push server on nodejs task
    $bx_sites_script -a push_configure_nodejs -H $USED_HOSTNAME >> $LOGS_FILE 2>&1
    if [[ $? -gt 0 ]];
    then
        return 1
    fi
    log_to_file "$BU3004"
}

# get available memory on board
get_available_memory() {
    AVAILABLE_MEMORY=$(free | grep Mem | awk '{print $2}')
    if [[ $IS_OPENVZ -gt 0 ]];
    then
        if [[ -z $AVAILABLE_MEMORY ]];
        then
            mem4kblock=`cat /proc/user_beancounters | grep vmguarpages|awk '{print $4}'`
            mem4kblock2=`cat /proc/user_beancounters | grep privvmpages|awk '{print $4}'`
            if [[ ${mem4kblock2} -gt ${mem4kblock} ]];
            then
                AVAILABLE_MEMORY=$(echo "${mem4kblock} * 4"|bc)
            else
                AVAILABLE_MEMORY=$(echo "${mem4kblock2} * 4"|bc)
            fi
        fi
    fi
    AVAILABLE_MEMORY_MB=$(( $AVAILABLE_MEMORY / 1024 ))
    [[ ( $IS_X86_64 -eq 0 ) && ( $AVAILABLE_MEMORY_MB -gt 4096 ) ]] && AVAILABLE_MEMORY_MB=4096
}

get_php_settings() {
    PHP_CMD=$(which php)
    APACHE_CMD=$(which httpd)
    # 5.4, 5.6, 7.0 and etc 
    PHP_VERSION=$($PHP_CMD -v | egrep -o "PHP [0-9\.]+" | awk '{print $2}' | awk -F'.' '{printf "%d.%d", $1, $2}')
    php_up=$(echo "$PHP_VERSION" | awk -F'.' '{print $1}')
    php_mid=$(echo "$PHP_VERSION" | awk -F'.' '{print $2}')
    IS_OLDER_PHP=0
    [[ ( $php_up -ge 5 && $php_mid -ge 6 ) || ( $php_up -ge 7 ) ]] && IS_OLDER_PHP=1
    APACHE_VERSION=$($APACHE_CMD -v | egrep -o "Apache/[0-9\.]+" | awk -F'/' '{print $2}' | awk -F'.' '{printf "%d.%d", $1,$2}')
    IS_APCU_PHP=$($PHP_CMD -m 2> /dev/null | grep -wc apcu)
    IS_OPCACHE_PHP=$($PHP_CMD -m 2> /dev/null | grep -wc OPcache)
}

# bx_trusted
public_firewalld() {
    if [[ $(systemctl is-active firewalld | grep -wc active) -eq 0 ]]; then
        # http://jabber.bx/view.php?id=89409
        rpm -qi firewalld > /dev/null 2>&1
        if [[ $? -gt 0 ]];
        then
            log_to_file "$BU0061"
            yum -y install  firewalld > /dev/null 2>&1
            if [[ $? -gt 0 ]];
            then
                log_to_file "$BU2032"
                return 2
            fi
        fi
        systemctl enable firewalld > /dev/null 2>&1
        systemctl start firewalld
        if [[ $? -gt 0 ]];
        then
            log_to_file "$BU2033"
            return 2
        fi
    fi

    log_to_file "$BU0059"
    is_bx_trusted=$(firewall-cmd --get-zones | grep "bx_trusted" -wc)
    if [[ $is_bx_trusted -eq 0 ]];
    then
        firewall-cmd --permanent --new-zone=bx_trusted > /dev/null 2>&1
    fi

    firewall-cmd --zone=bx_trusted --permanent --add-port=1-65535/tcp > /dev/null 2>&1
    firewall-cmd --zone=bx_trusted --permanent --add-port=1-65535/udp > /dev/null 2>&1

    firewall-cmd --zone=public --list-interfaces 1> /dev/null 2>&1
    if [[ $? -gt 0 ]];
    then
        log_to_file "$BU2030"
        return 2
    fi
    firewall-cmd --permanent --zone=public --add-service=http > /dev/null 2>&1 && firewall-cmd --permanent --zone=public --add-service=https  > /dev/null 2>&1
    if [[ $? -gt 0 ]];
    then
        log_to_file "$BU2031"
        return 2
    fi
    log_to_file "$BU0060"
    firewall-cmd --reload > /dev/null 2>&1
    return 0
}

check_iptables_status() {
    iptables_status='disabled'
    iptables_tmp=$(mktemp $TMP_DIR/bx_iptables.XXXXX)
    iptables_test_port=2222
    iptables_test_port_is_good=0

    # test if port is close (nobody listen)
    while [[ $iptables_test_port_is_good -eq 0 ]]; do
        ss -lnp | egrep ":80\s+$iptables_test_port" > $iptables_tmp 2>&1
        if [[ $? -gt 0 ]];
        then
            iptables_test_port_is_good=1
        else
            iptables_test_port=$(( $iptables_test_port + 1 ))
        fi
    done

    # iptables working (stateless)
    iptables -I INPUT -p tcp --dport $iptables_test_port -j ACCEPT > $iptables_tmp 2>&1
    if [[ $? -eq 0 ]];
    then
        iptables_status='stateless'
        iptables -D INPUT -p tcp --dport $iptables_test_port -j ACCEPT > $iptables_tmp 2>&1
    fi

    # iptables working (stateful)
    if [[ $iptables_status == "stateless" ]];
    then
        iptables -I INPUT -m state --state NEW -p tcp --dport $iptables_test_port -j ACCEPT > $iptables_tmp 2>&1
        if [[ $? -eq 0 ]];
        then
            iptables_status='stateful'
            iptables -D INPUT -m state --state NEW -p tcp --dport $iptables_test_port -j ACCEPT > $iptables_tmp 2>&1
        fi
    fi
    rm -f $iptables_tmp
}

check_firewalld_status() {
    firewalld_package="not_installed"
    firewalld_status="not_running"
    firewalld_bx_type="not_installed"
    firewalld_tolerance="non_compatible"

    firewalld_tmp=$(mktemp $TMP_DIR/firewalld.XXXXX)
    rpm -qi firewalld > $firewalld_tmp 2>&1
    if [[ $? -gt 0 ]];
    then
        rm -f $firewalld_tmp
        return 0
    fi
    firewalld_package="installed"

    firewall-cmd --state > $firewalld_tmp 2>&1
    if [[ $? -gt 0 ]];
    then
        rm -f $firewalld_tmp
        return 0
    fi

    if [[ $(grep -c '^running$' $firewalld_tmp) -gt 0 ]];
    then
        firewalld_status="running"
        if [[ $(firewall-cmd --get-active-zones | grep bx_trusted -c) -gt 0 ]];
        then
            firewalld_bx_type="installed"
        fi
	systemctl status firewalld > $firewalld_tmp 2>&1
        if [[ $(grep -c "ERROR:" $firewalld_tmp) -eq 0 ]];
        then
            firewalld_tolerance="compatible"
        fi
    fi
    rm -f $firewalld_tmp
}

replace_firewalld_by_iptables() {
    [[ -z $OS_VERSION ]] && get_os_type

    if [[ $OS_VERSION -eq 7 ]];
    then
        check_firewalld_status
        if [[ $firewalld_package == "installed" ]];
        then
            yum -y remove firewalld > /dev/null 2>&1
            yum -y install iptables-services > /dev/null 2>&1
            systemctl enable iptables
            systemctl start iptables
        fi

        if [[ $(systemctl is-active iptables | grep -c "active") -eq 0 ]];
        then
            echo '*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT' > /etc/sysconfig/iptables
            systemctl start iptables
        fi
    else
        chkconfig iptables on
        /etc/init.d/iptables restart > /dev/null 2>&1
    fi
}

public_stateless_iptables() {
    replace_firewalld_by_iptables

    is_incorrect_rules=$(grep -c "state NEW" /etc/sysconfig/iptables)
    if [[ $is_incorrect_rules -gt 0 ]];
    then
        echo '*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT' > /etc/sysconfig/iptables
    fi

    if [[ -f /etc/sysconfig/iptables-config ]];
    then
        sed -i "/IPTABLES_MODULES_UNLOAD/d" /etc/sysconfig/iptables-config
        echo 'IPTABLES_MODULES_UNLOAD="no"' >> /etc/sysconfig/iptables-config
    fi

    iptables -I INPUT -m tcp -p tcp --dport 80 -j ACCEPT 1> /dev/null 2>&1 && \
    iptables -I INPUT -m tcp -p tcp --dport 443 -j ACCEPT 1> /dev/null 2>&1 && \
    iptables -I INPUT -p tcp -m tcp --sport 443 -j ACCEPT 1> /dev/null 2>&1 && \
    iptables -I INPUT -p tcp -m tcp --sport 80 -j ACCEPT 1> /dev/null 2>&1 &&\
    iptables -I INPUT -p udp -m udp --sport 53 -j ACCEPT 1> /dev/null 2>&1

    if [[ $? -gt 0 ]];
    then
        log_to_file "$BU2035"
        return 2
    fi
    iptables-save > /etc/sysconfig/iptables
}

public_stateful_iptables() {
    replace_firewalld_by_iptables

    iptables -I INPUT -m tcp -p tcp -m state --state NEW --dport 80 -j ACCEPT 1> /dev/null 2>&1 && \
    iptables -I INPUT -m tcp -p tcp -m state --state NEW --dport 443 -j ACCEPT 1> /dev/null 2>&1
    if [[ $? -gt 0 ]];
    then
        log_to_file "$BU2035"
        return 2
    fi
 
    iptables-save > /etc/sysconfig/iptables
}

configure_firewall_daemon() {
    CONFIGURE_IPTABLES=${1:-1}
    CONFIGURE_FIREWALLD=${2:-0}

    # configure iptables_status
    check_iptables_status
    log_to_file "testing iptables status return $iptables_status"

    if [[ $iptables_status != 'stateful' ]];
    then
        if [[ $iptables_status == "disabled" ]];
        then
            log_to_file "$BU2036"
            return 255
        else
            public_stateless_iptables
        fi
    # support statefull
    else
	# VMBITRIX_9.0
	if [[ $OS_VERSION == "9" ]];
	then
	    public_firewalld
	    check_firewalld_status
	elif [[ $OS_VERSION == "7" ]];
	then
	    if [[ $CONFIGURE_FIREWALLD -eq 1 ]];
	    then
		public_firewalld
		check_firewalld_status
		if [[ $firewalld_tolerance == "non_compatible" ]];
		then
		    log_to_file "$BU2037"
		    public_stateful_iptables
		fi
            else
                public_stateful_iptables
            fi
        else
            public_stateful_iptables
        fi
    fi
}

get_server_id() {
    local h="${1}"

    [[ -z ${h} ]] && return 3
    cache_pool_info

    IFS_BAK=$IFS
    IFS=$'\n'
    for srv_info in $POOL_SERVER_LIST; do
        srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # server identifier in ansible inventory
        hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
        if [[ $hostname == "$h" ]];
        then
            echo $srv_name
            return 0
        fi
        if [[ $srv_name == "$h" ]];
        then
            echo $srv_name
            return 0
        fi
    done
    IFS=$IFS_BAK
    IFS_BAK=

    # print unused servers
    if [[ -n "$POOL_UNU_SERVER_LIST" ]];
    then
        IFS_BAK=$IFS
        IFS=$'\n'
 
        for srv_info in $POOL_UNU_SERVER_LIST; do
            srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # short server name
            hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
            if [[ $hostname == "$h" ]];
            then
                echo $srv_name
                return 1
            fi
            if [[ $srv_name == "$h" ]];
            then
                echo $srv_name
                return 1
            fi
        done
        IFS=$IFS_BAK
        IFS_BAK=
    fi
    return 2
}

if_hostname_exists_in_the_pool() {
    local h="${1}"
    cache_pool_info

    IFS_BAK=$IFS
    IFS=$'\n'
    for srv_info in $POOL_SERVER_LIST; do
        srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # server identifier in ansible inventory
        hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
        if [[ $hostname == "$h" ]];
        then
            return 1
        fi
    done
    IFS=$IFS_BAK
    IFS_BAK=

    # print unused servers
    if [[ -n "$POOL_UNU_SERVER_LIST" ]];
    then
        IFS_BAK=$IFS
        IFS=$'\n'
        for srv_info in $POOL_UNU_SERVER_LIST; do
            srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # short server name
            hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
            if [[ $hostname == "$h" ]];
            then
                return 1
            fi
        done
        IFS=$IFS_BAK
        IFS_BAK=
    fi
    return 0
}

if_serverid_exists_in_the_pool() {
    local h="${1}"
    cache_pool_info

    IFS_BAK=$IFS
    IFS=$'\n'
    for srv_info in $POOL_SERVER_LIST; do
        srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # server identifier in ansible inventory
        hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
        if [[ $srv_name == "$h" ]];
        then
            return 1
        fi
    done
    IFS=$IFS_BAK
    IFS_BAK=

    # print unused servers
    if [[ -n "$POOL_UNU_SERVER_LIST" ]];
    then
        IFS_BAK=$IFS
        IFS=$'\n'
        for srv_info in $POOL_UNU_SERVER_LIST; do
            srv_name=$(echo "$srv_info" | awk -F':' '{print $1}') # short server name
            hostname=$(echo "$srv_info" | awk -F':' '{print $5}') # server name 
            if [[ $srv_name == "$h" ]];
            then
                return 1
            fi
        done
        IFS=$IFS_BAK
        IFS_BAK=
    fi
    return 0
}

print_menu_header() {
    [[ $DEBUG -eq 0 ]] && clear
    echo -e "\t\t" $logo
    echo -e "\t\t" $menu_logo
    echo
}

is_ansible_running() {
    IS_ANSIBLE_PROCESS=$(ps -ef | grep ansible-playbook | grep -v grep | wc -l)
    return $IS_ANSIBLE_PROCESS
}

package_mysql() {
    # one-time call
    [[ -n $MYSQL_PACKAGE ]] && return 0

    PACKAGES_LIST=$(rpm -qa)
    if [[ $(echo "$PACKAGES_LIST" | grep -c '^mysql-community-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=mysql-community-server
        MYSQL_SERVICE=mysqld
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mysqld.service
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^Percona-Server-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=Percona-Server-server
        MYSQL_SERVICE=mysqld
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mysqld.service
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^MariaDB-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=MariaDB-server
        MYSQL_SERVICE=mariadb
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mariadb.service
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^mariadb-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=mariadb-server
        MYSQL_SERVICE=mariadb
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mariadb.service
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^mysql-server') -gt 0 ]];
    then
        MYSQL_PACKAGE=mysql-server
        MYSQL_SERVICE=mysqld
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mysql.service
    else
        return 1
    fi
    MYSQL_VERSION=$(rpm -qa --queryformat '%{version}' ${MYSQL_PACKAGE}* | head -1 | awk -F'.' '{printf "%d.%d", $1,$2}' )
    MYSQL_MID_VERSION=$(echo "$MYSQL_VERSION" | awk -F'.' '{print $2}')
}

bx_alternatives_for_mycnf() {
    is_mycnf_alters=$(alternatives --list | grep "^my\.cnf\s\+" -c)
    is_percona_alternatives=$(alternatives --list  | grep "^my\.cnf\s\+" | grep -cv '/etc/bitrix-my.cnf')
    [[ $is_mycnf_alters -eq 0 ]] && return 0            # doesn't use alternatives; skip
    [[ $is_percona_alternatives -eq 0 ]] && return 0    # already created bitrix alternatives; skip

    BACKUP_CFG_DIR=/etc/ansible/roles/mysql/files
    package_mysql

    BACKUP_CFG_FILE=$BACKUP_CFG_DIR/my.cnf.bx
    [[ $MYSQL_MID_VERSION -eq 6 ]] && BACKUP_CFG_FILE=$BACKUP_CFG_DIR/my.cnf.bx_mysql56
    [[ $MYSQL_MID_VERSION -eq 7 ]] && BACKUP_CFG_FILE=$BACKUP_CFG_DIR/my.cnf.bx_mysql57

    cp -f $BACKUP_CFG_FILE /etc/bitrix-my.cnf
    rm -f /etc/my.cnf
    update-alternatives --install /etc/my.cnf my.cnf "/etc/bitrix-my.cnf" 300
}

bx_repo_version() {
    repo_file=/etc/yum.repos.d/bitrix.repo

    [[ ! -f  $repo_file ]] && return 0

    is_bitrix_beta="$(cat $repo_file | grep -w bitrix-beta)"
    [[ -z "$is_bitrix_beta" ]] && is_bitrix="$(cat $repo_file | grep -w bitrix)"
    [[ -n $is_bitrix_beta ]] && return 2
    [[ -n $is_bitrix ]] && return 1
    return 0
}

bx_enable_beta_version() {
    get_os_type

    echo "[bitrix-beta]
name=Bitrix Env Beta - CentOS-$OS_VERSION - \$basearch
failovermethod=priority
baseurl=https://repo.bitrix.info/yum-beta/el/$OS_VERSION/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo.bitrix.info/yum/RPM-GPG-KEY-BitrixEnv
" > /etc/yum.repos.d/bitrix.repo

    yum clean all > /dev/null 2>&1
}

bx_disable_beta_version() {
    get_os_type

    echo "[bitrix]
name=Bitrix Env - CentOS-$OS_VERSION - \$basearch
failovermethod=priority
baseurl=https://repo.bitrix.info/yum/el/$OS_VERSION/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo.bitrix.info/yum/RPM-GPG-KEY-BitrixEnv
" > /etc/yum.repos.d/bitrix.repo

    yum clean all > /dev/null 2>&1
}

bx_update_master_network() {
    current=${1}
    saved=${2}
    host=${3}
    is_push=${4}

    ANSIBLE_CHANGED="/etc/ansible/hosts
/etc/ansible/host_vars/$host
/etc/ansible/group_vars/bitrix-hosts.yml
/etc/ansible/group_vars/bitrix-mysql.yml
/etc/ansible/group_vars/bitrix-web.yml
/etc/ansible/ansible-roles
/etc/hosts
/etc/sysconfig/iptables"

    for file in $ANSIBLE_CHANGED; do
        if [[ -f $file && $(grep -c "$saved" $file) -gt 0 ]];
        then
            sed -i "s/$saved/$current/g" $file
            log_to_file "Replace IP $current to $saved in $file"
            if [[ $file == "/etc/sysconfig/iptables" ]];
            then
                iptables-restore < /etc/sysconfig/iptables
            fi
        fi
    done

    [[ $is_push -eq 0 ]] && return 0

    PUSH_CHANGED="/etc/sysconfig/push-server-multi"
    for file in $PUSH_CHANGED; do
        if [[ -f $file && $(grep -c "$saved" $file) -gt 0 ]];
        then
            sed -i "s/$saved/$current/g" $file
            log_to_file "Replace NET $current to $saved in $file"
        fi
    done

    pushd /etc/push-server > /dev/null 2>&1
    for file in *.json; do
        if [[ -f $file && $(grep -c "$saved" $file) -gt 0 ]];
        then
            sed -i "s/$saved/$current/g" $file
            log_to_file "Replace NET $current to $saved in $file"
        fi
    done
    popd > /dev/null 2>&1
    # push service will be started by autostart option
}

bx_ansible_network() {
    get_client_settings

    if [[ $IS_MASTER -eq 0 ]];
    then 
        return 1
    fi

    # CLIENT_INT - interface
    # CLIENT_IP - ip address
    # IS_PUSH - bitrix-push
    # CLIENT_NAME
    VISIBLE_INTS=$(ip link  |  grep '^[0-9]\+:' | grep -v lo | awk '{print $2}' | sed -e 's/://')
    IS_EXISTEN_INT=$(echo "$VISIBLE_INTS" | grep -cw "^$CLIENT_INT$")
    IF_MISMATCH_IP=0
    IS_NET_CHANGED=0
    if [[ $IS_EXISTEN_INT -gt 0 ]];
    then
        CURRENT_IP=$(ip addr show $CLIENT_INT | egrep "inet\s+[0-9\.]+" | awk '{print $2}' | awk -F'/' '{print $1}')
        [[ $CURRENT_IP != "$CLIENT_IP" ]] && IF_MISMATCH_IP=1
    fi

    # case 01
    # interface doesn't change and ip doesn't change
    if [[ $IS_EXISTEN_INT -gt 0 && $IF_MISMATCH_IP -eq 0 ]];
    then
        return 0
    fi

    # case 02
    # interface doesn't change but IP is changed
    # we need
    # 1. change IP address in ansible configs
    # 2. change IP address in push-server configs
    # 3. update /etc/hosts
    # 4. if there is other hosts in the pool run common task
    if [[ $IS_EXISTEN_INT -gt 0 && $IF_MISMATCH_IP -eq 1 ]];
    then
        bx_update_master_network "$CURRENT_IP" "$CLIENT_IP" "$CLIENT_NAME" "$IS_PUSH"
    fi

    if [[ $IS_EXISTEN_INT -eq 0 ]];
    then
        CURRENT_INTS=$(ip link list | grep '^[0-9]\+:' | grep -v lo | awk '{print $2}' | sed -e 's/://')
        CURRENT_INT=
        CURRENT_IP=
        for int in $CURRENT_INTS; do
            [[ -n $CURRENT_IP && -n $CURRENT_INT ]] && continue
            ipv4=$(ip addr show $int | egrep "inet\s+[0-9\.]+" | awk '{print $2}' | awk -F'/' '{print $1}')
            if [[ -n $ipv4 ]];
            then
                CURRENT_IP=$ipv4
                CURRENT_INT=$int
            fi
        done
        if [[ -z $CURRENT_IP && -z $CURRENT_INT ]];
        then
            log_to_file "There are no active network interfaces"
            return 1
        fi
        bx_update_master_network "$CURRENT_IP" "$CLIENT_IP" "$CLIENT_NAME" "$IS_PUSH"
        bx_update_master_network "$CURRENT_INT" "$CLIENT_INT" "$CLIENT_NAME" 0
        IS_NET_CHANGED=1
    fi

    rm -f /opt/webdir/tmp/*
    return 0
}
