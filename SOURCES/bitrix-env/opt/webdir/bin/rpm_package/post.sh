#!/bin/bash
# post installation script for bitrix-env
# 1. create bitrix user
# 2. configure mysql/mariadb service
#set -x
export LANG=en_US.UTF-8
export NOLOCALE=yes
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

RPM_ACTION="${1:-undefined}"
BITRIX_ENV_VER="${2}"
BITRIX_ENV_TYPE=${3:-general}

OS_VERSION=$(cat /etc/redhat-release | \
    sed -e "s/CentOS Linux release//;s/CentOS release // " | cut -d'.' -f1 | \
    sed -e "s/\s\+//g")
UPDATE_TM=$(date +'%Y%m%d%H%M')
PHP_VERSION=$(php -v | grep ^PHP | awk '{print $2}' | awk -F'.' '{print $1}')
PHP_VERSION_MID=$(php -v | grep ^PHP | awk '{print $2}' | awk -F'.' '{print $2}')
NGINX_VERSION=$(nginx -v 2>&1 | grep "^nginx version" | awk -F'/' '{print $2}')
MYSQL_CNF=/root/.my.cnf
MYSQL_USER_BASE=bitrix

# configure logging
LOG_DIR=/opt/webdir/logs
[ ! -d $LOG_DIR  ] && mkdir -p $LOG_DIR
LOGS_FILE=$LOG_DIR/${RPM_ACTION}-${BITRIX_ENV_VER}.log
[[ -z $DEBUG ]] && DEBUG=0

log_to_file(){
  log_message="${1}"
  notice="${2:-INFO}"
  printf "%20s: %5s [%s] %s\n" \
      "$(date +"%Y/%m/%d %H:%M:%S")" $$ "$notice" "$log_message" >> $LOGS_FILE
  [[ $DEBUG -gt 0 ]] && \
    printf "%20s: %5s [%s] %s\n" \
      "$(date +"%Y/%m/%d %H:%M:%S")" $$ "$notice" "$log_message" 1>&2

  return 0
}

# generate random password
randpw(){
    local len="${1:-20}"
    if [[ $DEBUG -eq 0 ]]; then
        </dev/urandom tr -dc '?!@&\-_+@%\(\)\{\}\[\]=0-9a-zA-Z' | head -c20; echo ""
    else
        </dev/urandom tr -dc '?!@&\-_+@%\(\)\{\}\[\]=' | head -c20; echo ""
    fi

}

# copy-paste from mysql_secure_installation; you can find explanation in that script
basic_single_escape () {
    echo "$1" | sed 's/\(['"'"'\]\)/\\\1/g'
}

# generate client mysql config
my_config(){
    local cfg="${1:-$MYSQL_CNF}"
    echo "# mysql bvat config file" > $cfg
    echo "[client]" >> $cfg
    echo "user=root" >> $cfg
    local esc_pass=$(basic_single_escape "$MYSQL_ROOTPW")
    echo "password='$esc_pass'" >> $cfg
    echo "socket=/var/lib/mysqld/mysqld.sock" >> $cfg
}

# run query
my_query(){
    local query="${1}"
    local cfg="${2:-$MYSQL_CNF}"
    local opts="${3}"

    [[ -z $query ]] && return 1

    local tmp_f=$(mktemp /tmp/XXXXX_command)
    echo "$query" > $tmp_f
    mysql --defaults-file=$cfg $opts < $tmp_f >> $LOGS_FILE 2>&1
    mysql_rtn=$?

    rm -f $tmp_f
    return $mysql_rtn
}

