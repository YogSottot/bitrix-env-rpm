#!/usr/bin/bash
#
PHP_INI_FILE=/etc/php.ini
PHP_INI_RPMNEW_FILE=/etc/php.ini.rpmnew
if [[ -f ${PHP_INI_RPMNEW_FILE} ]];
then
    mv -f ${PHP_INI_RPMNEW_FILE} ${PHP_INI_FILE}
fi
