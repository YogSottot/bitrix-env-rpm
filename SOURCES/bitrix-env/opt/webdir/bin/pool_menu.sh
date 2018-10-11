#!/bin/bash
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
  print_color_text "You can not use the menu: host $(hostname) already in the pool" green
  printf "%15s : %s\n" "Manager Host" "$MASTER_NAME"
  printf "%15s : %s\n" "Manager IP" "$MASTER_IP"
  printf "%15s : %s\n" "Client IP" "$CLIENT_IP"
  print_color_text "Exit!!" green
  exit 0
fi

# test additional scripts
if [[ ! -x $bx_monotor_script ]]; then
  echo "Not found $bx_monotor_script. Exit"
  exit 1
fi

if [[ ! -x $bx_process_script ]]; then
  echo "Not found $bx_process_script. Exit"
  exit 1
fi
 
# empty pool menu
menu_create_pool_1="1.  Create Management pool of server";  # create_pool_1
# manage host and roles menu
menu_hosts_manage_1="1.  Manage Hosts in the pool";     # hosts_manage

# manage localhost settings
menu_local_2="2.  Manage localhost"

# manage mysql servers
menu_mysql_srv_3="3.  Configure MySQL servers"                # hosts_mysql
# manage memcached servers
menu_mc_srv_4="4.  Configure memcahed servers"                # hosts_memcached

menu_jobs_5="5.  Background tasks in the pool"              # view information about background tasks

menu_sites_6="6.  Manage sites in the pool"                 # manage sites on the server

menu_sphinx_7="7.  Manage sphinx in the pool"

menu_web_8="8.  Manage web nodes in the pool"

# manage monitoring in the pool
menu_monitoring_9="9.  Monitoring in pool";                   # hosts_monitoring

# default exit menu for all screens
menu_default_exit="0. Exit"

# create configuration mgmt environment
# all action do wrapper, but it can return error
# CREATE_POOL
create_pool_1() {
    clear
  
    POOL_CREATE_OPTION_INT=
    POOL_CREATE_OPTION_HOST=
    until [[ ( -n "$POOL_CREATE_OPTION_INT" ) && ( -n "$POOL_CREATE_OPTION_HOST" )  ]]; do
        clear;
        # print header
        echo -e "\t\t\t" $logo
        echo -e "\t\t\t" "Create initial config for pool and manager server"
        echo

        # POOL_CREATE_OPTION_INT 
        # if host has several interfaces, user must choose
        if [[ $HOST_NETWORK -gt 1 ]]; then
            print_color_text "Found network interfaces on the server: " green
            echo
      
            for _info_ip in $HOST_IPS; do
                int=$(echo $_info_ip | awk -F'=' '{print $1}')
                ip=$(echo $_info_ip | awk -F'=' '{print $2}')
                echo "$int: $ip"
            done
      
            print_message "Please select interface name that will be used for manage: " "" "" _interface
            if [[ $(echo "$HOST_IPS" | grep -cw "$_interface") -gt 0 ]]; then
                POOL_CREATE_OPTION_INT=$_interface
                # create configuration with IP
            else
                print_message "Want to try again(Y|n) " "Not found interface $_interface" "" _user
                [[ $(echo "$_user" | grep -wci 'y') -eq 0 ]] && exit 1
                continue
            fi
        # one interface, one choose options
        elif [[ $HOST_NETWORK -eq 1 ]]; then
            POOL_CREATE_OPTION_INT=$(echo "$HOST_IPS" | awk -F'=' '{print $1}')
        else
            print_message "Press ENTER to exit" "Not found running interfaces on host" "" any_key
            exit
        fi

        # POOL_CREATE_OPTION_HOST
        # hostname, may be user want to change it
        _hostname=$(hostname)
        print_message "Enter new name for master (default=$_hostname): " \
            "You can use the FQDN (ex, an public DNS for Amazon)" \
            "" _hostname $_hostname
        # test hostname
        if [[ -n "$_hostname" ]]; then
            POOL_CREATE_OPTION_HOST=$_hostname
        else
            print_message "Want to try again(Y|n) " "Cannot use empty hostname" "" _host_user
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
        print_message "CREATE_POOL error: Press ENTER for exit: " "$message" '' 'any_key'
    else
        print_message "CREATE_POOL complete: Press ENTER for exit: " "$message" '' 'any_key'
    fi
}

