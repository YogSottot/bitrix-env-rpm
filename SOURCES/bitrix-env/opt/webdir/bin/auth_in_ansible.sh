#!/usr/bin/bash
#
# manage ssh keys for ansible
# 1. create ney key for host ( removes previous keys )
# 2. removes the outdated keys
#
# auth E.Shemaeva
# created 30/01/2014
#
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
VERBOSE=0
BASE_DIR=/opt/webdir
LOGS_DIR=$BASE_DIR/logs
TEMP_DIR=$BASE_DIR/temp
TMPL_DIR=$BASE_DIR/templates
LOGS_FILE=$LOGS_DIR/$(echo $PROGNAME | sed -e 's/\.sh$//').log

# print help message
print_usage() {
  _return_code=$1

  echo "Usage: $PROGNAME -o mgmt|key [-hv] [ -t livetime_for_key ] [ -u sshuser ] [-s secret] [ -k keyid ] [-b location]"
  echo " -o - determines action script;"
  echo "      mgmt   - configure server for mgmt role"
  echo "      key    - get current mgmt key file"
  echo " -b - location in the web through which the key will be available"
  echo " -u - ssh user ( default: root )"
  echo " -t - lifetime for ssh keys in seconds ( default: 900s = 15m )"
  echo " -k - ssh key id, used for the point clear"
  echo " -s - secret link that allows to get a  sshkey to enter the server"
  echo " -h - show this message"
  echo " -v - enable verobose mode"
  echo

 exit $_return_code
}

# save information in log file
print_log() {
  _log_message=$1
  if [[ -n "$LOGS_FILE" ]]; then
    log_date=$(date +'%Y-%m-%dT%H:%M:%S')
    # exclude test domain
    printf "%-14s: %6d: %s\n" "$log_date" "$$" "$_log_message" >> $LOGS_FILE
  fi
}

# print information and exit
# here identifies possible return codes from script
# main rule:
# 0xx - notice message    and return_code=0
# 1xx - warning message   and return_code=1
# 2xx - critical message  and return_code=2
# 3xx - impossible message/situation and return_code=3
print_and_exit() {
  _exit_code=$1
  _exit_opt=$2

  return_mess="CODE_$_exit_code: "
  return_code=$(echo ${_exit_type:0:1})

  case $_exit_code in
    "101")
      return_mess=$return_mess"'-o' - is mandatory option. Use '-h' for help message."
    ;;
    "102")
      return_mess=$return_mess"'-o' can contain 'create' or 'clear' values only."
    ;;
    "103")
      return_mess=$return_mess"Ansible key already installed on this server."
    ;;
    "104")
      return_mess=$return_mess"$_exit_opt already exists in ansible system"
    ;;
    "201")
      return_mess=$return_mess"Can't create ssh key $_exit_opt"
    ;;
    "202")
      return_mess=$return_mess"Can't found ssh key for user $_exit_opt"
    ;;
    "203")
      return_mess=$return_mess"To add the client must specify the link with key"
    ;;
    "204")
      return_mess=$return_mess"Not found Annsible key for master. May be you must create it - '-o mgmt'"
    ;;
    "205")
      return_mess=$return_mess"Ansible key is found but it is empty."
    ;;
    "206")
      return_mess=$return_mess"Cannot access to the key $_exit_opt"
    ;;
    "207")
      return_mess=$return_mess"Cannot connect to $_exit_opt"
    ;;
    "001")
      return_mess=$return_mess"To add a machine to control, enter the following link in the interface\n"
      return_mess=$return_mess"$_exit_opt\n"
      return_mess=$return_mess"Attention! The file is temporary and will be removed in $SSHTIME seconds."
    ;;
    "002")
      return_mess=$return_mess"Delete old keys file is complete. Was removed $_exit_opt key(s)."
    ;;
    "003")
      return_mess=$return_mess"Create new key $_exit_opt for Ansible"
    ;;
    "004")
      return_mess=$return_mess"Client $_exit_opt is added"
    ;;
    *)
      return_mess=$return_mess"$_exit_opt"
    ;;
  esac

  print_log "$return_mess"

  echo -e "$return_mess"
  exit $return_code
}

