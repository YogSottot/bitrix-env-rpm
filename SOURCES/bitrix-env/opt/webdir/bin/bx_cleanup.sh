#!/usr/bin/bash
#
# clear temporary trash files for transformer module
#set -x
#
export LANG=en_US.UTF-8
export TERM=linux

PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
BASE_DIR=/opt/webdir
BITRIX_DIR=/home/bitrix/.webdir
SAVE_LIMIT=7    # save backup for 7 days

# opt/webdir/bin/bx-sites -a status --site  SITE | grep directory
# bxSite:directory:SITE:dbksh:/home/bitrix/ext_www/SITE:upload
SITE_SCRIPT=$BASE_DIR/bin/bx-sites 
LOGS_DIR=$BITRIX_DIR/logs
TEMP_DIR=$BITRIX_DIR/temp
LOGS_FILE=$LOGS_DIR/transformer_cleanetransformer_cleaner.log
[[ -z $DEBUG ]] && DEBUG=0

# create additional directories
for _dir in $BITRIX_DIR $LOGS_DIR $TEMP_DIR; do
    [[ ! -d $_dir ]] && mkdir -p -m 700 $_dir
done

# test options
SITE_NAME=${1}
TR_DIR=${2:-transformercontroller}

if [[ -z "$SITE_NAME" ]];
then
    echo "Usage: $PROGNAME site_name"
    echo "Ex."
    echo "$PROGNAME test.site"
    echo
    exit 1
fi

# logging infor to file
log_to_file() {
    _mess=$1

    echo "$(date +"%Y/%m/%d %H:%M:%S") $$ $_mess" | tee -a $LOGS_FILE
}

error() {
    _mess="${1}"
    _exit="${2:-1}"

    [[ -f $BACK_DB_MYCNF ]] && rm -f $BACK_DB_MYCNF

    log_to_file "$_mess"
    exit $_exit
}

# get site upload directory
SITE_INFO=$($SITE_SCRIPT -a status --site $SITE_NAME)

UPLOAD_DIR=$(echo "$SITE_INFO" | grep ':directory:' | awk -F':' '{print $6}')
if [[ -z $UPLOAD_DIR ]];
then
    error "There are no upload_dir option for site $SITE_NAME. Exit"
fi

if [[ $UPLOAD_DIR =~ "." || $UPLOAD_DIR =~ "/" ]];
then
    error "Directory name $UPLOAD_DIR contains invalid characters. Exit"
fi

if [[ $TR_DIR =~ "." || $TR_DIR =~ "/" ]];
then
    error "Directory name $TR_DIR contains invalid characters. Exit"
fi

SITE_DIR=$(echo "$SITE_INFO" |  grep ':directory:' | awk -F':' '{print $5}')

TR_FF="${SITE_DIR}/${UPLOAD_DIR}/${TR_DIR}"
if [[ ! -d $TR_FF ]];
then
    error "There are no $TR_FF"
fi

pushd $TR_FF || exit 
find .  -type f -mmin +60 -exec rm -rf "{}" ";" >> $LOGS_FILE 2>&1
popd 