# manage host in the pool
hosts_manage() {
  $PROGPATH/menu/01_host.sh
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
  $PROGPATH/menu/06_site.sh
}

hosts_sphinx(){
  $PROGPATH/menu/07_sphinx.sh
}

hosts_web(){
  $PROGPATH/menu/08_web.sh
}

# manage monitoring options for server pool
hosts_monitoring(){
  $PROGPATH/menu/09_monitor.sh
}

push_service(){
  $PROGPATH/menu/10_push.sh
}


# main menu for pool manage
menu_server_list(){
  
  logo_msg="Pool Configuration manager on this host"
  test_passw_bitrix_localhost

  POOL_SELECTION=
  POOL_MAIN_CONFIG=/etc/ansible/group_vars/bitrix-hosts.yml
  POLL_HOST_CONFIG=/etc/ansible/ansible-roles
  until [[ "$POOL_SELECTION" == "0" ]]; do
    clear;
    # print header
    echo -e "\t\t\t" $logo
    echo -e "\t\t\t" $logo_msg
    echo

    # not found pool configuation
    if [[ ! -f $POOL_MAIN_CONFIG ]]; then
      if [[ -f $POLL_HOST_CONFIG ]]; then
        print_header "This host already in the pool"
        echo Available actions:
        echo -e "\t\t" $menu_default_exit
      else
        print_header "Not found configured server's pool! May be You want to add new."
        get_local_network $LINK_STATUS
        if [[ $HOST_NETWORK -gt 0 ]]; then
          print_color_text "If you want to add the server to an existing cluster" red
          print_color_text "Use one of the addresses listed above on master server" red
          echo Available actions:
          echo -e "\t\t " $menu_create_pool_1
          echo -e "\t\t " $menu_local_2
          echo -e "\t\t " $menu_default_exit
        else
          echo Available actions:
          echo -e "\t\t " $menu_default_exit
        fi
      fi
      print_message 'Enter selection: ' '' '' POOL_SELECTION

      case "$POOL_SELECTION" in
        "1") create_pool_1; HOST_NETWORK=; HOST_NETWORK_INFO=;;
	      "2") localhost_manage;;
        "0") exit;;
        *)   error_pick;;
      esac
      POOL_SELECTION=
    else
      print_pool_info

      echo Available actions:
      echo -e "\t\t" $menu_hosts_manage_1
      echo -e "\t\t" $menu_local_2
      echo -e "\t\t" $menu_mysql_srv_3
      echo -e "\t\t" $menu_mc_srv_4
      echo -e "\t\t" $menu_jobs_5
      echo -e "\t\t" $menu_sites_6
      echo -e "\t\t" $menu_sphinx_7
      echo -e "\t\t" $menu_web_8
      echo -e "\t\t" $menu_monitoring_9
      echo -e "\t\t" "10. Configure Push/RTC service"
      echo -e "\t\t" $menu_default_exit
      print_message 'Enter selection: ' '' '' POOL_SELECTION

      case "$POOL_SELECTION" in 
        "1"|a)  hosts_manage; POOL_SERVER_LIST=;;
        "2"|c)  localhost_manage;;
        "3"|d)  hosts_mysql;;
        "4"|e)  hosts_memcached;;
        "5"|f)  hosts_tasks; POOL_SERVER_LIST=;;
        "6"|g)  sites_manage;;
        "7"|i)  hosts_sphinx;;
        "8"|k)  hosts_web;;
        "9"|l)  hosts_monitoring;;
        "10"|m) push_service;;
        0|z)  exit;;
        *)    error_pick;;
      esac
      POOL_SELECTION=
 
    fi
 done
}


# action part
menu_server_list
