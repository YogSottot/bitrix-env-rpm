#!/bin/bash

export LANG=en_US.UTF-8
export TERM=linux
export NOLOCALE=yes

BASE_DIR=/opt/webdir
LOGS_DIR=$BASE_DIR/logs
TEMP_DIR=$BASE_DIR/temp
CACHE_DIR=$BASE_DIR/tmp
BIN_DIR=$BASE_DIR/bin
bx_process_script=$BIN_DIR/bx-process

# get_text variables
[[ -f $BIN_DIR/bitrix_utils.sh ]] && \
    . $BIN_DIR/bitrix_utils.sh

[[ ! -d $CACHE_DIR  ]] && mkdir -m 700 $CACHE_DIR

LOGS_FILE=$LOGS_DIR/restart_httpd-scale.log
REQUEST_FILE=$LOGS_DIR/restart_httpd-scale.request

TYPE=${1:-request}

if [[ $TYPE == "request" ]]; then
    touch $REQUEST_FILE
    print_log "Create $REQUEST_FILE file" $LOGS_FILE
    exit 0
elif [[ $TYPE == "process" ]]; then
    if [[ -f $REQUEST_FILE ]]; then
        is_ansible_running
        if  [[ $? -eq 0 ]]; then
            print_log "Reload httpd-scale service" $LOGS_FILE
            systemctl reload httpd-scale >> $LOGS_FILE 2>&1
            rm -f $REQUEST_FILE
        else
            print_log "Found $IS_ANSIBLE_PROCESS ansible-playbooks. Exit"
        fi
    fi
else
     print_log "Incorrect option=$TYPE"
fi
