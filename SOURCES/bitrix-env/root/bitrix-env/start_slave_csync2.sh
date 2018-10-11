#!/bin/bash

#
# Rebuild www csync2
#

hostname=`hostname`

echo
echo "Extract site files on slave node"
chown -R bitrix:bitrix /home/bitrix/www
cd /home/bitrix
tar -zxf tmp_add_slave_backup.tar.gz > /dev/null &
P=${!}
while [ `ps -p $P h|wc -l` -ne '0' ]; do
	echo -ne "."
	sleep 1
done
echo
chown -R bitrix:bitrix /home/bitrix/www

echo
echo "Remove tmp_add_slave_backup.tar.gz from slave node"
test -f /home/bitrix/tmp_add_slave_backup.tar.gz && { rm -f /home/bitrix/tmp_add_slave_backup.tar.gz ; }

echo 
echo "Create csync2 database of slave node files"
csync2 -cIr -C bxwww /home/bitrix > /dev/null &
P=${!}
while [ `ps -p $P h|wc -l` -ne '0' ]; do
	echo -ne "."
	sleep 1
done
echo

chown bitrix:root /var/lib/csync2/"$hostname"_bxwww.db
chmod 0664 /var/lib/csync2/"$hostname"_bxwww.db

echo
echo "Add csync2 to cron on slave node"
test -z "`cat /etc/crontab | grep csync2 `" && echo "*/5 * * * * bitrix csync2 -cr -C bxwww / csync2 -u -C bxwww
" >> /etc/crontab;

