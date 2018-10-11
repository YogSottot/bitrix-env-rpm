#!/bin/bash
#====================================================================
# Run level information:
#
# chkconfig: 2345 99 99
# description: Bitrix Virtual Appliance Tuning & Configuration Script
# processname: bvat
export LANG=en_US.UTF-8
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

INIT_FLAG=/root/BX_INITIAL_SETUP
MYSQL_CNF=/root/.my.cnf

# upload proc
. /opt/webdir/bin/bitrix_utils.sh || exit 1

# get OS information
get_os_type
[[ $OS_TYPE -eq 0  ]] && exit 1

# get php settings
get_php_settings

# logging
LOG_DIR=/opt/webdir/logs
[[ ! -d $LOG_DIR ]] && mkdir -p $LOG_DIR
LOGS_FILE=$LOG_DIR/bvat.log
[[ -z $DEBUG ]] && DEBUG=0
if [[ -f $LOGS_FILE ]]; then
    tm=$(date +%s)
    mv -f $LOGS_FILE $LOGS_FILE.$tm
    echo -n "" > $LOGS_FILE
fi

# intial/first boot configuration script
# - set mysql root password
# - set mysql user and password for default bitrix site
bx_init(){
    # generate root password and update security options
    my_generate_rootpw

    # generate bitrix password for default site
    my_generate_sitepw

    # update crypo key
    update_crypto_key

    if [[ ( -n $BITRIX_ENV_TYPE ) && \
        ( $BITRIX_ENV_TYPE == "crm" ) ]]; then
        # generate push settings
        generate_push

        # update bitrix and root passwords
        update_bitrix_password

        # update root password
        update_root_password

        # generate pool server
        generate_ansible_inventory 0 "$BITRIX_ENV_TYPE"
    fi
}

