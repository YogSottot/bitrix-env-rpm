#!/usr/bin/bash
#
PHP_INI_FILE=/etc/php.ini
UPDATE_TM=$(date +'%Y%m%d%H%M')
if [[ -f ${PHP_INI_FILE} ]];
then
    cp -f ${PHP_INI_FILE} ${PHP_INI_FILE}.ori.${UPDATE_TM}
fi
