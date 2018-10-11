#!/bin/bash

ip_=`ifconfig | grep Bcast | grep -v 127.0.0.1 | awk '{print $2}' | sed 's/addr://'`


echo "Bitrix virtual appliance helpful information:"
echo
echo "IP address:" ${ip_}
[ -f /home/bitrix/www/.htsecure ] && echo "Bitrix product working on HTTPS port and available on https://"${ip_} || echo "Bitrix product working on HTTP and HTTPS ports on http://"${ip_}" or https://"${ip_}

echo "Default password for user root: bitrix. You have to change this for the first login"
echo "For MySQL access use username root without password"

echo "Current mail send subsystem(SMTP) parameters:"
test -f /home/bitrix/.msmtprc && cat /home/bitrix/.msmtprc || echo "Not configured yet"