get_ip_addr() {
  # get firt ip address for host
  ip -f inet -o addr show | cut -d\  -f 7 | cut -d/ -f 1 | grep -v '127\.0\.0\.1' | head -1
}

# set host like ansible master/mgmt server
# create key key that will be used on other machine
set_mgmt_role() {
  _sshuser=$1

  #  home of user
  sshhome=$(getent passwd $_sshuser| cut -d':' -f6)
  sshdir=/etc/ansible/.ssh
  [[ ! -d $anshome ]] && mkdir -m 700 $anshome
  sshconf=$sshdir/config
  [[ -z "$sshhome" ]] && print_and_exit "202" "$_sshuser"

  # test if it's already installed
  [[ ( -f $sshconf ) && ( $(grep -c 'ANSIBLE_KEY' $sshconf) -gt 0 ) ]] && print_and_exit "103" 

  # create new
  sshid=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32)_$(date +%s)
  sshkey=$sshdir/$sshid.bxkey

  ssh-keygen -t rsa -N "" -f $sshkey -C "ANSIBLE_KEY_$(hostname -s)" 1>/dev/null 2>&1      
  if [[ $? -gt 0 ]]; then
    print_and_exit "201" "$sshkey"
  fi

  # set value to config file
  #echo -e "# ANSIBLE_KEY_$sshid\nhost *\n  StrictHostKeyChecking no\n  user $_sshuser\n  identityfile $sshkey\n\n" >> $sshconf
  echo -e "# ANSIBLE_KEY_$sshid\nhost *\n  user $_sshuser\n  identityfile $sshkey\n\n" >> $sshconf

  # add default config options to ansible hosts file
  ansible_template=$TMPL_DIR/ansible/hosts
  ansible_config=/etc/ansible/hosts
  if [[ -f $ansible_template ]]; then
    hostname=$(hostname -s)
    sed -e "s/__HOSTNAME__/$hostname/g" $ansible_template >> $ansible_config
  fi

  print_and_exit "003" "$sshid"
}

# get ssh key info from config file
ssh_key() {
  _sshuser=$1

  #  home of user
  sshhome=$(getent passwd $_sshuser| cut -d':' -f6)
  sshdir=$sshhome/.ssh
  sshconf=$sshdir/config
  sshauth=$sshdir/authorized_keys
  if [[ -z "$sshhome" ]]; then
    print_and_exit "202" "$_sshuser"
  fi

  sshid=$(awk -F'_' '/ANSIBLE_KEY/{printf "%s_%s",$3,$4}' $sshconf)
  # if key doesn't exist
  [[ -z "$sshid" ]] && print_and_exit "204"
  
  #ssh public key
  sshkey="$sshdir/$sshid.bxkey.pub"
  [[ ! -f "$sshkey" ]] && print_and_exit "205"
  
  # print info about key
  print_and_exit 005 "$sshkey"
}

# parse command line argvs
while getopts ":o:b:u:t:k:s:vh" opt; do
  case $opt in
  h)
    print_usage 0
  ;;
  o)
    OP=$OPTARG
  ;;
  b)
    BWEB=$OPTARG
  ;;
  u)
    SSHUSER=$OPTARG
  ;;
  t)
    SSHTIME=$OPTARG
  ;;
  k)
    SSHKEY=$OPTARG
  ;;
  s)
    SSHLINK=$OPTARG
  ;;
  v)
    VERBOSE=1
  ;;
  \?)
    print_usage 1
  ;;
  esac
done

[[ -z "$OP" ]] && print_and_exit 101
[[ -z "$BWEB" ]] && BWEB=webkey
[[ -z "$SSHUSER" ]] && SSHUSER=root
[[ -z "$SSHTIME" ]] && SSHTIME=900

case $OP in
  "mgmt")
    set_mgmt_role $SSHUSER
  ;;
  "key")
    ssh_key "$SSHUSER"
  ;;
  *)
    print_and_exit 102
  ;;
esac
