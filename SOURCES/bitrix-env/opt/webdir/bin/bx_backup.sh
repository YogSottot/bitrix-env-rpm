#!/usr/bin/bash
#
# backup site information
# argv:
# $1 - kernel_name  - dbname for site ( create backup for all sites with with db)
# $2 - backup_dir 
# if site is link - backup only files
# if iste is kernel - files + mysql
#set -x
#
export LANG=en_US.UTF-8
export TERM=linux
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)

BASE_DIR=/opt/webdir
BITRIX_DIR=/home/bitrix/.webdir
SAVE_LIMIT=7    # save backup for 7 days

. $PROGPATH/bitrix_utils.sh || exit 1

site_menu_dir=$BASE_DIR/bin/menu/06_site
site_menu_fnc=$site_menu_dir/functions.sh
. $site_menu_fnc || exit 1

LOGS_DIR=$BITRIX_DIR/logs
TEMP_DIR=$BITRIX_DIR/temp
CONF_DIR=$BITRIX_DIR/etc
LOGS_FILE=$LOGS_DIR/backup_sites.log
[[ -z $DEBUG ]] && DEBUG=0

# create additional directories
for _dir in $BITRIX_DIR $LOGS_DIR $TEMP_DIR $CONF_DIR; do
  [[ ! -d $_dir ]] && mkdir -p -m 700 $_dir
done

# test options
kernel_name=$1
backup_dir=$2
sql_dir=/home/bitrix
if [[ ( -z "$kernel_name" ) || ( -z $backup_dir ) ]]; then
    echo "Usage: $PROGNAME kernel_name backup_dir"
    echo "Ex."
    echo "$PROGNAME sitemanager0 /home/bitrix/backup/archive"
    echo
    exit 1
fi

[[ ! -d $backup_dir ]] && mkdir $backup_dir

# logging infor to file
log_to_file() {
    _mess=$1

    echo "$(date +"%Y/%m/%d %H:%M:%S") $$ $_mess" | tee -a $LOGS_FILE
}

error() {
    _mess="${1}"

    [[ -f $BACK_DB_MYCNF ]] && rm -f $BACK_DB_MYCNF

    log_to_file "$_mess"
    exit 1
}

# create backup directory that can be access from http(s)
create_wwwbackup_directory() {
    _backup_directory=$1
    if [[ ! -d $_backup_directory ]];then
        mkdir -p $_backup_directory
        echo "<head>
        <meta http-equiv=\"REFRESH\" content=\"0;URL=/bitrix/admin/index.php\">
        </head>
        " > $_backup_directory/index.php
        chown -R bitrix.bitrix $_backup_directory
        chmod -R 0755 $_backup_directory
        [[ $DEBUG -gt 0 ]] && \
            log_to_file "Create backup directory $_backup_directory"
    fi
}

# create mysql dump
create_mysqldump() {
    _dump_conf=$1
    _dump_db=$2
    _dump_char=$3
    _dump_var_files=$4

    # define dump file name
    _dump_file=$sql_dir/mysql_dump_${_dump_db}_${DATE_STR}_${RAND_STR}.sql
    _acon_file=$sql_dir/mysql_dump_${_dump_db}_${DATE_STR}_${RAND_STR}_after_connect.sql

    # create dump
    mysqldump --defaults-file=$_dump_conf --default-character-set=$_dump_char \
        $_dump_db > $_dump_file
    [[ $? -gt 0 ]] && error "mysqldump cmd return error"
    [[ $DEBUG -gt 0 ]] && \
        log_to_file "Create mysqldump db=$_dump_db"

    # for php-restore support
    sed -i "/\/*40101 SET/d;/\/*40103 SET/d;/\!40111 SET/d;/\!40014 SET/d;/\!40000 ALTER/d" \
        $_dump_file

    # Clean mysql log
    if [ "$_dump_char" == "cp1251" ]; then
        echo "SET NAMES 'cp1251' COLLATE 'cp1251_general_ci';" > $_acon_file
    else
        echo "SET NAMES 'utf8mb4' COLLATE 'utf8mb4_0900_ai_ci';" > $_acon_file
    fi

    eval "$_dump_var_files='$_dump_file $_acon_file'"
}

