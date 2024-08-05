#!/usr/bin/bash
#
export LANG=en_US.UTF-8
export TERM=linux
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
VERBOSE=0
BASE_DIR=/opt/webdir
LOGS_DIR=$BASE_DIR/logs
TEMP_DIR=$BASE_DIR/temp
LOGS_FILE=$LOGS_DIR/pool_menu.log
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/bitrix_utils.sh || exit 1

logo=$(get_logo)

ansible_wrapper=$PROGPATH/wrapper_ansible_conf # parse config file, add and change data in the ansible configuration
bx_monotor_script=$PROGPATH/bx-monitor         # manage monitoring 
bx_process_script=$PROGPATH/bx-process         # manage background tasks
bx_mysql_script=$PROGPATH/bx-mysql             # manage mysql servers
bx_mc_script=$PROGPATH/bx-mc                   # manage memcached servers

ansible_hosts=/etc/ansible/hosts               # file contains configuration of hosts and groups 
ansible_copy_keys=$PROGPATH/ssh_keycopy        # expect script that copy ssh key by input user and password string 
ansible_changepwd=$PROGPATH/ssh_chpasswd       # expect script that change user password
log_copy_keys=$LOGS_DIR/ssh_keycopy.log
log_changepwd=$LOGS_DIR/ssh_chpasswd.log
ansible_pool_flag=/etc/ansible/ansible-roles

# test client settings
get_client_settings
if [[ ( $IN_POOL -eq 1 ) && ( $IS_MASTER -eq 0 ) ]]; then
    print_color_text "$MM0001" red
    print_color_text "$MM0002" green
    printf "%15s : %s\n" "$MM0003" "$MASTER_NAME"
    printf "%15s : %s\n" "$MM0004" "$MASTER_IP"
    printf "%15s : %s\n" "$MM0006" "$CLIENT_IP"
    print_color_text "$MM0007!!!" green
    exit 0
fi

# test additional scripts
if [[ ! -x $bx_monotor_script ]]; then
    print_color_text "$(get_text "$MM0008"  "$bx_monotor_script"). $MM0007!"
    exit 1
fi

if [[ ! -x $bx_process_script ]]; then
    print_color_text "$(get_text "$MM0008"  "$bx_process_script"). $MM0007!"
    exit 1
fi
 
######################### MENU POINTS
menu_create_pool_1="1.  $MM0010"
menu_hosts_manage_1="1.  $MM0011"
menu_local_2="2.  $MM0012"
menu_monitoring_3="3.  $MM0019"
menu_sites_4="4.  $MM0016"
menu_web_5="5.  $MM0018"
menu_push_6="6.  $MM0020"
menu_jobs_7="7.  $MM0015"
menu_trans_8="8.  $MM00201"

menu_default_exit="0.  $MM0007."

# create configuration mgmt environment
# all action do wrapper, but it can return error
# CREATE_POOL
create_pool_1() {
    [[ $DEBUG -eq 0 ]] && clear
  
    POOL_CREATE_OPTION_INT=
    POOL_CREATE_OPTION_HOST=
    until [[ ( -n "$POOL_CREATE_OPTION_INT" ) && ( -n "$POOL_CREATE_OPTION_HOST" )  ]]; do
        [[ $DEBUG -eq 0 ]] && clear;
        # print header
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" "$MM0021"
        echo

        # POOL_CREATE_OPTION_INT 
        # if host has several interfaces, user must choose
        if [[ $HOST_NETWORK -gt 1 ]]; then
            print_color_text "$MM0022" green
            echo
      
            for _info_ip in $HOST_IPS; do
                int=$(echo $_info_ip | awk -F'=' '{print $1}')
                ip=$(echo $_info_ip | awk -F'=' '{print $2}')
                echo "$int: $ip"
            done
      
            print_message  "$MM0023" "$MM0024" "" _interface
            if [[ $(echo "$HOST_IPS" | grep -cw "$_interface") -gt 0 ]]; then
                POOL_CREATE_OPTION_INT=$_interface
                # create configuration with IP
            else
                print_message "$MM0025" \
                    "$(get_text "$MM0026" "$_interface")" \
                    "" _user
                [[ $(echo "$_user" | grep -wci 'y') -eq 0 ]] && exit 1
                continue
            fi
        # one interface, one choose options
        elif [[ $HOST_NETWORK -eq 1 ]]; then
            POOL_CREATE_OPTION_INT=$(echo "$HOST_IPS" | awk -F'=' '{print $1}')
        else
            print_message "$BU1001" \
                "$MM0027" "" any_key
            exit
        fi

        # POOL_CREATE_OPTION_HOST
        # hostname, may be user want to change it
        _hostname=$(hostname)
        print_message "$(get_text "$MM0028" "$_hostname")" \
            "$MM0029" \
            "" _hostname $_hostname
        # test hostname
        if [[ -n "$_hostname" ]]; then
            POOL_CREATE_OPTION_HOST=$_hostname
        else
            print_message "$MM0025 " \
                "$MM0030" \
                "" _host_user
            [[ $(echo "$_user" | grep -wci 'y') -eq 0 ]] && exit 1
        fi
    done

    # subinterfaces via IPADDR2 and PREFIX2
    if [[ $(echo "$POOL_CREATE_OPTION_INT" | grep -c '/[0-9]\+' ) -gt 0 ]]; then
        POOL_CREATE_OPTION_IP=$(echo "$HOST_IPS" | \
            egrep -o "$POOL_CREATE_OPTION_INT=\S+" | awk -F'=' '{print $2}')
        POOL_CREATE_OPTION_INT=$(echo $POOL_CREATE_OPTION_INT | awk -F'/' '{print $1}')
    fi


    [[ $DEBUG -gt 0 ]] && \
        echo "cmd=$ansible_wrapper -a create -H $POOL_CREATE_OPTION_HOST -I $POOL_CREATE_OPTION_INT"
    output=$($ansible_wrapper -a create -H $POOL_CREATE_OPTION_HOST \
        -I $POOL_CREATE_OPTION_INT)

    # test on error message
    error=$(  echo "$output" | grep '^error:'   | sed -e 's/^error://')
    message=$(echo "$output" | grep '^message:' | sed -e 's/^message://')
    any_key=
    if [[ -n "$error" ]]; then
        print_message "$MM0031 $BU1001" \
            "$message" '' 'any_key'
    else
        print_message "$MM0032 $BU1002"  \
            "$message" '' 'any_key'
    fi
}

