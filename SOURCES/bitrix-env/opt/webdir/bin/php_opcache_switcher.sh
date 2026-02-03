#!/usr/bin/bash
#
ACTION=$1
OPCACHE_INI_FILE=/etc/php.d/10-opcache.ini
if [[ -f ${OPCACHE_INI_FILE} ]];
then
    if [[ ${ACTION} == 'off' ]];
    then
        sed -i "s/.*zend_extension.*/; zend_extension=opcache.so/" ${OPCACHE_INI_FILE}
    fi
    if [[ ${ACTION} == 'on' ]];
    then
        sed -i "s/.*zend_extension.*/zend_extension=opcache.so/" ${OPCACHE_INI_FILE}
    fi
fi