# get_pool_sites
# POOL_SITES_KERNEL_LIST
# POOL_SITES_LINK_LIST
# POOL_SITES_KETNEL_COUNT
# POOL_SITES_LINK_COUNT
get_kernel_info() {
    # get list of all sites on the server
    get_pool_sites
    # test if site with defined kernelname exists
    found_kernel_name=$(echo "$POOL_SITES_KERNEL_LIST" | grep -c ":$kernel_name:")
    [[ $found_kernel_name -eq 0 ]] && \
        error "Not found sites with defined db=$kernel_name"
    [[ $DEBUG -gt 0 ]] && \
        log_to_file "Get list sites; use information for link sites"

    # kernel info
    BACK_DB=$kernel_name
    # default or alice.bx
    BACK_KERNEL_SITE=$(echo "$POOL_SITES_KERNEL_LIST" | \
        grep ":$kernel_name:" | awk -F':' '{print $1}')
    # /home/bitrix/www
    BACK_KERNEL_ROOT=$(echo "$POOL_SITES_KERNEL_LIST" | \
        grep ":$kernel_name:" | awk -F':' '{print $6}')
    # utf-8| cp1251
    BACK_KERNEL_CHAR=$(echo "$POOL_SITES_KERNEL_LIST" | \
        grep ":$kernel_name:" | awk -F':' '{print $7}')

    # bxSite:db:cp.ksh.bx:dbcp:mysql:localhost:cp:*************::/home/bitrix/.tmp/.my_cnfcyPNwh9_
    DB_INFO=$(get_site_my_connect "$BACK_KERNEL_SITE" "$BACK_KERNEL_ROOT" "$BITRIX_DIR" "my_cnf")
    [[ -z "$DB_INFO" ]] &&  \
        error "Cannot create temporary my.cnf file"
    
    BACK_DB_TYPE=$(echo "$DB_INFO" | awk -F':' '{print $5}')   # mysql
    BACK_DB_HOST=$(echo "$DB_INFO" | awk -F':' '{print $6}')   # h01w
    BACK_DB_MYCNF=$(echo "$DB_INFO" | awk -F':' '{print $NF}')   # /opt/webdir/tmp/.my_cnf2AOOxKwn
    [[ $BACK_DB_TYPE != "mysql" ]] && \
        error "Only work for mysql type of tables. SITE=$BACK_KERNEL_SITE DB_TYPE=$BACK_DB_TYPE"
    [[ $DEBUG -gt 0 ]] && \
        log_to_file "Create temporary my.cnf"

    # get info about links
    BACK_WWW_DIRS="."
    if [[ $POOL_SITES_LINK_COUNT -gt 0 ]]; then
        for _site_info in $(echo "$POOL_SITES_LINK_LIST" | grep ":$kernel_name:"); do
            _site_name=$(echo "$POOL_SITES_LINK_LIST" | \
                grep ":$kernel_name:" | awk -F':' '{print $1}')
            _site_root=$(echo "$POOL_SITES_LINK_LIST" | \
                grep ":$kernel_name:" | awk -F':' '{print $6}')
            _site_status=$(echo "$POOL_SITES_LINK_LIST" | \
                grep ":$kernel_name:" | awk -F':' '{print $4}')
            [[ "$_site_status" == "finished" ]] && \
                BACK_WWW_DIRS=$BACK_WWW_DIRS" $_site_root"
        done
    fi
    [[ $DEBUG -gt 0 ]] && \
        log_to_file "Site directories=$BACK_WWW_DIRS"
}

# clean old backup
# crontab can be different => limit by count
clean_old_backup_files() {
    # there are today's backup 
    TODAYS_FILES=$(find $backup_dir -name "www_backup_${kernel_name}*.tar.gz" -mtime -1 | wc -l)
    if [[ $TODAYS_FILES -gt 0 ]]; then
        find $backup_dir -name "www_backup_${kernel_name}*.tar.gz" -mtime +$SAVE_LIMIT -delete
    fi
}

# create backup archive
# backup_dir/wwww_backup_$kernel_name_$DATE_STR_$RAND_STR.tar
create_backup_archive() {
    BACK_FILE=$backup_dir/www_backup_${kernel_name}_${DATE_STR}_${RAND_STR}.tar

    # create tar archive
    tar -cf $BACK_FILE --exclude-from=$WWW_EXCL_DIR -C $BACK_KERNEL_ROOT \
        $BACK_WWW_DIRS \
        $BACK_SQL_FILES 2>/dev/null
    # 1      Some files differ
    # 2      Fatal error.  This means that some fatal, unrecoverable error occurred.
    [[ $? -eq 2 ]] && \
        error "Cannot create tar archive=$BACK_FILE"

    gzip $BACK_FILE

    # delete sql files; we have added them to archive
    for sql_file in $BACK_SQL_FILES; do
        rm -f $sql_file
        log_to_file "Delete sql file=$sql_file"
    done
}

# get backup info
DATE_STR=$(date +%d.%m.%Y)         # backup date
RAND_STR=$(create_random_string)   # backup random string
WWW_BACK_DIR=/home/bitrix/www/bitrix/backup   # dir can be used by php via http(s)
WWW_EXCL_DIR=$BASE_DIR/bin/ex.txt

# test and create backup directory
create_wwwbackup_directory "$WWW_BACK_DIR"

# get options about sites on for defined kernel
get_kernel_info 

# create mysqldump files - list files in BACK_SQL_FILES
mysql_charset='utf8mb4'
[[ "$BACK_KERNEL_CHAR" == "cp1251" ]] && mysql_charset="cp1251"

# create backup via mysqldump
create_mysqldump "$BACK_DB_MYCNF" "$kernel_name" "$mysql_charset" "BACK_SQL_FILES"
rm -f $BACK_DB_MYCNF

#archive backup in file
create_backup_archive

# clean files from old backups
clean_old_backup_files