# manage host in the pool
hosts_manage() {
  $PROGPATH/menu/01_host_crm.sh
}

# manage localhost settings
localhost_manage(){
  $PROGPATH/menu/02_local.sh
}


# manage mysql servers in the pool
hosts_mysql(){
  $PROGPATH/menu/03_mysql.sh
}

# manage memcached servers in the pool
hosts_memcached(){
  $PROGPATH/menu/04_memcached.sh
}

# manage tasks on the server
hosts_tasks(){
  $PROGPATH/menu/05_task.sh
}

# manage sites on the pool
sites_manage(){
  $PROGPATH/menu/06_site_crm.sh
}

hosts_sphinx(){
  $PROGPATH/menu/07_sphinx.sh
}

hosts_web(){
  $PROGPATH/menu/08_web_crm.sh
}

# manage monitoring options for server pool
hosts_monitoring(){
  $PROGPATH/menu/09_monitor.sh
}

push_service(){
  $PROGPATH/menu/10_push_crm.sh
}

transformer_service(){
    if [[ -z $OS_VERSION ]]; then
        get_os_type
    fi
    if [[ $OS_VERSION -ge 7 ]]; then
        $PROGPATH/menu/11_transformer.sh
    else
        print_message "There is no support for CentOS $OS_VERSION version" \
            "press any key to continue" "" any_key
        return 1
    fi
}


# main menu for pool manage
menu_server_list(){
  logo_msg="$MM0033"
  test_passw_bitrix_localhost

  POOL_SELECTION=
  POOL_MAIN_CONFIG=/etc/ansible/group_vars/bitrix-hosts.yml
  POLL_HOST_CONFIG=/etc/ansible/ansible-roles
  until [[ "$POOL_SELECTION" == "0" ]]; do
    [[ $DEBUG -eq 0 ]] && clear;
    # print header
    echo -e "\t\t\t" $logo
    echo -e "\t\t\t" $logo_msg
    echo

    # not found pool configuation
    if [[ ! -f $POOL_MAIN_CONFIG ]]; then
      if [[ -f $POLL_HOST_CONFIG ]]; then
        print_header "$MM0034"
        echo $BU0029
        echo -e "\t\t" $menu_default_exit
      else
        print_header "$MM0035"
        get_local_network $LINK_STATUS
        if [[ $HOST_NETWORK -gt 0 ]]; then
          print_color_text "$MM0036" red
          echo "$BU0029"
          #echo -e "\t\t " $menu_create_pool_1
          #echo -e "\t\t " $menu_local_2
          echo -e "\t\t " $menu_default_exit
        else
          echo "$BU0029"
          #echo -e "\t\t " $menu_local_2
          echo -e "\t\t " $menu_default_exit
        fi
      fi
      print_message "$MM0037" '' '' POOL_SELECTION

      case "$POOL_SELECTION" in
        #"1") create_pool_1; HOST_NETWORK=; HOST_NETWORK_INFO=;;
        #"2") localhost_manage;;
        "0") exit;;
        *)   error_pick;;
      esac
      POOL_SELECTION=
    else
      print_pool_info

      echo "$BU0029"
      #echo -e "\t\t" $menu_hosts_manage_1
      #echo -e "\t\t" $menu_local_2
      #echo -e "\t\t" $menu_monitoring_3
      #echo -e "\t\t" $menu_sites_4
      #echo -e "\t\t" $menu_web_5
      #echo -e "\t\t" $menu_push_6
      #echo -e "\t\t" $menu_jobs_7
      echo -e "\t\t" $menu_default_exit
      print_message "$MM0037" '' '' POOL_SELECTION

      case "$POOL_SELECTION" in 
        #"1"|a)  hosts_manage; POOL_SERVER_LIST=;;
        #"2"|c)  localhost_manage;;
        #"3"|d)  hosts_monitoring;;
        #"4"|e)  sites_manage;;
        #"5"|l)  hosts_web;;
        #"6"|g)  push_service;;
        #"7"|i)  hosts_tasks; POOL_SERVER_LIST=;;
        0|z)  exit;;
        *)    error_pick;;
      esac
      POOL_SELECTION=
 
    fi
 done
}

# action part
menu_server_list
