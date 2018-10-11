#!/bin/bash

#
# Check node in cluster
#

#
# Move
#

LIMIT=1
mywwwvar=0
until  test "$mywwwvar" -eq "$LIMIT"
do
	test -d /home/bitrix/www."$mywwwvar" && { (( mywwwvar++ )) ; (( LIMIT++ )) ; } || LIMIT=`expr $mywwwvar`
done

test -d /home/bitrix/www && {
	echo	
	mv -f /home/bitrix/www /home/bitrix/www."$mywwwvar" ;
	echo 'Directory /home/bitrix/www was moved to /home/bitrix/www.'"$mywwwvar" ;
	echo
}

mkdir -p /home/bitrix/www
chown -R bitrix:bitrix /home/bitrix/www
chmod -R 0770 /home/bitrix/www

test -d /etc/bx_cluster/site_enabled && { rm -rf /etc/bx_cluster/site_enabled ; mkdir -p /etc/bx_cluster/site_enabled ; }
test ! -d /var/log/mysqld && { mkdir -p /var/log/mysqld ; chmod -R 0770 /var/log/mysqld ; chown -R mysql:mysql /var/log/mysqld ; }

#
# Set server hostname
#

hostname="`cat /etc/csync2/tmp_slave_hostname`";
if [ "$hostname" != "" ]; then 
	echo ${hostname} > /etc/hostname
	hostname ${hostname}
fi

rm -f /etc/csync2/tmp_slave_hostname
mv -f /etc/csync2/tmp_hosts /etc/hosts

echo 
echo "Add temporary iptables rules"

test -z "`iptables -L | grep 'Chain BX_CLUSTER'`" && iptables -N BX_CLUSTER || iptables -F BX_CLUSTER
test -z "`iptables -L INPUT | grep 'BX_CLUSTER'`" && iptables -I INPUT -j BX_CLUSTER
iptables -A BX_CLUSTER -p tcp --dport 30865 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 3306 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 11211 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 8889 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 80 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 443 -j ACCEPT

service memcached restart

#
# Grant priv
#

echo 
echo "Add mysql user access"
chmod +x /etc/csync2/tmp_mysql.sh
/etc/csync2/tmp_mysql.sh
rm -f /etc/csync2/tmp_mysql.sh


#
# Start and rebuild csync2
#

chown -R bitrix:root /var/lib/csync2
chmod -R 0770 /var/lib/csync2
chown root:bitrix /etc/csync2/csync2.cluster.key
chmod 0640 /etc/csync2/csync2.cluster.key
chown root:bitrix /etc/csync2/csync2_ssl_cert.pem
chmod 0640 /etc/csync2/csync2_ssl_cert.pem
chown root:bitrix /etc/csync2/csync2_ssl_key.pem
chmod 0640 /etc/csync2/csync2_ssl_key.pem

sed -i '/^[\t ]*disable/d' /etc/xinetd.d/csync2
service xinetd restart
chkconfig xinetd on

test -f /home/bitrix/tmp_add_slave_backup.tar.gz && { rm -f /home/bitrix/tmp_add_slave_backup.tar.gz ; }
