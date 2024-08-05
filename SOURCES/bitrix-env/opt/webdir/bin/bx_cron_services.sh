#!/usr/bin/bash
#
# start site services: xmppd, smtpd
# 
# options:
# $1 - module_name
# $2 - site_directory 
#
export LANG=en_US.UTF-8
export TERM=linux
export NOLOCALE=yes
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

PROGNAME=$0
PROGPATH=$(dirname $0)
PHPCMD=/usr/bin/php
PHPCFG=/etc/php.ini

BASE_DIR=/opt/webdir
. $PROGPATH/bitrix_utils.sh || exit 1

# logging infor to file
log_to_file() {
    _mess=$1
  
    echo "$(date +"%Y/%m/%d %H:%M:%S") $$ $_mess" >> $LOGS_FILE
    echo $_mess 1>&2
}

help_message() {
    echo "Usage: $PROGNAME xmppd|smppd [/path/to/site/directory]"
    echo "Ex."
    echo " * Start xmppd daemon for default site"
    echo "   $PROGNAME xmppd"
    echo " * Start smtpd daemon for additional site"
    echo "   $PROGNAME smtpd /home/bitrix/ext_www/site_name"
    echo
    exit 1
}

test_process() {
    process_starter=$1
    process_number=$(ps -ef | grep -v "grep\|$PROGNAME" | grep -c "$process_starter")
    echo $process_number
}

start_xmppd() {
    xmppd_script="$site_directory/bitrix/modules/xmpp/xmppd.php"
    if [[ ! -f $xmppd_script ]]; then
	echo "Not installed xmpp module on site in $site_directory"
	exit 1
    fi

    xmppd_process_number=$(test_process $xmppd_script)
    if [[ $xmppd_process_number -eq 0 ]]; then
	$PHPCMD -c $PHPCFG -f $xmppd_script >> $LOGS_FILE 2>&1
	if [[ $? -eq 0 ]]; then
	    service stunnel restart >> $LOGS_FILE 2>&1
	fi
	chown bitrix.bitrix $LOGS_FILE
    fi
}

configure_init_bx_smtpd() {
    TEMPLATE=/etc/ansible/roles/web/templates/init.d-bx_smtpd.j2
    INIT=/etc/init.d/bx_smtpd

    # create init script
    TMP_TEMPLATE=/tmp/$(basename $TEMPLATE)
    SITE_DIR_REGEXP=$(echo "$site_directory" | sed -e "s:/:\\\/:g")

    # temporary file
    cp -f $TEMPLATE $TMP_TEMPLATE
    sed -i "s/{{ item.DocumentRoot }}/$SITE_DIR_REGEXP/" $TMP_TEMPLATE

    # test replacement
    TMP_MD5=$(md5sum $TMP_TEMPLATE | awk '{print $1}')
    INIT_MD5=0
    [[ -f $INIT ]] && INIT_MD5=$(md5sum $INIT | awk '{print $1}')
    if [[ $TMP_MD5 != "$INIT_MD5" ]]; then
        cp -f $TMP_TEMPLATE $INIT
        chmod 755 $INIT
        echo "Update $INIT"
    fi
    rm -f $TMP_TEMPLATE
}

configure_systemd_bx_smtpd() {
    TEMPLATE=/etc/ansible/roles/web/templates/systemd-bx_smtpd.service.j2
    SYSTEMD=/etc/systemd/system/bx_smtpd.service

    # create systemd service
    TMP_TEMPLATE=/tmp/$(basename $TEMPLATE)
    SITE_DIR_REGEXP=$(echo "$site_directory" | sed -e "s:/:\\\/:g")

    # temporary file
    cp -f $TEMPLATE $TMP_TEMPLATE
    sed -i "s/{{ item.DocumentRoot }}/$SITE_DIR_REGEXP/" $TMP_TEMPLATE

    # test replacement
    TMP_MD5=$(md5sum $TMP_TEMPLATE | awk '{print $1}')
    INIT_MD5=0
    [[ -f $SYSTEMD ]] && INIT_MD5=$(md5sum $SYSTEMD | awk '{print $1}')
    if [[ $TMP_MD5 != "$INIT_MD5" ]]; then
        cp -f $TMP_TEMPLATE $SYSTEMD
        systemctl daemon-reload
        echo "Update $SYSTEMD"
    fi
    rm -f $TMP_TEMPLATE

    # enable systemd
    if [[ $(systemctl is-active bx_smtpd | grep -wc active) -eq 0 ]]; then
        systemctl enable bx_smtpd
        systemctl start bx_smtpd
    fi
}

configure_capabilities() {
    PHP=$(which php)
    [[ -z $PHP ]] && return 1

    setcap CAP_NET_BIND_SERVICE=ep $PHP
}

configure_smtpd_centos7() {
    configure_capabilities
    configure_init_bx_smtpd
    configure_systemd_bx_smtpd
}

# VMBITRIX_9.0
configure_smtpd_centos9() {
    configure_capabilities
    configure_init_bx_smtpd
    configure_systemd_bx_smtpd
}

start_smtpd() {
    get_os_type

    smtpd_script="$site_directory/bitrix/modules/mail/smtpd.php"
    if [[ ! -f $smtpd_script ]]; then
        echo "Not installed smtpd module on site in $site_directory"
        exit 1
    fi

    smtpd_process_number=$(test_process $smtpd_script)
    if [[ $smtpd_process_number -eq 0 ]]; then
        if [[ $OS_VERSION -eq 6 ]]; then
            su - bitrix -c "authbind $PHPCMD -c $PHPCFG -f $smtpd_script >> $LOGS_FILE 2>&1"
        fi
        if [[ $OS_VERSION -eq 7 ]]; then
            configure_smtpd_centos7
        fi
        # VMBITRIX_9.0
        if [[ $OS_VERSION -eq 9 ]]; then
            configure_smtpd_centos9
        fi
    fi
}

# test options
module_name=$1
site_directory=$2
[[ ( -z "$module_name" ) || ( -z $site_directory ) ]] && help_message
if [[ ! -d $site_directory ]]; then
    echo "error: Not exist site directory $site_directory"
    exit 1
fi
site_directory=$(echo $site_directory | sed -e 's:/$::')

# log file /home/bitrix/ext_www/site_name/bitrix/modules/xmppd.log
LOGS_FILE=$site_directory/bitrix/modules/$module_name.log

case $module_name in
    'xmppd')  start_xmppd ;;
    'smtpd')  start_smtpd ;;
    *)        help_message ;;
esac
