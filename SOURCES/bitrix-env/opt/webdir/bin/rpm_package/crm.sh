#!/usr/bin/bash
#
# post installation script for bitrix-env
# 1. create bitrix user
# 2. configure mysql/mariadb service
#set -x
#
export LANG=en_US.UTF-8
export NOLOCALE=yes
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

RPM_ACTION="${1:-undefined}"
BITRIX_ENV_VER="${2}"
BITRIX_ENV_TYPE=${3:-general}

[[ $BITRIX_ENV_TYPE == "general" ]] && exit 0

OS_VERSION=$(cat /etc/redhat-release | sed -e "s/CentOS Linux release//;s/CentOS release // " | cut -d'.' -f1)
UPDATE_TM=$(date +'%Y%m%d%H%M')
PHP_VERSION=$(php -v | grep ^PHP | awk '{print $2}' | awk -F'.' '{print $1}')
NGINX_VERSION=$(nginx -v 2>&1 | grep "^nginx version" | awk -F'/' '{print $2}')

# configure logging
LOG_DIR=/opt/webdir/logs
[ ! -d $LOG_DIR  ] && mkdir -p $LOG_DIR
LOGS_FILE=$LOG_DIR/${RPM_ACTION}-${BITRIX_ENV_VER}.log
[[ -z $DEBUG ]] && DEBUG=0

log_to_file() {
    log_message="${1}"
    notice="${2:-INFO}"
    printf "%20s: %5s [%s] %s\n" "$(date +"%Y/%m/%d %H:%M:%S")" $$ "$notice" "$log_message" >> $LOGS_FILE
    [[ $DEBUG -gt 0 ]] && printf "%20s: %5s [%s] %s\n" "$(date +"%Y/%m/%d %H:%M:%S")" $$ "$notice" "$log_message" 1>&2
}

service_manage() {
    local service="${1}"
    local action="${2}"
    local restart_rtn=0

    [[ ( -z $action ) || ( -z $service ) ]] && exit 1

    if [[ $OS_VERSION -eq 7 ]]; then
        if [[ "$action" != "status" ]]; then
            systemctl $action $service >> $LOGS_FILE 2>&1
            restart_rtn=$?
        else
            systemctl is-active $service >/dev/null 2>&1
            return $?
        fi
    else
        if [[ $action == "status" ]]; then
            /etc/init.d/$service status | grep -wc running >/dev/null 2>&1
            return $?
        elif [[ "$action" == "enable" ]]; then
            chkconfig --add $service >/dev/null 2>&1
            chkconfig $service on >/dev/null 2>&1
        else
            service $service $action >> $LOGS_FILE 2>&1
            restart_rtn=$?
        fi
    fi

    if [[ $restart_rtn -gt 0 ]]; then
        log_to_file "Cannot $action for $service service" "ERROR"
        exit 1
    else
        log_to_file "Service $service is ${action}ed"
    fi
}

configure_push() {
    INVENTORY_TEMP=/etc/ansible/hosts.push
    PLAYBOOK_OPTIONS=/etc/ansible/push.yml
    PLAYBOOK_FILE=/etc/ansible/push-server.yml
    
    # temporary inventory file
    echo "[bitrix-hosts]"                                       >  $INVENTORY_TEMP
    echo "localhost ansible_connection=local"                   >> $INVENTORY_TEMP
    echo                                                        >> $INVENTORY_TEMP
    echo "[bitrix-hosts:vars]"                                  >> $INVENTORY_TEMP
    echo "bx_netaddr=127.0.0.1"                                 >> $INVENTORY_TEMP
    echo "cluster_web_server=localhost"                         >> $INVENTORY_TEMP

    # playbok options
    echo "---"                              >  $PLAYBOOK_OPTIONS
    echo "manage: configure_nodejs"         >> $PLAYBOOK_OPTIONS
    echo "hostname: localhost"              >> $PLAYBOOK_OPTIONS
    echo "is_rpm: True"                     >> $PLAYBOOK_OPTIONS

    ansible-playbook $PLAYBOOK_FILE -i $INVENTORY_TEMP -e "ansible_playbook_file=$PLAYBOOK_OPTIONS" >> $LOGS_FILE 2>&1
    if [[ $? -gt 0 ]]; then
        log_to_file "Cannot configure push server" "ERROR"
    else
        log_to_file "Configure push server"
        rm -f $INVENTORY_TEMP $PLAYBOOK_OPTIONS
    fi
}

configure_memcached() {
    # memory
    mem=$(free | grep Mem | awk '{print $2}')
    mc_mem=$(( $mem / 8 ))

    # sysconfig/memcached
    echo "
PORT=11211
USER=\"bitrix\"
MAXCONN=\"1024\"
CACHESIZE=\"$mc_mem\"
OPTIONS=\"-s /tmp/memcached.sock\"" > /etc/sysconfig/memcached
    log_to_file "Create /etc/sysconfig/memcached config"

    # start service
    service_manage memcached enable
    service_manage memcached start
}

# post installation action for install process; no previous installation bitrix-env
install() {
    export BITRIX_ENV_TYPE=$BITRIX_ENV_TYPE
    configure_push
    configure_memcached
}

upgrade() {
    export BITRIX_ENV_TYPE=$BITRIX_ENV_TYPE

    # http://jabber.bx/view.php?id=113476
    if [[ ( -f /etc/ansible/hosts ) && \
        ( $(grep -v '^$\|^#' /etc/ansible/hosts | grep -c "bitrix-hosts") -gt 0 ) ]]; then
        log_to_file "Run common playbook"
        ansible-playbook /etc/ansible/common.yml \
            -e common_manage=update_push_server >> $LOGS_FILE 2>&1
        if [[ $? -gt 0 ]]; then
            log_to_file "Cannot run common-playbok" "ERROR"
        else
            log_to_file "Run common-playbook after update"
            rm -f $INVENTORY_TEMP $PLAYBOOK_OPTIONS
        fi
    fi
}

log_to_file "Start $RPM_ACTION for bitrix-env=$BITRIX_ENV_VER timestamp=$UPDATE_TM"
case $RPM_ACTION in
    install)
        install
        ;;
    upgrade)
        upgrade
        ;;
    *)
        log_to_file "Incorrect action=$RPM_ACTION"
        ;;
esac