start(){
    log_to_file "Start server configuration by Bitrix-Env" 
    log_to_file "OS info: version=$OS_VERSION type=$OS_TYPE x86_64=$IS_X86_64"

    # get system memory on board
    get_available_memory
    log_to_file "Maximum available memory=${AVAILABLE_MEMORY}KB"

    # directories that used for installation
    install_directories="/etc/mysql/conf.d /etc/httpd/bx/conf"
    for install_dir in $install_directories; do
        if [[ ! -d $install_dir ]]; then
            mkdir -p $install_dir
            log_to_file "Create direcory=$install_dir"
        fi
    done

    # create config that depends on installed RAM
    httpd_restart=$(/etc/ansible/library/bx_perf apache | grep -c '"changed":true')
    mysql_restart=$(/etc/ansible/library/bx_perf mysql | grep -c '"changed":true')

    # restart services
    if [[ $mysql_restart -gt 0 ]]; then
        get_mysql_package
        log_to_file "Update mysql service; need to restart $MYSQL_SERVICE"

        if [[ $OS_VERSION -eq 7 ]]; then
            systemctl restart $MYSQL_SERVICE >> $LOGS_FILE 2>&1
        else
            service mysqld restart >> $LOGS_FILE 2>&1
        fi
    fi

    if [[ $httpd_restart -gt 0 ]]; then
        log_to_file "Update httpd service; need to restart $MYSQL_SERVICE"

        if [[ $OS_VERSION -eq 7 ]]; then
            systemctl restart httpd >> $LOGS_FILE 2>&1
        else
            service httpd restart >> $LOGS_FILE 2>&1
        fi
    fi

    # increase max_input_vars for php 5.4 and above
    if [[ $(echo "$PHP_VERSION" | egrep -c '^(5\.[456]|7\.[0-9])$')  ]]; then
        sed -i 's/max_input_vars = 4000/max_input_vars = 10000/' \
            /etc/php.d/bitrixenv.ini
        log_to_file "Increase max_input_vars value in /etc/php.d/bitrixenv.ini"
    fi
#    if [[ $IS_OLDER_PHP -gt 0 ]]; then
#        if [[ $(grep -c "mbstring.internal_encoding" /etc/php.d/bitrixenv.ini) -gt 0 ]]; then
#            log_to_file "Found mbstring.internal_encoding at /etc/php.d/bitrixenv.ini"
#            sed -i "s/mbstring.internal_encoding/default_charset/" \
#            /etc/php.d/bitrixenv.ini && \
#                log_to_file "Replace mbstring.internal_encoding by default_charset"
#        fi
#    fi

    # configure apcu module
    if [[ ( $IS_APCU_PHP -gt 0 ) && ( -f /etc/php.d/apc.ini ) ]]; then
        sed -i 's/apc.so/apcu.so/' /etc/php.d/apc.ini
        if [[ "$PHP_VERSION" == "5.4" ]]; then
            mv -f /etc/php.d/apc.ini /etc/php.d/apcu.ini
        elif [[ "$PHP_VERSION" == "5.6" ]]; then
            mv -f /etc/php.d/apc.ini /etc/php.d/40-apcu.ini
        elif [[ "$PHP_VERSION" == "7.0" ]]; then
            mv -f /etc/php.d/apc.ini /etc/php.d/40-apcu.ini
        fi
    fi
    # apc compatibility disable
    # php-pecl-apcu     - php.d/40-apcu.ini
    # php-pecl-apcu-bc  - php.d/50-apc.ini
    if [[ -f /etc/php.d/50-apc.ini ]]; then
        : > /etc/php.d/50-apc.ini
    fi

    # configure opcache module
    if [[ $IS_OPCACHE_PHP -gt 0 ]]; then
        log_to_file "Opcache module is enabled. Start configuration."
        opcache_template=/etc/ansible/bvat_conf/opcache.ini.bx
        opcache_memory_mb=$(( $AVAILABLE_MEMORY_MB/8 ))
        [[ -z $opcache_memory_mb ]] && opcache_memory_mb=64
        [[ $opcache_memory_mb -lt 64 ]] && opcache_memory_mb=64
        [[ $opcache_memory_mb -gt 2048 ]] && opcache_memory_mb=2048

        opcache_memory_strings=$(( $opcache_memory_mb/4 ))

        opcache_config=/etc/php.d/10-opcache.ini
        [[ "$PHP_VERSION" == "5.4" ]] && opcache_config=/etc/php.d/opcache.ini

        # delete old config file; if there is one
        [[ ( "$PHP_VERSION" != "5.4" ) && \
            ( -f /etc/php.d/opcache.ini ) ]] && \
            rm -f /etc/php.d/opcache.ini

        # update opcache config
        if [[ -f $opcache_template ]]; then
            cat $opcache_template | \
                sed -e "s:__MEMORY__:$opcache_memory_mb:;s:__MEMORYSTR__:$opcache_memory_strings:;" \
                > $opcache_config 2>/dev/null && \
                log_to_file "Update opcache config=$opcache_config"
        fi
    fi


    BXFILE=/etc/php.d/bitrixenv.ini
    if [[ "$PHP_VERSION" == "5.6" ]]; then
        if [[ $( grep -cw always_populate_raw_post_data $BXFILE ) -eq 0 ]]; then
            echo "always_populate_raw_post_data = -1" >> $BXFILE
        fi
    else
        if [[ $( grep -cw always_populate_raw_post_data $BXFILE ) -gt 0 ]]; then
            sed -i "/always_populate_raw_post_data/d" $BXFILE
        fi
    fi

    # disable or enable xmpp daemon
    if [[ -f /etc/init.d/xmpp ]]; then
        if [[ $memory_mb -le 512 ]]; then
            chkconfig xmpp off
        else
            chkconfig xmpp on
        fi
    fi

    chmod 0664 /etc/php.d/*.ini
    ulimit -n 10240

    # generate root password and site user password
    if [[ -f $INIT_FLAG ]]; then 
        bx_init
        rm -f $INIT_FLAG

    fi

    # update alternatives
    bx_alternatives_for_mycnf

    # change issue message (that used in login screen)
    /opt/webdir/bin/bx_motd > /etc/issue 2>/dev/null

}


test_f(){
#    DEBUG=1
    bx_init
}

### main
action=$1
[[ -z $action ]] && action=start

case "$1" in
    start|restart|"") 
        start 
        ;;
    stop)
		# No-op
		;;
    test)
        test_f
        ;;
    *)
		echo "Error: argument '$1' not supported" >&2
		exit 3
		;;
esac

exit 0