# query and result
my_select(){
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

update_site_settings(){
    local path=${1:-/home/bitrix/www/bitrix/.settings.php}
    tmp_path=$path.tmp

    [[ -z $BX_PASSWORD ]] && return 2
    [[ -z $BX_USER ]] && return 2

    [[ ! -f $path ]] && return 1 
    #cp -f $path $path.bak
    log_to_file "Start updating path=$path"

    #  'login' => '__LOGIN__',
    #  'password' => '__PASSWORD__',
    login_line=$(grep -n "'login'" $path | awk -F':' '{print $1}')
    if [[ -z $login_line ]]; then
        log_to_file "Cannot find password option in $path"
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
    log_to_file "Update login and password options in file=$path"

}
update_site_dbconn(){
    local path=${1:-/home/bitrix/www/bitrix/php_interface/dbconn.php}
    tmp_path=$path.tmp

    [[ -z $BX_PASSWORD ]] && return 2
    [[ -z $BX_USER ]] && return 2

    [[ ! -f $path ]] && return 1 
    #cp -f $path $path.bak
    log_to_file "Start updating path=$path"
    login_line=$(grep -n "DBLogin" $path | awk -F':' '{print $1}')
    if [[ -z $login_line ]]; then
        log_to_file "Cannot find password option in $path"
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
    log_to_file "Update login and password options in file=$path"
}


# create mysql account and database for default site
# MYSQL_USER_BASE
create_site_mysql_data(){

    # get mysqld service status
    service_mysql status
    [[ $? -gt 0 ]] && service_mysql start

    # generate DB name
    db_id=0
    db_name=sitemanager
    BX_DB=
    db_limit=20
    while [[ ( -z "$BX_DB" ) && ( $db_limit -gt 0 ) ]]; do

        test_db="$db_name"
        [[ $db_id -gt 0 ]] && \
            test_db="${db_name}${db_id}"

        [[ ! -d $MYSQL_BASE_DIR/$test_db ]] && \
            BX_DB=$test_db

        db_id=$(( $db_id + 1 ))
        db_limit=$(( $db_limit - 1 ))
    done
    if [[ -z $BX_DB ]]; then
        log_to_file "Cannot autogenerate name for bitrix DB"
        exit 1
    fi

    # generate user name
    user_id=0
    user_tmp=$(mktemp /tmp/XXXXXX_user)
    BX_USER=
    BX_PASSWORD=

    # choose user name
    test_limits=20
    while [[ ( -z $BX_USER ) && ( $test_limits -gt 0 ) ]]; do
        test_user="${MYSQL_USER_BASE}${user_id}"

        log_to_file "Checking the user's existence: $test_user"
        my_select "SELECT User FROM mysql.user WHERE User='$test_user'" > $user_tmp 2>&1
        if [[ $? -gt 0 ]]; then
            log_to_file "Request to the mysql service return error: "
            cat $user_tmp >> $LOGS_FILE
            rm -f $user_tmp
            exit
        fi
        # if temporary file contains username than request return value and user exists
        is_user=$(cat $user_tmp | grep -wc "$test_user")

        [[ $is_user -eq 0 ]] && \
            BX_USER="$test_user"

        user_id=$(( $user_id + 1 ))
        test_limits=$(( $test_limits - 1 ))
    done

    if [[ -z $BX_USER ]]; then
        log_to_file "Cannot autogenerate user name. Exit"
        rm -f $user_tmp
        exit
    fi
    log_to_file "Generate user name=$BX_USER for default site"

    # create user
    BX_PASSWORD=$(randpw)
    esc_db_password=$(basic_single_escape $BX_PASSWORD)
    my_query "CREATE USER '$BX_USER'@'localhost' IDENTIFIED BY '$esc_db_password';" > $user_tmp 2>&1
    if [[ $? -gt 0 ]]; then
        log_to_file "Cannot create $BX_USER"
        cat $user_tmp >> $LOGS_FILE
        rm -f $user_tmp
        exit 1
    fi
    #log_to_file "Create mysql user=$BX_USER password=$BX_PASSWORD"
    log_to_file "Create mysql user=$BX_USER"

    # grant access
    my_query "GRANT ALL PRIVILEGES ON $BX_DB.* TO '$BX_USER'@'localhost';" >$user_tmp 2>&1
    if [[ $? -gt 0 ]]; then
        log_to_file "Cannot grant access rights to user=$BX_USER to db=$BX_DB"
        cat $user_tmp >> $LOGS_FILE
        rm -f $user_tmp
        exit 1
    fi
    log_to_file "Grant access rights to user=$BX_USER to db=$BX_DB"

    # create database
    mysql_create_file=/root/.bitrix.sql
    echo "create database $BX_DB character set 'utf8' collate utf8_unicode_ci;" \
        > $mysql_create_file
    mysql --defaults-file="$MYSQL_CNF" < $mysql_create_file 1>>$LOGS_FILE 2>&1
    if [[ $? -gt 0 ]]; then
        log_to_file "Cannot create DB=$BX_DB"
        rm -f $user_tmp
        exit
    fi
    log_to_file "DB $BX_DB is created"
    rm -f $mysql_create_file $user_tmp


}
# Centos7:
# mysql-community-server => mysql-community
# Percona-Server-server  => percona
# MariaDB-server         => MariaDB
# mariadb-server         => mariadb
# Centos6:
# mysql-server           => mysql
package_mysql(){
    # one-time call
    [[ -n $MYSQL_PACKAGE ]] && return 0

    PACKAGES_LIST=$(rpm -qa)
    if [[ $(echo "$PACKAGES_LIST" | grep -c '^mysql-community-server') -gt 0 ]]; then
        MYSQL_PACKAGE=mysql-community-server
        MYSQL_SERVICE=mysqld
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mysqld.service
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^Percona-Server-server') -gt 0 ]]; then
        MYSQL_PACKAGE=Percona-Server-server
        MYSQL_SERVICE=mysqld
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mysqld.service

    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^MariaDB-server') -gt 0 ]]; then
        MYSQL_PACKAGE=MariaDB-server
        MYSQL_SERVICE=mariadb
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mariadb.service

    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^mariadb-server') -gt 0 ]]; then
        MYSQL_PACKAGE=mariadb-server
        MYSQL_SERVICE=mariadb
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mariadb.service
    elif [[ $(echo "$PACKAGES_LIST" | grep -c '^mysql-server') -gt 0 ]]; then
        MYSQL_PACKAGE=mysql-server
        MYSQL_SERVICE=mysqld
        MYSQL_SYSTEMD=/usr/lib/systemd/system/mysql.service
    else
        log_to_file "Cannot define mysql-server package" "ERROR"
        return 1
    fi
    MYSQL_VERSION=$(rpm -qa --queryformat '%{version}' ${MYSQL_PACKAGE}* | \
        head -1 | awk -F'.' '{printf "%d.%d", $1,$2}' )
    MYSQL_MID_VERSION=$(echo "$MYSQL_VERSION" | awk -F'.' '{print $2}')

    log_to_file "Found package for mysql-server=$MYSQL_PACKAGE version=$MYSQL_VERSION"
}

# shell fro mysql start/restart/stop operations
service_mysql(){
    local action="${1}"
    local restart_rtn=0
    [[ -z $action ]] && return 1
    package_mysql || exit 1

    if [[ $OS_VERSION -eq 7 ]]; then
        if [[ "$action" == "status" ]]; then
            systemctl is-active $MYSQL_SERVICE >/dev/null 2>&1
            return $?
        elif [[ $action == "enable" ]]; then
            systemctl enable $MYSQL_SERVICE >> $LOGS_FILE 2>&1
            restart_rtn=$?
        else
            systemctl $action $MYSQL_SERVICE >> $LOGS_FILE 2>&1
            restart_rtn=$?
       fi
    else
        if [[ $action == "status" ]]; then
            /etc/init.d/mysqld status | grep -wc running >/dev/null 2>&1
            return $?
        elif [[ "$action" == "enable" ]]; then
            chkconfig mysqld on >/dev/null 2>&1
        else
            service mysqld $action >> $LOGS_FILE 2>&1
            restart_rtn=$?
        fi
    fi

    if [[ $restart_rtn -gt 0 ]]; then
        log_to_file "Cannot $action for mysqld service" "ERROR"
        exit 1
    else
        log_to_file "Service $MYSQL_SERVICE is \"${action}ed\""
    fi
}

service_web(){
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

# temporary password for mysql
# goal - create MYSQL_CNF which can be used by procedure of site creation
create_mysql_config() {
    MYSQL_LOG_FILE=${1:-/var/log/mysqld.log}
    MYSQL_BX_LOG_FILE=${2:-/var/log/mysql/error.log}
    log_to_file "Processing log file=$MYSQL_LOG_FILE mysql_version=$MYSQL_MID_VERSION"

    MYSQL_TMP_FILE=$(mktemp /tmp/XXXXXX_mysql)
    if [[ $MYSQL_MID_VERSION -eq 7 ]]; then

        if [[ -s $MYSQL_LOG_FILE ]]; then
            MYSQL_ROOTPW=$(grep 'temporary password' $MYSQL_LOG_FILE | awk '{print $NF}')
            log_to_file "Found mysql log=$MYSQL_LOG_FILE"
            cat $MYSQL_LOG_FILE >> $LOGS_FILE
        fi

        if [[ ( -s $MYSQL_BX_LOG_FILE ) && ( -z $MYSQL_ROOTPW ) ]]; then
            MYSQL_ROOTPW=$(grep 'temporary password' $MYSQL_BX_LOG_FILE | awk '{print $NF}')
            log_to_file "Found mysql log=$MYSQL_BX_LOG_FILE"
            cat $MYSQL_BX_LOG_FILE >> $LOGS_FILE
        fi


        # generate own temporary password :)
        if [[ ! -f $MYSQL_CNF ]]; then

            if [[ -n $MYSQL_ROOTPW ]]; then
                my_config
                my_select "status;" > $MYSQL_TMP_FILE 2>&1
                if [[ $? -gt 0 ]]; then
                    if [[ $( grep -c "connect-expired-password" $MYSQL_TMP_FILE ) -gt 0 ]]; then
                        NEWPW="$(randpw)"
                        esc_pass=$(basic_single_escape "${NEWPW}")
                        my_query "ALTER USER 'root'@'localhost' IDENTIFIED BY '$esc_pass';" \
                            $MYSQL_CNF --connect-expired-password
                        if [[ $? -gt 0 ]]; then
                            log_to_file "Cannot change temporary root password"
                            rm -f $MYSQL_TMP_FILE
                            exit 1
                        else
                            log_to_file "Change root password for mysql"
                            MYSQL_ROOTPW="${NEWPW}"
                            my_config
                            log_to_file "Create mysql config file=$MYSQL_CNF"
                        fi
                    else
                        log_to_file "Connect to mysql service return error: "
                        cat $MYSQL_TMP_FILE >> $LOGS_FILE
                        rm -f $MYSQL_TMP_FILE
                        exit 1
                    fi
                fi
            else
                log_to_file "Cannot find temporary root password; not found $MYSQL_CNF. Exit"
                rm -f $MYSQL_TMP_FILE
                exit 1
            fi
        fi
    else
        if [[ ! -f $MYSQL_CNF ]]; then
            MYSQL_ROOTPW=""
            my_config
        fi
    fi
    my_select "status;" > $MYSQL_TMP_FILE 2>&1
    if [[ $? -gt 0 ]]; then
        log_to_file "Cannot connect to mysql with config file=$MYSQL_CNF. Exit"
        cat $MYSQL_TMP_FILE >> $LOGS_FILE
        exit 1
    fi

    rm -f $MYSQL_TMP_FILE
}

# configure mysql service
install_mysql(){
    local dir=

    IS_UPDATE_MYSQL_CONFIG=0                            # do script replace main mysql config or not
    package_mysql || exit 1


    # create socket and include directories
    for dir in $MYSQL_INCLUDE_DIR $MYSQL_SOCKET_DIR; do
        if [[ ! -d $dir ]]; then
            mkdir -p $dir
            chown -R mysql:mysql $dir
            log_to_file "Directory=$dir was created"
        fi
    done

    if [[ $OS_VERSION -eq 7 ]]; then

        # create systemd settings for mariadb for Centos7
        if [[ $MYSQL_SERVICE == "mariadb" ]]; then
            MYSQL_SYSTEMD_DIR=/etc/systemd/system/mariadb.service.d
            [[ ! -d $MYSQL_SYSTEMD_DIR ]] && \
                mkdir -p $MYSQL_SYSTEMD_DIR
            echo -e "[Install]\nAlias=mysql.service mysqld.service" > $MYSQL_SYSTEMD_DIR/custom.conf
            log_to_file "Create Alias settings for mariadb..service"

            ln -sf /usr/lib/systemd/system/mariadb.service /etc/systemd/system/mysql.service
            ln -sf /usr/lib/systemd/system/mariadb.service /etc/systemd/system/mysqld.service
            log_to_file "Create mysql(d) services for compatibility"
        fi

        echo "d /var/run/mysqld 0755 mysql mysql -" > /etc/tmpfiles.d/$MYSQL_SERVICE.conf
        systemd-tmpfiles --create /etc/tmpfiles.d/$MYSQL_SERVICE.conf
        log_to_file "Create configuration for $MYSQL_SERVICE pid file"

        systemctl daemon-reload
    fi

    if [[ $OS_VERSION -eq 7 ]]; then
        if [[ ( $MYSQL_PACKAGE == "MariaDB-server" ) && \
            ( ! -f $MYSQL_SYSTEMD ) ]]; then
            tee $MYSQL_SYSTEMD << EOF
[Unit]
Description=MariaDB database server
After=syslog.target
After=network.target

[Service]
Type=forking
User=mysql
Group=mysql

ExecStart=/etc/init.d/mysql start
ExecStop=/etc/init.d/mysql stop

TimeoutSec=300

PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
        fi
    fi

    if [[ $OS_VERSION -eq 6 ]]; then
        if [[ ( $MYSQL_PACKAGE == "Percona-Server-server" ) && \
            ( ! -f /etc/init.d/mysqld ) ]]; then
            ln -sf /etc/init.d/mysql /etc/init.d/mysqld
            log_to_file "Create init.d script mysqld"
        fi
    fi


    # create base configs
    MYSQL_MAIN_RPM_CFG=${MYSQL_MAIN_CFG}.bx             # cnf.bx config to avoid conflicts with mysql/mariadb rpm
    [[ $MYSQL_MID_VERSION -eq 6 ]] && \
        MYSQL_MAIN_RPM_CFG=${MYSQL_MAIN_CFG}.bx_mysql56
    [[ $MYSQL_MID_VERSION -eq 7 ]] && \
        MYSQL_MAIN_RPM_CFG=${MYSQL_MAIN_CFG}.bx_mysql57
 
    log_to_file "MYSQL_MAIN_RPM_CFG=$MYSQL_MAIN_RPM_CFG"

    MYSQL_MAIN_BKP_CFG=${MYSQL_MAIN_CFG}.ori.$UPDATE_TM
    if [[ -f $MYSQL_MAIN_CFG ]]; then
        # don't update config updated by ansible
        IS_ANSIBLE_CFG=$(grep -c ' Ansible managed ' $MYSQL_MAIN_CFG)
        if [[ $IS_ANSIBLE_CFG -eq 0 ]]; then
            mv -f $MYSQL_MAIN_CFG $MYSQL_MAIN_BKP_CFG
            mv -f $MYSQL_MAIN_RPM_CFG $MYSQL_MAIN_CFG
            IS_UPDATE_MYSQL_CONFIG=1
            log_to_file "Config=$MYSQL_MAIN_CFG was updated by $MYSQL_MAIN_RPM_CFG"
        fi
    else
        mv -f $MYSQL_MAIN_RPM_CFG $MYSQL_MAIN_CFG
        IS_UPDATE_MYSQL_CONFIG=1
        log_to_file "Config=$MYSQL_MAIN_CFG was created"
    fi
    [[ -f ${MYSQL_MAIN_CFG}.bx ]] && rm -f ${MYSQL_MAIN_CFG}.bx

    # create customer's empty file
    if [[ ! -f $MYSQL_CUSTOM_CFG ]]; then
        echo -n "" > $MYSQL_CUSTOM_CFG
        log_to_file "Config=${MYSQL_CUSTOM_CFG} was created"
    fi

    # update mysql settings
    if [[ $IS_UPDATE_MYSQL_CONFIG -gt 0 ]]; then
        log_to_file "Create default data objects in $MYSQL_BASE_DIR"

         # not found mysql database => install it
         if [[ ! -d $MYSQL_BASE_DIR/mysql ]]; then
             log_to_file "Not found $MYSQL_BASE_DIR/mysql directory; create it."

            service_mysql stop
            MYSQL_INIT_LOG=$(mktemp /tmp/MYSQL_INIT_LOG.XXXXXX)

            if [[ $MYSQL_MID_VERSION -lt 7 ]]; then
                mysql_install_db --datadir=$MYSQL_BASE_DIR \
                 --defaults-file=$MYSQL_MAIN_CFG \
                 --user=mysql >$MYSQL_INIT_LOG 2>&1
                mysql_install_db_rtn=$?
            else
                mysqld --defaults-file=$MYSQL_MAIN_CFG --initialize >$MYSQL_INIT_LOG 2>&1
                mysql_install_db_rtn=$?
            fi
            log_to_file "Initialize data in the directory=$MYSQL_BASE_DIR"

            if [[ $mysql_install_db_rtn -gt 0 ]]; then
                log_to_file "Cannot install mysql db to $MYSQL_BASE_DIR: log=$MYSQL_INIT_LOG" "ERROR"
                exit 1
            else
                cat $MYSQL_INIT_LOG >> $LOGS_FILE
            fi
            service_mysql start
            rtn=$?
            if [[ $rtn -gt 0 ]]; then
                log_to_file "Start the mysql service return error rtn_code=$?"
            fi
            service_mysql status
            rtn=$?
            if [[ $rtn -gt 0 ]]; then
                log_to_file "The mysql service is not running; rtn_code=$?"
            fi


        # restart mysql service
        else
            service_mysql stop
            # delete ib_logfiles; mysql start recreate them
            if [[ $(ls -l $MYSQL_BASE_DIR/ib_logfile{0,1} 2>/dev/null | wc -l) -gt 1 ]]; then
                mkdir -p $MYSQL_BASE_BKP_DIR
                log_to_file "Backup directory=$MYSQL_BASE_BKP_DIR is created"
                mv -f $MYSQL_BASE_DIR/ib_logfile{0,1} $MYSQL_BASE_BKP_DIR/
                log_to_file "Files=$MYSQL_BASE_DIR/ib_logfile{0,1} are deleted"
            fi
            service_mysql start
        fi
    fi

    # create root config file
    create_mysql_config $MYSQL_INIT_LOG
}

# create DB  for default site
# create DB user and use his credentials in site's configs
# create sites directories
create_site_settings(){

    package_mysql || exit 1

    # determine whether there is a site by its DocumentRoot
    if [[ ! -d $SITE_DIR ]]; then
        # create mysql settings
        create_site_mysql_data

        # create default directories
        mkdir -p $SITE_DIR && \
            log_to_file "Directory=$SITE_DIR is created"
        pushd $SITE_DIR > /dev/null 2>&1
        tar xzf /etc/ansible/roles/web/files/vm_kernel.tar.gz && \
            log_to_file "Unpack source for kernel instance to $SITE_DIR"
        # CRM
        if [[ $BITRIX_ENV_TYPE == "crm" ]]; then
            log_to_file "Create settings from CRM files"
            mv -f ./bitrix/.settings.php.crm ./bitrix/.settings.php
            mv -f ./bitrix/php_interface/dbconn.php.crm ./bitrix/php_interface/dbconn.php
        else
            log_to_file "Create settings from general files"
            rm -f ./bitrix/.settings.php.crm
            rm -f ./bitrix/php_interface/dbconn.php.crm
        fi
        rm -f vm_kernel.tar.gz
        popd >/dev/null 2>&1

        # update config files
        #set -x
        DBCONN_CFG=$SITE_DIR/bitrix/php_interface/dbconn.php
        SETTINGS_CFG=$SITE_DIR/bitrix/.settings.php
        update_site_settings $SETTINGS_CFG
        update_site_dbconn $DBCONN_CFG
 

        # update access rights for document root
        find $SITE_DIR -type f -exec chmod 0660 '{}' ';'
        find $SITE_DIR -type d -exec chmod 0770 '{}' ';'
        chown -R bitrix:bitrix $SITE_DIR
        log_to_file "Update access rights for directory=$SITE_DIR"

        # create additional directories
        [[ ! -d $PHP_LOGS_DIR ]] && mkdir -p $PHP_LOGS_DIR
        for d in $PHP_UPLD_DIR $PHP_SESS_DIR; do
            [[ ! -d $d/www ]] && mkdir -p $d/www
            [[ ! -d $d/ext_www ]] && mkdir -p $d/ext_www
            log_to_file "Create directories in $d"
        done

        for d in $PHP_LOGS_DIR $PHP_SESS_DIR $PHP_UPLD_DIR; do
            chown -R bitrix:bitrix $d
            find $d -type d -exec chmod 0770 '{}' ';'
            log_to_file "Update access rights for directory=$d"
        done

        # create record for systemd-tmpfiles
        if [[ $OS_VERSION -eq 7 ]]; then
            BVAT_TMPF_CONF=/etc/tmpfiles.d/bvat.conf
            BVAT_TMPF_TEMP=$(mktemp /tmp/bvat.conf.XXXXXX)

            for dir in $PHP_SESS_DIR $PHP_UPLD_DIR; do
                echo "d $dir 0770 bitrix bitrix -" >> $BVAT_TMPF_TEMP
                for sdir in www ext_www; do
                    echo "d $dir/$sdir 0770 bitrix bitrix -" >> $BVAT_TMPF_TEMP
                done
            done
            BVAT_TMPF_CONF_MD5=
            if [[ -f $BVAT_TMPF_CONF ]]; then
                BVAT_TMPF_CONF_MD5=$(md5sum $BVAT_TMPF_CONF | awk '{print $1}')
            fi
            BVAT_TMPF_TEMP_MD5=$(md5sum $BVAT_TMPF_TEMP | awk '{print $1}')
            if [[ $BVAT_TMPF_TEMP_MD5 != "$BVAT_TMPF_CONF_MD5" ]]; then
                mv -f $BVAT_TMPF_TEMP $BVAT_TMPF_CONF
                log_to_file "Update $BVAT_TMPF_CONF config"
                systemd-tmpfiles --create
            fi
            [[ -f $BVAT_TMPF_TEMP ]] && rm -f $BVAT_TMPF_TEMP
        fi
    fi
}

replace_conf_by_bx(){
    local dir="${1}"
    local list="${2}"

    [[ -z $dir  ]] && return 1
    [[ -z $list ]] && return 0

    local conf=
    local conf_fn=      # config full path
    local conf_sb=      # config sub directory in main dir

    for conf in $list; do
        conf_fn="$dir/$conf"
        conf_sb=$(dirname $conf_fn)

        # create sub directory
        [[ ! -d $conf_sb ]] && mkdir -p $conf_sb

        # backup existen config
        [[ -f $conf_fn ]] && mv -f $conf_fn $conf_fn.ori.$UPDATE_TM

        # replace config
        conf_sf=$conf_fn.bx
        if [[ $OS_VERSION -eq 7 ]]; then
            [[ -f $conf_fn.bx_centos7 ]] && conf_sf=$conf_fn.bx_centos7
        fi
        mv -f $conf_sf $conf_fn
        chown bitrix:bitrix $conf_fn
        log_to_file "Update file=$conf_fn by $conf_sf"
    done
}

purge_confs(){
    local dir="${1}"
    local list="${2}"

    [[ -z $dir  ]] && return 1
    [[ -z $list ]] && return 0

    local conf=
    local conf_fn=

    for conf in $list; do
        conf_fn="$dir/$conf"
        if [[ -s $conf_fn ]]; then
            cp -f $conf_fn $conf_fn.disabled
            echo -n > $conf_fn
            log_to_file "Purge content of file=$conf_fn; backup=$conf_fn.disabled"
        fi
    done
}

configure_httpd_scale(){
    [[ $OS_VERSION -ne 7 ]] && return 0

    HTTPD_SCALE_DIR=/etc/httpd/bx-scale
    HTTPD_MAIN_DIR=/etc/httpd/bx
    [[ ! -d $HTTPD_SCALE_DIR ]] && mkdir -p $HTTPD_SCALE_DIR

    rsync -a $HTTPD_MAIN_DIR/conf/ $HTTPD_SCALE_DIR/conf/ >/dev/null 2>&1
    if [[ $? -gt 0 ]]; then
        log_to_file "Cannot sync files from  $HTTPD_MAIN_DIR/conf/ to $HTTPD_SCALE_DIR/conf/"
        return 1
    else
        log_to_file "Sync files from  $HTTPD_MAIN_DIR/conf/ to $HTTPD_SCALE_DIR/conf/"
    fi
    SCALE_FILES=$(find $HTTPD_SCALE_DIR/conf/ -type f -name "*.conf")

    for file in $SCALE_FILES; do
        if [[ $(cat $file | grep -c "create virtual hosts for NTLM") -gt 0  ]]; then
            rm -f $file
            log_to_file "Remove file $file from httpd-scale"
            continue
        fi
        sed -i "s/127.0.0.1:[0-9]\+/127.0.0.1:9887/g" $file
        sed -i "/Listen 127.0.0.1:[0-9]\+/d" $file
        
        if [[ $(basename $file | grep "^bx_ext" -c ) -gt 0 ]]; then
            new_file=$(echo "$file" | sed -e "s/bx_ext_/ext_/")
            mv -f $file $new_file
            log_to_file "Rename file $file to $new_file"
        fi
        log_to_file "Convert file $file to httpd-scale"
    done

    echo "<IfModule mpm_prefork_module>
  StartServers        4
  MinSpareServers     4
  MaxSpareServers     4
  MaxRequestWorkers   4
  MaxRequestsPerChild 5000
</IfModule>" > $HTTPD_SCALE_DIR/conf/prefork.conf
    log_to_file "Update file=$HTTPD_SCALE_DIR/conf/prefork.conf"


    echo "# bitrix-env
SetEnv BITRIX_VA_VER $BITRIX_ENV_VER
SetEnv BITRIX_ENV_TYPE $BITRIX_ENV_TYPE
SetEnv AUTHBIND_UNAVAILABLE yes" > $HTTPD_SCALE_DIR/conf/00-environment.conf
    log_to_file "Update file=$HTTPD_SCALE_DIR/conf/00-environment.conf"

    if [[ ! -f /etc/sysconfig/httpd-scale ]] ; then
        cp -f $HTTPD_SCALE_DIR/httpd-scale /etc/sysconfig/httpd-scale && \
            log_to_file "Copy $HTTPD_SCALE_DIR/httpd-scale to /etc/sysconfig/httpd-scale"
    fi

    if [[ ! -f /etc/systemd/system/httpd-scale.service ]]; then
        cp -f $HTTPD_SCALE_DIR/httpd-scale.service \
            /etc/systemd/system/httpd-scale.service && \
            log_to_file "Create httpd-scale.service service"
    fi

    if [[ ! -f /etc/cron.d/bx_httpd-scale ]]; then
        echo "* * * * * root /opt/webdir/bin/restart_httpd-scale.sh process" \
            > /etc/cron.d/bx_httpd-scale
        log_to_file "Create cron task for httpd-scale"
    fi

    mv -f $HTTPD_SCALE_DIR/httpd-scale.conf \
        /etc/httpd/conf/httpd-scale.conf && \
    log_to_file "Update file=/etc/httpd/conf/httpd-scale.conf"

    systemctl daemon-reload
    systemctl enable httpd-scale
    systemctl restart httpd-scale
}



configure_httpd(){
    # update files
    replace_conf_by_bx "$HTTPD_CONF_DIR" "$HTTPD_CONF_LIST"

    # purge content for config files from other package
    purge_confs "$HTTPD_CONF_DIR" "$HTTPD_CONF_LIST_PURGE"

    # update MIME types for OpenOffice formats
    HTTPD_OO_PREFIX="application/vnd.openxmlformats-officedocument"
    HTTPD_OO_MIMES_LIST="wordprocessingml.document=docx
presentationml.presentation=pptx
spreadsheetml.sheet=xlsx"
    HTTPD_EXT_MIMES="application/x-rar-compressed=rar
image/x-coreldraw=cdr"
    HTTPD_MIME_CONF=/etc/mime.types
    for def in $HTTPD_OO_MIMES_LIST; do
        mime=$(echo "$def" | awk -F'=' '{print $1}')
        ext=$(echo "$def"  | awk -F'=' '{print $2}')

        # update settings
        if_exist=$(grep -c "$HTTPD_OO_PREFIX\.$mime\s\+$ext" $HTTPD_MIME_CONF)
        if [[ $if_exist -eq 0 ]]; then
            echo -e "$HTTPD_OO_PREFIX.$mime\t$ext" >> $HTTPD_MIME_CONF
            log_to_file "Add settings \`$mime $ext\` to $HTTPD_MIME_CONF"
        fi
    done

    for def in $HTTPD_EXT_MIMES; do
        mime=$(echo "$def" | awk -F'=' '{print $1}')
        ext=$(echo "$def"  | awk -F'=' '{print $2}')

        # update settings
        if_exist=$(grep -c "$mime\s\+$ext" $HTTPD_MIME_CONF)
        if [[ $if_exist -eq 0 ]]; then
            echo -e "$mime\t$ext" >> $HTTPD_MIME_CONF
            log_to_file "Add settings \`$mime $ext\` to $HTTPD_MIME_CONF"
        fi
    done

 
    if [[ $OS_VERSION -eq 7 ]]; then
        # disable PrivateTmp for httpd service
        HTTPD_SERVICE_CUSTOM_DIR=/etc/systemd/system/httpd.service.d
        HTTPD_SERVICE_CUSTOM_FILE=$HTTPD_SERVICE_CUSTOM_DIR/custom.conf
        [[ ! -d $HTTPD_SERVICE_CUSTOM_DIR ]] && mkdir -p $HTTPD_SERVICE_CUSTOM_DIR
        echo -e "[Service]\nPrivateTmp=false\nLimitSTACK=infinity" > $HTTPD_SERVICE_CUSTOM_FILE.tmp
        HTTPD_REPLACE_CONFIG=0
        HTTPD_RELOAD_SERVICE=0
        if [[ -f $HTTPD_SERVICE_CUSTOM_FILE ]]; then
            MD5_HTTPD_SERVICE_CUSTOM_FILE=$(md5sum $HTTPD_SERVICE_CUSTOM_FILE | awk '{print $1}')
            MD5_HTTPD_SERVICE_CUSTOM_TEMP=$(md5sum $HTTPD_SERVICE_CUSTOM_FILE.tmp | awk '{print $1}')
            [[ $MD5_HTTPD_SERVICE_CUSTOM_FILE != "$MD5_HTTPD_SERVICE_CUSTOM_TEMP" ]] && \
                HTTPD_REPLACE_CONFIG=1
        else
            HTTPD_REPLACE_CONFIG=1
        fi

        if [[ $HTTPD_REPLACE_CONFIG -gt 0 ]]; then
            mv -f $HTTPD_SERVICE_CUSTOM_FILE.tmp $HTTPD_SERVICE_CUSTOM_FILE
            log_to_file "Recreate $HTTPD_SERVICE_CUSTOM_FILE config file"
            HTTPD_RELOAD_SERVICE=1
        fi
        # disable additional modules for apache service (webdav, lua and etc.)
        HTTPD_MODULES_DIR=/etc/httpd/conf.modules.d
        if [[ -n "$HTTPD_TMODULES_LIST" ]]; then
            for mod in $HTTPD_TMODULES_LIST; do
                mod_file=$(find $HTTPD_MODULES_DIR -type f -name "*-$mod.conf")
                if [[ -s "$mod_file" ]]; then
                    mv -f $mod_file $mod_file.disabled
                    touch $mod_file
                    HTTPD_RELOAD_SERVICE=1
                    log_to_file "Disable apache modules=$mod in config $mod_file"
                fi
            done

            # disable negotiation_module
            [[ -f $HTTPD_MODULES_DIR/00-base.conf ]] && \
                sed -e '/negotiation_module/ s/^#*/#/' -i $HTTPD_MODULES_DIR/00-base.conf
        fi
        configure_httpd_scale

        if [[ $HTTPD_RELOAD_SERVICE -gt 0 ]]; then
            systemctl daemon-reload
            systemctl restart httpd
            log_to_file "Reload httpd service"
        fi
    fi
}

configure_nginx(){
    # update files
    replace_conf_by_bx "$NGINX_CONF_DIR" "$NGINX_CONF_LIST"

    # enable default sites
    if [[ -n $NGINX_CONF_SITES ]]; then
        NGINX_CONF_DIR_SITES=$NGINX_CONF_DIR/bx/site_enabled
        for conf in $NGINX_CONF_SITES; do
            conf_fn=$NGINX_CONF_DIR/$conf
            ln -sf $conf_fn $NGINX_CONF_DIR_SITES/
            log_to_file "Enable site config; create link from $conf_fn to $NGINX_CONF_DIR_SITES/"
        done
    fi

    # enable http_v2
    if [[ -n $NGINX_CONF_DEFAULT_SSL ]]; then
        nginx_up=$(echo $NGINX_VERSION | awk -F'.' '{print $1}')
        nginx_mid=$(echo $NGINX_VERSION | awk -F'.' '{print $2}')
        nginx_end=$(echo $NGINX_VERSION | awk -F'.' '{print $3}')
        if [[ ( $nginx_up -ge 1 ) && \
            ( ( ( $nginx_mid -ge 10 ) && ( $nginx_end -ge 2 ) ) || \
            ( $nginx_mid -ge 11 ) ) ]]; then
            sed -i 's/default_server ssl/default_server http2/g' \
                $NGINX_CONF_DIR/$NGINX_CONF_DEFAULT_SSL
        fi
    fi

    # use empty/blank conmfig for sever_monitor.conf
    if [[ -n $NGINX_CONF_LINKS ]]; then
        for def in $NGINX_CONF_LINKS; do
            to=$(echo "$def" | awk -F'=' '{print $1}')
            to_dir=$(dirname $to)
            [[ ! -d $NGINX_CONF_DIR/$to_dir ]] && \
                mkdir -p $NGINX_CONF_DIR/$to_dir && \
                log_to_file "Create directory=$NGINX_CONF_DIR/$to_dir"

            from=$(echo "$def" | awk -F'=' '{print $2}')
            if [[  -f $NGINX_CONF_DIR/$to ]]; then
                rm -f $NGINX_CONF_DIR/$to 1>/dev/null 2>&1
                log_to_file "Delete file=$NGINX_CONF_DIR/$to"
            fi
            ln -s $NGINX_CONF_DIR/$from $NGINX_CONF_DIR/$to
            log_to_file "Create link=$NGINX_CONF_DIR/$to from=$NGINX_CONF_DIR/$from"
        done
    fi

    # generate self-signed certificate for nginx
    NGINX_CONF_SSL_DIR=$NGINX_CONF_DIR/ssl
    NGINX_CONF_SSL_CRT=$NGINX_CONF_SSL_DIR/cert.pem
    if [[ ! -f $NGINX_CONF_SSL_CRT ]]; then
        # generate certificate
        [[ ! -d $NGINX_CONF_SSL_DIR ]] && mkdir -p $NGINX_CONF_SSL_DIR
        openssl req -new -x509 -days 3650 -nodes \
            -out $NGINX_CONF_SSL_CRT \
            -keyout $NGINX_CONF_SSL_CRT \
            -config $NGINX_CONF_SSL_CNF
        log_to_file "create certificate $NGINX_CONF_SSL_CRT"

        chmod 0750 $NGINX_CONF_SSL_DIR
        find $NGINX_CONF_SSL_DIR -type f -exec chmod 0640 '{}' ';'
        chown -R root:bitrix $NGINX_CONF_SSL_DIR
        log_to_file "update access rights"
    fi
    NGINX_CONF_SSL_DHP=$NGINX_CONF_SSL_DIR/dhparam.pem
    if [[ ! -f $NGINX_CONF_SSL_DHP ]]; then
        openssl dhparam -dsaparam -out $NGINX_CONF_SSL_DHP 2048
        log_to_file "create Diffie-Hellman Ephemeral Parameters"
    fi

    # install certificate to the system
    update-ca-trust force-enable
    cp -f $NGINX_CONF_SSL_CRT /etc/pki/ca-trust/source/anchors/
    update-ca-trust extract


    # configure MIME type for nginx
    NGINX_MIME_CONF=/etc/nginx/mime.types
    sed -i".$UPDATE_TM" '/^}/d' $NGINX_MIME_CONF
    sed -i '/application\/octet-stream\s\+eot/d' $NGINX_MIME_CONF
    sed -i '/application\/x-font-woff\s\+woff/d' $NGINX_MIME_CONF
    # IE fix
    sed -i".$UPDATE_TM" 's:image/x-ms-bmp:image/bmp:' $NGINX_MIME_CONF

    NGINX_MIMES_LIST="application/vnd.openxmlformats-officedocument.wordprocessingml.document=docx
application/vnd.openxmlformats-officedocument.presentationml.presentation=pptx
application/vnd.openxmlformats-officedocument.spreadsheetml.sheet=xlsx
image/jpeg=jpe
application/x-font-ttf=ttf
application/vnd.ms-fontobject=eot application/x-font-opentype=otf"

    for def in $NGINX_MIMES_LIST; do
        mime=$(echo "$def" | awk -F'=' '{print $1}')
        ext=$(echo "$def"  | awk -F'=' '{print $2}')

        # update settings
        if_exist=$(grep -c "$mime\s\+$ext" $NGINX_MIME_CONF)

        # nginx 1.14
        [[ $if_exist -eq 0 ]] && \
            if_exist=$(grep -A1  "$mime" $NGINX_MIME_CONF | \
            tail -n 1 | grep -c "$ext" )

        if [[ $if_exist -eq 0 ]]; then
            echo -e "\n$mime $ext; # bitrix-env" >> $NGINX_MIME_CONF
            log_to_file "Add settings \`$mime $ext\` to $NGINX_MIME_CONF"
        else
            log_to_file "Settings \`$,i,e $ext\` already exists in $NGINX_MIME_CONF"
        fi
    done
    echo -e "\n}" >> $NGINX_MIME_CONF

    # bitrix_scale.conf
    if [[ $OS_VERSION -eq 6 ]]; then
        : > /etc/nginx/bx/conf/bitrix_scale.conf
    fi
}

configure_php(){
    # delete sendmail option in main config
    sed -i".$UPDATE_TM" \
        '/sendmail\_path/d;/define\_syslog\_variables/d' $PHP_CONF_FILE
    log_to_file "Delete sendmail_path from $PHP_CONF_FILE"

    # disable modules
    if [[ -n "$PHP_MODULES_DISABLE" ]]; then
        for mod in $PHP_MODULES_DISABLE; do
            # php 5.4 - /etc/php.d/module.ini
            # php 5.6 - /etc/php.d/XX-module.ini
            # php 7   - /etc/php.d/XX-module.ini
            mod_f=$(find $PHP_CONF_DIR/ -name "*${mod}.ini" -type f)
            if [[ -z "$mod_f" ]]; then
                log_to_file "Not found config file for php module=$mod"
                continue
            fi

            for f in $mod_f; do
                if [[ -f $f.disabled ]]; then
                    if [[ -s $f ]]; then
                        log_to_file "Don't change settings for $mod; It looks like a user enable it in $f"
                    else
                        log_to_file "Don't change settings for $mod; It is already disabled"
                    fi
                else
                    mv -f $f $f.disabled
                    touch $f
                    log_to_file "Disable php module=$mod; Backup file=$f.disabled"
                fi
            done
        done
    fi

    # enable modules; old version doesn't work
    if [[ -n "$PHP_MODULES_ENABLE" ]]; then
        for mod in $PHP_MODULES_ENABLE; do
            mod_f=$(find $PHP_CONF_DIR/ -name "*${mod}.ini" -type f)
            if [[ -z "$mod_f" ]]; then
                log_to_file "Not found config file for php module=$mod. Create new one"
                mod_f=$PHP_CONF_DIR/$mod.ini
                [[ $PHP_VERSION -ge 6 ]] && mod_f=$PHP_CONF_DIR/99-$mod.ini
            fi

            is_mod=$(php -m 2>/dev/null | grep -wc $mod)
            if [[ $is_mod -eq 0 ]]; then
                log_to_file "Update config file for php module=$mod_f"
                echo "extension=$mod.so" > $mod_f
            fi
        done
    fi

    # update php settings for php7
    if [[ $PHP_VERSION -eq 7 ]]; then
        # site configuration
        DBCON=$SITE_DIR/bitrix/php_interface/dbconn.php
        is_use_mysqli_enabled=$(grep -v '^#' $DBCON | grep -w 'BX_USE_MYSQLI' | grep -wc true )
        if [[ $is_use_mysqli_enabled -eq 0 ]]; then
            log_to_file "Enable BX_USE_MYSQLI at $DBCON"
            sed -i '/^?>/d' $DBCON
            echo -e '\ndefine("BX_USE_MYSQLI", true);\n?>' >> $DBCON
        fi


        SETTS=$SITE_DIR/bitrix/.settings.php
        sed -i 's/MysqlConnection/MysqliConnection/g' $SETTS
        log_to_file "Enable MysqliConnection at $SETTS"

        # httpd configuration
        log_to_file "Replace libphp5 by libphp7 in httpd config"
        sed -i 's/libphp5/libphp7/g;s/php5_module/php7_module/g' /etc/httpd/bx/conf/php.conf
    fi


}

configure_stunnel(){
    STUNNEL_DIR=/etc/stunnel
    STUNNEL_CERT=$STUNNEL_DIR/stunnel.pem
    STUNNEL_CONF=$STUNNEL_DIR/stunnel.conf
    STUNNEL_INIT=/etc/init.d/stunnel
    OPENSSL_CNF=$NGINX_CONF_SSL_CNF
    [[ ! -d $STUNNEL_DIR ]] && \
        mkdir -m 750 $STUNNEL_DIR

    # generate stunnel certificate
    if [[ ! -f $STUNNEL_CERT ]]; then
        openssl req -new -x509 -days 3650 -nodes \
            -out $STUNNEL_CERT \
            -keyout $STUNNEL_CERT \
            -config $OPENSSL_CNF
        chmod 0600 $STUNNEL_CERT
        log_to_file "Cretae stunnel certificate=$STUNNEL_CERT"
    fi

    # update stunnel config and init
    for f in $STUNNEL_CONF $STUNNEL_INIT; do
        # update stunnel config
        if [[ -f $f ]]; then
            mv -f $f $f.ori.$UPDATE_TM
            log_to_file "Create backup config=$f.ori.$UPDATE_TM"
        fi

        # use rpm config file
        mv -f $f.bx $f
        log_to_file "Update config=$f"
    done
    sed  -i "s/^SEXE\=.*/SEXE\=stunnel/g;s/^sslVersion.*/;sslVersion \= all/g" $STUNNEL_INIT

    # stunnel.service is not a native service, redirecting to chkconfig
    chmod 755 $STUNNEL_INIT
    chkconfig --add stunnel
    chkconfig stunnel on
    service stunnel stop ; service stunnel start
    log_to_file "Enable stunnel service"
}

configure_bvat(){
    BVAT_INIT=/etc/init.d/bvat
    BVAT_SERVICE=/etc/systemd/system/bvat.service
    SRC_SERVICE=/etc/ansible/bvat_conf/bvat.service
    [[ $BITRIX_ENV_TYPE == "crm" ]] && \
        SRC_SERVICE=/etc/ansible/bvat_conf/bvat.service.crm
    
    # get mysql info
    package_mysql

    [[ ! -f $BVAT_INIT.bx ]] && return 1

    if [[ -f $BVAT_INIT ]]; then
        mv -f $BVAT_INIT $BVAT_INIT.ori.$UPDATE_TM
        log_to_file "Create backup file=$BVAT_INIT.ori.$UPDATE_TM"
    fi
    mv -f $BVAT_INIT.bx $BVAT_INIT
    chmod 755 $BVAT_INIT
    log_to_file "Update bvat service file"

    if [[ $OS_VERSION -eq 7 ]]; then
        cp -f $SRC_SERVICE $BVAT_SERVICE

        [[ $MYSQL_SERVICE == "mysqld" ]] && \
            sed -i 's/After=mariadb.service/After=mysqld.service/' $BVAT_SERVICE

        systemctl enable bvat
        systemctl start bvat

    else
        chkconfig --add bvat
        chkconfig bvat on
        service bvat start
    fi
}

configure_system(){
    if [[ $OS_VERSION -eq 7 ]]; then
        GETTY_DIR="/etc/systemd/system/getty@.service.d"
        [[ ! -d "$GETTY_DIR" ]] && \
            mkdir "$GETTY_DIR"
        echo "[Unit]
ConditionPathExists=!/etc/no-login-console" > "$GETTY_DIR/override.conf"
        systemctl daemon-reload
    fi
}

configure_msmtp(){
    mv -f /etc/logrotate.d/msmtp.bx /etc/logrotate.d/msmtp ;

    # update system file, if user created personal
    # usage in cron job
    if [[ -f /home/bitrix/.msmtprc ]]; then
        [[ ! -f /etc/msmtprc ]] && \
            ln -sf /home/bitrix/.msmtprc /etc/msmtprc
        log_to_file "Create msmtprc symbolic link from /home/bitrix/.msmtprc to /etc/msmtprc"
    fi
}

configure_ntp(){
    NTP_CONF=/etc/ntp.conf
    [[ ! -f $NTP_CONF ]] && return 1

    # disable tinker panic
    is_disabled=$(grep -c "tinker\s\+panic\s\+0" $NTP_CONF)
    if [[ $is_disabled -eq 0 ]]; then
        cp -f $NTP_CONF $NTP_CONF.ori.$UPDATE_TM
        echo -e "\ntinker panic 0\n" >> $NTP_CONF
    fi

    if [[ $OS_VERSION -eq 7 ]]; then
        systemctl disable chronyd.service
        systemctl enable ntpd
        systemctl restart ntpd
    else
        chkconfig --add ntpd
        chkconfig ntpd on
        service ntpd restart >/dev/null 2>&1
    fi
}

configure_crontab(){
    CRONTAB_CONF=/etc/crontab

    [[ ! -f $CRONTAB_CONF ]] && touch $CRONTAB_CONF

    # add cron_events script for default site to /etc/crontab
    # Note: default site can be deleted
    CRON_EVENTS_SCRIPT='/home/bitrix/www/bitrix/modules/main/tools/cron_events.php'
    is_cron_events=$(grep -v '^#' $CRONTAB_CONF | \
        grep -c "$CRON_EVENTS_SCRIPT")
    if [[ $is_cron_events -eq 0 ]]; then
        log_to_file "Update $CRONTAB_CONF file by bitrix cron_events script"
        echo -e \
            "\n* * * * *  bitrix test -f $CRON_EVENTS_SCRIPT && { /usr/bin/php -f $CRON_EVENTS_SCRIPT; } >/dev/null 2>&1\n" \
            >> $CRONTAB_CONF
    
    # http://jabber.bx/view.php?id=79008
    # missing ; 
    else
        is_good_cron_events=$(grep -v "^#" $CRONTAB_CONF | \
            grep -c "$CRON_EVENTS_SCRIPT\s*;\s*}") 
        if [[ $is_good_cron_events -eq 0 ]]; then
            log_to_file "Fix $CRONTAB_CONF file by bitrix cron_events script"
            sed -i "/cron_events.php/d" $CRONTAB_CONF
            echo -e \
                "\n* * * * *  bitrix test -f $CRON_EVENTS_SCRIPT && { /usr/bin/php -f $CRON_EVENTS_SCRIPT; } >/dev/null 2>&1\n" \
                >> $CRONTAB_CONF
        fi
    fi

    # delete old scripts
    BX_CHOWN_SCRIPT=/root/bitrix-env/check_bitrixenv_chown.sh
    is_bx_chown=$(grep -v '^#' $CRONTAB_CONF | \
        grep -c $BX_CHOWN_SCRIPT)
    if [[ $is_bx_chown -gt 0 ]]; then
        sed -i ":$BX_CHOWN_SCRIPT:d" $CRONTAB_CONF
    fi

}

configure_autobind(){
    AUTOBIND_DIR=/etc/authbind/byport
    AUTOBIND_FILE=$AUTOBIND_DIR/25
    [[ ! -d $AUTOBIND_DIR ]] && \
        mkdir -p $AUTOBIND_FILE

    touch $AUTOBIND_FILE && \
        chmod 500 $AUTOBIND_FILE && \
        chown bitrix $AUTOBIND_FILE
}

restart_services(){
    # mysql
    service_mysql enable
    service_mysql stop
    service_mysql start

    for srv in nginx httpd; do
        service_web $srv enable
        service_web $srv stop
        service_web $srv start
    done
}

delete_unused_bxfiles(){
    find /etc/ -type f -name "*.bx" -not -path "/etc/ansible/*" -delete
    find /etc/ -type f -name "*.bx_centos7" -not -path "/etc/ansible/*" -delete
    rm -f /etc/my.cnf.bx_mysql56 /etc/my.cnf.bx_mysql57

    rm -f /root/my.cnf
}

configure_bitrix_env_var(){
    local f=
    for f in $BITRIX_VA_VER_FILES; do
        v_export="export "
        [[ (  $(echo $f | grep -c "/sysconfig/") -gt 0 ) && ( $OS_VERSION -eq 7 ) ]] && v_export=
        if [[ ! -f $f ]]; then
            echo echo -e "#bitrix-env\n${v_export}BITRIX_VA_VER=$BITRIX_ENV_VER\n" > $f
        else
            # update version
            if [[ $(grep -v  "^#" $f | grep -wc BITRIX_VA_VER ) -gt 0 ]]; then
                
                sed -i '/BITRIX_VA_VER/d' $f
                log_to_file "Delete current record BITRIX_VA_VER in file=$f"
            fi

            # update version
            if [[ $(grep -v  "^#" $f | grep -wc BITRIX_ENV_TYPE ) -gt 0 ]]; then
                
                sed -i '/BITRIX_ENV_TYPE/d' $f
                log_to_file "Delete current record BITRIX_ENV_TYPE in file=$f"
            fi


            # set version
            echo -e "#bitrix-env\n${v_export}BITRIX_VA_VER=$BITRIX_ENV_VER\n" >> $f
            echo -e "${v_export}BITRIX_ENV_TYPE=$BITRIX_ENV_TYPE\n" >> $f
            log_to_file "Add BITRIX_VA_VER to file=$f"
        fi
    done

    # configure apache for Centos7
    if [[ $OS_VERSION -eq 7 ]]; then
        HTTPD_ENV_CONF=/etc/httpd/bx/conf/00-environment.conf
        if [[ -s $HTTPD_CONF ]]; then
            sed -i '/BITRIX_VA_VER/d;/BITRIX_ENV_TYPE/d;/AUTHBIND_UNAVAILABLE/d' \
                $HTTPD_ENV_CONF
        fi
        echo -e "# bitrix-env\nSetEnv BITRIX_VA_VER $BITRIX_ENV_VER" >> \
            $HTTPD_ENV_CONF
        echo -e "SetEnv BITRIX_ENV_TYPE $BITRIX_ENV_TYPE\n" >> \
            $HTTPD_ENV_CONF
        echo -e "SetEnv AUTHBIND_UNAVAILABLE yes" >> \
            $HTTPD_ENV_CONF
    fi
}

bx_alternatives_for_mycnf(){
    is_mycnf_alters=$(alternatives --list | grep "^my\.cnf\s\+" -c)
    is_percona_alternatives=$(alternatives --list  | \
        grep "^my\.cnf\s\+" | grep -cv '/etc/bitrix-my.cnf')
    [[ $is_mycnf_alters -eq 0 ]] && return 0            # doesn't use alternatives; skip
    [[ $is_percona_alternatives -eq 0 ]] && return 0    # already created bitrix alternatives; skip

    BACKUP_CFG_DIR=/etc/ansible/roles/mysql/files
    package_mysql

    BACKUP_CFG_FILE=$BACKUP_CFG_DIR/my.cnf.bx
    [[ $MYSQL_MID_VERSION -eq 6 ]] && \
        BACKUP_CFG_FILE=$BACKUP_CFG_DIR/my.cnf.bx_mysql56
    [[ $MYSQL_MID_VERSION -eq 7 ]] && \
        BACKUP_CFG_FILE=$BACKUP_CFG_DIR/my.cnf.bx_mysql57

    cp -f $BACKUP_CFG_FILE /etc/bitrix-my.cnf
    rm -f /etc/my.cnf
    update-alternatives --install /etc/my.cnf my.cnf "/etc/bitrix-my.cnf" 300
	log_to_file "Create /etc/bitrix-my.cnf alternatives"
}


upgrade_fixes(){
    ################################### FIXES
    # 1. FIX ansible group config; change option value from `yes` to `enable`; from `no` to `disable`
    ANS_WEB_GROUP_FILE=/etc/ansible/group_vars/bitrix-web
    if [[ -f $ANS_WEB_GROUP_FILE ]]; then
        sed -i "s/cluster_mysql_configure:\s\+no/cluster_mysql_configure: disable/" $ANS_WEB_GROUP_FILE
        sed -i "s/cluster_mysql_configure:\s\+yes/cluster_mysql_configure: enable/" $ANS_WEB_GROUP_FILE

        sed -i "s/cluster_web_configure:\s\+no/cluster_web_configure: disable/" $ANS_WEB_GROUP_FILE
        sed -i "s/cluster_web_configure:\s\+yes/cluster_web_configure: enable/" $ANS_WEB_GROUP_FILE

        sed -i "s/ntlm_web_configure:\s\+no/ntlm_web_configure: disable/" $ANS_WEB_GROUP_FILE
        sed -i "s/ntlm_web_configure:\s\+yes/ntlm_web_configure: enable/" $ANS_WEB_GROUP_FILE
        log_to_file "Update settings in file=$ANS_WEB_GROUP_FILE"
    fi

    # 2. FIX for version 5.0.46; 
    # 2.1 we created ssl.s1.conf on host where web-cluster exists => we need to delete it
    NGINX_SSLSITE_CONF=/etc/nginx/bx/site_enabled/ssl.s1.conf
    NGINX_SSLSITE_CONF_SRC=/etc/nginx/bx/site_avaliable/ssl.s1.conf
    NGINX_BALANCER_CONF=/etc/nginx/bx/site_enabled/https_balancer.conf
    service nginx configtest 1>/dev/null 2>&1
    if [[ $? -gt 0 ]]; then
        # balancer config file exists and contains default_server option
        if [[ ( -f $NGINX_BALANCER_CONF ) && \
            ( $(cat $NGINX_BALANCER_CONF | grep -wc "default_server") -gt 0 ) ]]; then
            # ssl config file exists and contains default_server option
            if [[ (  -f $NGINX_SSLSITE_CONF ) && \
                ( $(cat $NGINX_SSLSITE_CONF | grep -wc "default_server") -gt 0 ) ]]; then
                rm -f $NGINX_SSLSITE_CONF
                log_to_file "Delete config=$NGINX_SSLSITE_CONF; Found existing config=$NGINX_BALANCER_CONF"
            fi
        fi
    fi
    # 2.2 we cerate ssl.s1.conf on host whih is backend server in web cluster configuration
    ANS_ROLES_FILES=/etc/ansible/ansible-roles
    if [[ -f $ANS_ROLES_FILES ]]; then
        is_backend_web=$(grep '^groups' $ANS_ROLES_FILES | \
            grep -v 'bitrix-mgmt' | grep -c 'bitrix-web')

        # host is part of web-group, but not the balancer
        if [[ $is_backend_web -gt 0 ]]; then
            if [[ -f $NGINX_SSLSITE_CONF ]]; then
                rm -f $NGINX_SSLSITE_CONF
                log_to_file "Delete config=$NGINX_SSLSITE_CONF; Config found on backend node in web-cluster"
            fi
        # 3. FIX; Deletiion of ssl.s1.conf on the master server because of incorrect condition
        else
            # test if main file exists; it will be removed when default site is deleted
            if [[ -f $NGINX_SSLSITE_CONF_SRC ]]; then

                if [[ -L $NGINX_SSLSITE_CONF ]]; then
                    log_to_file "Config file=$NGINX_SSLSITE_CONF is found. Nothing to do"
                else
                    ln -s $NGINX_SSLSITE_CONF_SRC $NGINX_SSLSITE_CONF
                    log_to_file "Recreate link for config=$NGINX_SSLSITE_CONF"
                fi
            fi
        fi
    fi

    # ansible 2.2 include_vars does not have a valid extension: yaml, yml, json
    # issue: https://github.com/ansible/ansible/issues/18223
    # docs: group_vars can optionally end in '.yml', '.yaml', or '.json'
    ANS_GROUP_VARS=/etc/ansible/group_vars
    ANS_GROUPS="bitrix-hosts bitrix-mysql bitrix-web bitrix-sphinx bitrix-memcached"

    for group in $ANS_GROUPS; do
        sfile=$ANS_GROUP_VARS/$group
        hlink=$ANS_GROUP_VARS/$group.yml
        if [[ ( -f $sfile ) && ( ! -f $hlink ) ]]; then
            log_to_file "Replace $sfile by $hlink"
            mv -f $sfile $hlink
        fi
    done

    # http://jabber.bx/view.php?id=80407
    # PHP Warning:  PHP Startup: Unable to load dynamic library ... /pdo_dblib.so: 
    # undefined symbol: php_pdo_unregister_driver in Unknown on line 0
    if_error_01=$(php -m 2>&1 | grep -c "undefined symbol: php_pdo_unregister_driver")
    if [[ $if_error_01 -gt 0 ]]; then
        echo "extension=pdo.so" > /etc/php.d/20-pdo.ini
    fi

    if_error_02=$(php -m 2>&1 | grep -c "undefined symbol: php_pdo_register_driver")
    if [[ $if_error_02 -gt 0 ]]; then
        echo ";extension=pdo_dblib.so" > /etc/php.d/30-pdo_dblib.ini
    fi

    # nginx DHP options
    if_dhp=$(grep -v "^$\|^#" /etc/nginx/bx/conf/ssl.conf | grep -cw ssl_dhparam)
    if [[ ( $if_dhp -eq 0 ) && ( -f /etc/nginx/ssl/dhparam.pem ) ]]; then
        echo "ssl_dhparam         /etc/nginx/ssl/dhparam.pem;" >> /etc/nginx/bx/conf/ssl.conf
    fi

    # clean cache
    cache_directory=/opt/webdir/tmp
    if [[ -d $cache_directory ]]; then
        find $cache_directory -type f -delete
    fi

    # http://jabber.bx/view.php?id=77187
    SUDOERS_FILE=/etc/sudoers.d/bitrix_hosts
    if [[ ! -f $SUDOERS_FILE ]]; then
        if [[ $(grep -wc bitrix-mgmt /etc/ansible/hosts) -gt 0 ]]; then
            LIST_HOSTS=$(grep -v '^#\|^$\|\[' /etc/ansible/hosts | sort | uniq | awk '{printf "%s ", $1}')
            LIST_HOSTS=$LIST_HOSTS"localhost"
        else
            LIST_HOSTS="localhost"
        fi
        for h in $LIST_HOSTS; do
            ANSIBLE_CMD=$ANSIBLE_CMD"/usr/bin/ansible $h -m setup,"
        done
        ANSIBLE_CMD=$(echo "$ANSIBLE_CMD" | sed -e "s/,$//")
        echo "Cmnd_Alias BXANSIBLE = $ANSIBLE_CMD" > $SUDOERS_FILE
        log_to_file "bitrix  ALL=(ALL) NOPASSWD: BXANSIBLE to $SUDOERS_FILE"
    fi

    # aliases for mariadb service
    package_mysql
    if [[ $(echo $MYSQL_PACKAGE | grep -wci mariadb) -gt 0 ]]; then
        if [[ $OS_VERSION -eq 7 ]]; then
            ln -fs '/usr/lib/systemd/system/mariadb.service' '/etc/systemd/system/mysql.service'
            ln -fs '/usr/lib/systemd/system/mariadb.service' '/etc/systemd/system/mysqld.service'
        fi
    fi

    # http://jabber.bx/view.php?id=87272
    # upgrade push server
    if [[ -f /etc/nginx/bx/conf/im_settings.conf ]]; then
        mv -f /etc/nginx/bx/conf/im_settings.conf /etc/nginx/bx/conf/push-im_settings.conf
    fi

    # http://jabber.bx/view.php?id=87278
    # add new group push
    if [[ ( -f /etc/ansible/hosts ) && \
        ( $(grep -c "bitrix-hosts" /etc/ansible/hosts) -gt 0 ) && \
        ( $(grep -c "bitrix-push" /etc/ansible/hosts) -eq 0 ) ]]; then
        echo -e "[bitrix-push]\n" >> /etc/ansible/hosts
    fi

    # http://jabber.bx/view.php?id=90064
    log_to_file "OS_VERSION=$OS_VERSION"
    if [[ $OS_VERSION -eq 7 ]]; then
        log_to_file "Disable mod_auth_digest.so at /etc/httpd/conf.modules.d/00-base.conf"
        sed -i "/mod_auth_digest.so/d" /etc/httpd/conf.modules.d/00-base.conf
    fi

    if [[ -d /etc/ansible/host_vars ]]; then
        for f in $(find /etc/ansible/host_vars -type f); do 
            if [[ $(grep -wc "bx_host" $f) -eq 0 ]]; then
                bx_hostname=$(grep "bx_hostname:" $f | awk -F':' '{print $2}')
                echo "bx_host:$bx_hostname" >> $f
            fi
        done
    fi

    # http://jabber.bx/view.php?id=92994; remove mbstring.internal_encoding for php >= 5.6
    #if [[ ( $PHP_VERSION -ge 5 && $PHP_VERSION_MID -ge 6 ) || \
    #    $PHP_VERSION -ge 7 ]]; then
    #    OLD_VALUE="php_admin_value mbstring.internal_encoding"
    #    NEW_VALUE="php_admin_value default_charset"
    #    HTTPD_CONF_DIRS="/etc/httpd/bx/conf /etc/httpd/bx-scale/conf"
    #    for dir in $HTTPD_CONF_DIRS; do
    #        if [[ -d $dir ]]; then
    #            for file in $(find $dir/ -type f -name "*.conf"); do
    #                if [[ $(grep -c "mbstring.internal_encoding" $file) -gt 0 ]]; then
    #                    sed -i "s/$OLD_VALUE/$NEW_VALUE/" $file
    #                    log_to_file "Replace mbstring.internal_encoding in $file"
    #                fi
    #            done
    #        fi
    #    done
    #fi

    # http://jabber.bx/view.php?id=96220; LE certificates and nginx restart
    # replace 
    # "0 12 1 * * bitrix /home/bitrix/dehydrated/dehydrated -c >/home/bitrix/dehydrated_update.log 2>&1"
    # by
    # "0 12 1 * * /opt/webdir/bin/bx-dehydrated"
    is_clean_dehydrated=$(cat /etc/crontab | grep -c "bitrix /home/bitrix/dehydrated/dehydrated")
    is_incorrect_crontab=$(cat /etc/crontab | grep -c '* /opt/webdir/bin/bx-dehydrated')

    if [[ $is_clean_dehydrated -gt 0 || $is_incorrect_crontab -gt 0 ]]; then
        sed -i "/\/home\/bitrix\/dehydrated\/dehydrated/d" /etc/crontab
        sed -i "/\/opt\/webdir\/bin\/bx-dehydrated/d" /etc/crontab
        sed -i "/\/home\/bitrix\/dehydrated\/certs/d" /etc/crontab

        echo '0 12 1 * * root /opt/webdir/bin/bx-dehydrated' >> /etc/crontab
        echo '0 12 2 * * bitrix find /home/bitrix/dehydrated/certs -type f -mtime +120 -delete >>/home/bitrix/dehydrated_update.log 2>&1' >> /etc/crontab
        log_to_file "Replace /home/bitrix/dehydrated/dehydrated by /opt/webdir/bin/bx-dehydrated"
    fi

	# fixes for my.cnf alternatives
	# http://jabber.bx/view.php?id=99083
	bx_alternatives_for_mycnf


    # http://jabber.bx/view.php?id=96811
    /opt/webdir/bin/update_network.sh

    # http://jabber.bx/view.php?id=84610
    if [[ $(grep -v '^$\|^#' /etc/yum.conf | \
        grep -c "installonly_limit" ) -eq 0 ]]; then
        echo "installonly_limit=3" >> /etc/yum.conf
    else
        if [[ $(grep -v '^$\|^#' /etc/yum.conf | \
            grep -c "installonly_limit=5") -gt 0 ]]; then
            sed -i "s/installonly_limit=5/installonly_limit=3/" /etc/yum.conf 
        fi
    fi

    # http://jabber.bx/view.php?id=80385
    if [[ ! -d /home/bitrix/www ]]; then
        for conf in /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd-scale.conf; do
            sed -i "/DocumentRoot/d" $conf
            echo "DocumentRoot '/var/www/html'" >> $conf
        done

        echo "Listen 127.0.0.1:8888" >> /etc/httpd/conf/httpd.conf
        echo "Listen 127.0.0.1:9887" >> /etc/httpd/conf/httpd-scale.conf
    fi

}

install_fixes(){
    # http://jabber.bx/view.php?id=90064
    log_to_file "OS_VERSION=$OS_VERSION"

    if [[ $OS_VERSION -eq 7 ]]; then
        log_to_file "Disable mod_auth_digest.so at /etc/httpd/conf.modules.d/00-base.conf"
        sed -i "/mod_auth_digest.so/d" /etc/httpd/conf.modules.d/00-base.conf
    fi
}

# post installation action for install process; no previous installation bitrix-env
install() {
    # configure shadow for old systems?
    pwconv

    # configure bitrix user
    id bitrix 1>/dev/null 2>&1
    bitrix_rtn=$?
    if [[ $bitrix_rtn -gt 0 ]]; then
        groupadd -g 600 bitrix && \
            useradd -g 600 -u 600 -p bitrix bitrix && \
            chage -d 0 bitrix
        if [[ $? -gt 0 ]]; then
            log_to_file "Cannot create bitrix user. Exit" "ERROR"
            exit 1
        else
            log_to_file "User bitrix was created"
        fi
    fi

    # disable SELinux
    [[ -d /selinux ]] && echo 0 > /selinux/enforce
    if [[ -f /etc/selinux/config ]]; then
        sed -i".$UPDATE_TM" "s/^SELINUX\=.*/SELINUX\=disabled/g" /etc/selinux/config
        log_to_file "SELinux was disabled"
    fi

    # configure OS
    #configure_system

    # configure MySQL/MariaDB services
    MYSQL_MAIN_CFG=/etc/my.cnf
   MYSQL_INCLUDE_DIR=/etc/mysql/conf.d
    MYSQL_BASE_DIR=/var/lib/mysql
    MYSQL_BASE_BKP_DIR=/var/lib/mysql.$UPDATE_TM
    MYSQL_SOCKET_DIR=/var/lib/mysqld                    # it is legacy option
    MYSQL_CUSTOM_CFG=$MYSQL_INCLUDE_DIR/z_bx_custom.cnf
    MYSQL_LOCAL_CFG=/root/my.cnf
    install_mysql

    # create database for bitrix default site
    # create mysql user settings and save them to config files
    SITE_DIR=/home/bitrix/www
    PHP_SESS_DIR=/tmp/php_sessions
    PHP_UPLD_DIR=/tmp/php_upload
    PHP_LOGS_DIR=/var/log/php
    create_site_settings

    # configure apache service
    # etc/httpd/bx/conf/default.conf.bx         - config for default site
    # etc/httpd/bx/conf/mod_geoip.conf.bx       - enable module geoip
    # etc/httpd/bx/conf/mod_rpaf.conf.bx        - enable module real ip for apache
    # etc/httpd/bx/conf/php.conf.bx             - enable php module
    # etc/httpd/bx/custom/z_bx_custom.conf.bx   - create emty file, that can be used by customer
    # etc/httpd/conf/httpd.conf.bx              - default config file
    # Note! Replace files only for first installation
    HTTPD_CONF_DIR=/etc/httpd
    HTTPD_CONF_LIST="bx/conf/default.conf conf/httpd.conf
    bx/conf/mod_geoip.conf bx/conf/mod_rpaf.conf
    bx/conf/php.conf bx/custom/z_bx_custom.conf"
    HTTPD_CONF_LIST_PURGE="bx/conf/ssl.conf bx/conf/proxy_ajp.conf
    bx/conf/mod_auth_ntlm_winbind.conf"
    HTTPD_TMODULES_LIST="dav lua proxy ssl cgi geoip"
    HTTPD_FMODULES_LIST="base.conf"
    configure_httpd

    # configure nginx service
    # etc/nginx/nginx.conf.bx                     - general config file
    # etc/nginx/openssl.cnf.bx                    - file that used when keys or certs are generated
    # etc/nginx/bx/conf/ssl.conf.bx               - ssl settings
    # etc/nginx/bx/conf/blank.conf.bx             - empty file
    # etc/nginx/bx/conf/im_subscrider.conf.bx     - push&pull settings (sub and subws locations)
    # etc/nginx/bx/conf/im_settings.conf.bx       - push&pull memory and channels options
    # etc/nginx/bx/conf/errors.conf.bx            - default error pages for all sites
    # etc/nginx/bx/conf/bitrix.conf.bx            - default settings for bitrix-env (included in any site config)
    # etc/nginx/bx/conf/bitrix_general.conf       - default settings for bitrix-env (without root location, usage when composite settings enabled)
    # etc/nginx/bx/site_avaliable/ssl.s1.conf.bx  - default site on the server (https access)
    # etc/nginx/bx/site_avaliable/s1.conf.bx      - default site on the server (http access)
    # etc/nginx/bx/site_avaliable/push.conf.bx    - push&pull http servers
    # etc/nginx/bx/maps/composite_settings.conf   - main composite settings that the same fow all site on the server
    # etc/nginx/bx/conf/bitrix_block.conf         - locations with deny access
    NGINX_CONF_DIR=/etc/nginx
    NGINX_CONF_LIST="bx/conf/ssl.conf bx/conf/blank.conf
    bx/conf/bitrix_block.conf bx/conf/bitrix_general.conf
    bx/maps/composite_settings.conf bx/maps/common_variables.conf
    bx/conf/push-im_settings.conf bx/conf/push-im_subscrider.conf
    bx/conf/bitrix.conf bx/conf/errors.conf
    bx/conf/bitrix_scale.conf
    bx/site_avaliable/ssl.s1.conf bx/site_avaliable/s1.conf
    bx/site_avaliable/push.conf
    bx/conf/general-add_header.conf
    openssl.cnf nginx.conf"
    NGINX_CONF_SITES="bx/site_avaliable/ssl.s1.conf bx/site_avaliable/s1.conf
    bx/site_avaliable/push.conf"
    NGINX_CONF_SSL_CNF=$NGINX_CONF_DIR/openssl.cnf
    NGINX_CONF_LINKS="bx/conf/http-add_header.conf=bx/conf/general-add_header.conf
    bx/server_monitor.conf=bx/conf/blank.conf 
    bx/settings/im_settings.conf=bx/conf/push-im_settings.conf
    bx/conf/im_subscrider.conf=bx/conf/push-im_subscrider.conf"
    NGINX_CONF_DEFAULT_SSL="bx/site_avaliable/ssl.s1.conf"
    configure_nginx

    # configure php
    PHP_CONF_FILE="/etc/php.ini"
    PHP_CONF_DIR=/etc/php.d
    PHP_MODULES_DISABLE="xdebug xhprof mssql
    phar xmlwriter xmlreader dom
    sqlite3 pdo pdo_dblib pdo_mysql
    pdo_sqlite imap xsl soap
    curl gmp posix sybase_ct sysvmsg
    sysvsem sysvshm wddx xsl ftp"
    PHP_MODULES_ENABLE="json mysqli" 
    configure_php

    # configure stunnel
    configure_stunnel

    # configure bvat script runnig
    configure_bvat

    # configure msmtp agent
    configure_msmtp

    # configure ntpd
    configure_ntp

    # configure crontab
    configure_crontab

    # configure autobind
    configure_autobind

    # delete *.bx files from /etc
    delete_unused_bxfiles

    install_fixes

    # add BITRIX_VA_VER to config files
    BITRIX_VA_VER_FILES="/etc/sysconfig/httpd /etc/profile /root/.bash_profile"
    configure_bitrix_env_var
    echo -e "#menu\n~/menu.sh\n" >> /root/.bash_profile

    # restart services
    restart_services

    export BITRIX_VA_VER=$BITRIX_ENV_VER

}

upgrade(){
    # configure apache service
    # etc/httpd/bx/conf/default.conf.bx         - config for default site
    # etc/httpd/bx/conf/mod_geoip.conf.bx       - enable module geoip
    # etc/httpd/bx/conf/mod_rpaf.conf.bx        - enable module real ip for apache
    # etc/httpd/bx/conf/php.conf.bx             - enable php module
    # etc/httpd/bx/custom/z_bx_custom.conf.bx   - create emty file, that can be used by customer
    # etc/httpd/conf/httpd.conf.bx              - default config file
    # Note! Replace files only for first installation
    HTTPD_CONF_DIR=/etc/httpd
    HTTPD_CONF_LIST="bx/conf/mod_geoip.conf bx/conf/mod_rpaf.conf
    bx/conf/php.conf conf/httpd.conf"
    HTTPD_CONF_LIST_PURGE="bx/conf/ssl.conf bx/conf/proxy_ajp.conf
    bx/conf/mod_auth_ntlm_winbind.conf"
    configure_httpd

    # configure nginx service
    # etc/nginx/nginx.conf.bx                     - general config file
    # etc/nginx/openssl.cnf.bx                    - file that used when keys or certs are generated
    # etc/nginx/bx/conf/ssl.conf.bx               - ssl settings
    # etc/nginx/bx/conf/blank.conf.bx             - empty file
    # etc/nginx/bx/conf/im_subscrider.conf.bx     - push&pull settings (sub and subws locations)
    # etc/nginx/bx/conf/im_settings.conf.bx       - push&pull memory and channels options
    # etc/nginx/bx/conf/errors.conf.bx            - default error pages for all sites
    # etc/nginx/bx/conf/bitrix.conf.bx            - default settings for bitrix-env (included in any site config)
    # etc/nginx/bx/conf/bitrix_general.conf       - default settings for bitrix-env (without root location, usage when composite settings enabled)
    # etc/nginx/bx/site_avaliable/ssl.s1.conf.bx  - default site on the server (https access)
    # etc/nginx/bx/site_avaliable/s1.conf.bx      - default site on the server (http access)
    # etc/nginx/bx/site_avaliable/push.conf.bx    - push&pull http servers
    # etc/nginx/bx/maps/composite_settings.conf   - main composite settings that the same fow all site on the server
    # etc/nginx/bx/conf/bitrix_block.conf         - locations with deny access
    NGINX_CONF_DIR=/etc/nginx
    NGINX_CONF_LIST="bx/conf/bitrix.conf
    bx/conf/bitrix_block.conf
    bx/conf/bitrix_general.conf
    bx/maps/composite_settings.conf
    bx/maps/common_variables.conf
    bx/conf/push-im_subscrider.conf
    bx/conf/ssl.conf
    bx/conf/general-add_header.conf
    bx/conf/bitrix_scale.conf
    nginx.conf"
    NGINX_CONF_SSL_CNF=$NGINX_CONF_DIR/openssl.cnf
    NGINX_CONF_LINKS="bx/conf/http-add_header.conf=bx/conf/general-add_header.conf
    bx/server_monitor.conf=bx/conf/blank.conf
    bx/settings/im_settings.conf=bx/conf/push-im_settings.conf"
 
    configure_nginx

    # configure php
    PHP_CONF_FILE="/etc/php.ini"
    PHP_CONF_DIR=/etc/php.d
    PHP_MODULES_DISABLE=
    PHP_MODULES_ENABLE="mysqli"
    SITE_DIR=/home/bitrix/www
    configure_php

    # update BITRIX_VA_VER to config files
    BITRIX_VA_VER_FILES="/etc/sysconfig/httpd /etc/profile /root/.bash_profile"
    configure_bitrix_env_var

    # configure bvat script running
    configure_bvat

    # configure msmtp
    configure_msmtp

    # configure ntpd
    configure_ntp

    # configure crontab
    configure_crontab

    # configure autobind
    configure_autobind

    # delete unused *.bx files from rpm package
    delete_unused_bxfiles

    # fixes
    upgrade_fixes

    # restart services
    restart_services

    export BITRIX_VA_VER=$BITRIX_ENV_VER


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
        log_to_file "INcorrect action=$RPM_ACTION"
        ;;
esac