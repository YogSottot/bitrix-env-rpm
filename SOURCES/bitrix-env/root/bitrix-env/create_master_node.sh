#!/bin/bash

echo
echo "Before creating a cluster, you must install the Bitrix product."
echo
echo
read -p "Yes, I have already installed CMS Bitrix [ y/N ]: " isInstalled
echo
echo

if [ "$isInstalled" = "y" -o "$isInstalled" = "Y" ]; then
	echo
	echo "Start creating master node"
else
	exit;
fi



modOk=`php -f /root/bitrix-env/check_cluster_module.php`

if [ "$modOk" != "" ]; then
	echo
	echo "Bitrix web cluster module is not installed."
	echo
	echo "$modOk"
	echo
	read "Press any key" key
	exit
fi

#
# Chech memory size
#

if [ -f /proc/user_beancounters ] ; then
        is_vps=1
        if [ `free | grep Mem | awk '{print $2}'` -gt 500000 ]; then
                mem4kblock=`cat /proc/user_beancounters |grep vmguarpages|awk '{print $4}'`
                mem4kblock2=`cat /proc/user_beancounters |grep privvmpages|awk '{print $4}'`
                [ ${mem4kblock2} -gt ${mem4kblock} ] && memory=`echo "${mem4kblock} * 4"|bc` || memory=`echo "${mem4kblock2} * 4"|bc`
        else
                 memory=`free | grep Mem | awk '{print $2}'`
        fi
else
        is_vps=0
        memory=`free | grep Mem | awk '{print $2}'`
fi

#if [ $memory -lt 1000000 ]; then
if [ $memory -lt 500000 ]; then
	echo
	echo "Not enough memory to work in a cluster. Requires 512 MB of RAM or more.";
	read "Press any key: " key
	exit
fi

#
# Check node in cluster
#

isCluster="NO"
for node in $(ls /etc/bx_cluster/nodes)
do
	isCluster="YES"
done

if [ "$isCluster" = "YES" ]; then
	echo
	echo "Node already in the cluster.";
	read "Press any key: " key
	exit
fi

ipCnt=0;
for ip_ in $(ifconfig | grep Bcast | grep -v 127.0.0.1 | awk '{print $2}' | sed 's/addr://')
do
	ipList[${ipCnt}]="$ip_"
	let "ipCnt++";
done

hostname_=`hostname`

echo "======================================================="
echo "	         Create master node for cluster"
echo "======================================================="
echo

read -p "Hostname (examle www1.bxcluster) [$hostname_]: " hostname
if [ "$hostname" = "" ]; then hostname=$hostname_ ; fi

if [ $ipCnt -eq 1 ]; then
	ip="${ipList[0]}"
else
	endRead="N"
	while [ "$endRead" = "N" ]
	do
		echo
		i=0;
		while [ $i -lt $ipCnt ]
		do
			echo "$i - ${ipList[$i]}"
			let "i++"
		done

		echo

		read -p "Select IP address: " ipNum
		if [ "${ipList[$ipNum]}" != "" ]; then
			endRead="Y"
			ip="${ipList[$ipNum]}"
		else
			echo "Incorrect choice"
			echo
		fi
	done
fi

endRead="N"
while [ "$endRead" = "N" ]
do
	echo
	echo
	read -s -p "Current mysql root password: " currentMysqlPasswd
	if [ "$currentMysqlPasswd" = "" ]; then
		res=`mysql -e "show databases;" | grep -v Database`
	else
		res=`mysql -p"$currentMysqlPasswd" -e "show databases;" | grep -v Database`
	fi

	dbCnt=0
	echo

	for db in $(echo "$res")
	do
		if [ "$db" != 'mysql' -a "$db" != "information_schema" ]; then
			dbList[$dbCnt]="$db"
			echo "$dbCnt - ${dbList[$dbCnt]}"
			let "dbCnt++"
		fi
	done


	if [ $dbCnt -eq 1 ]; then
		dbName="${dbList[0]}"
		endRead="Y"
	else
		read -p "Select database: " dbNum
		if [ "${dbList[$dbNum]}" != "" ]; then
			endRead="Y"
			dbName="${dbList[$dbNum]}"
		else
			echo "Incorect chouse"
			echo
		fi
	fi
done

echo
read -p "Change mysql root password? [ y/N ]: " chPasswd

if [ "$chPasswd" = 'Y' -o "$chPasswd" = 'y' ]; then
	read -s -p "New mysql root password: " mysqlPasswd
	echo
fi

echo "======================================================="
echo "	         Current master node parameters"
echo "======================================================="
echo Hostname: ${hostname}
echo IP: ${ip}
echo Database name: ${dbName}
echo "======================================================="
echo
read -p "Save changes? [ y/N ]: " save
if [ "$save" != "y" -a "$save" != "Y" ]; then
	echo "You have canceled adding a slave node to cluster"
	read "Press any key" key
	exit
fi


dbOk=`php -f /root/bitrix-env/check_master_node.php`

if [ "$dbOk" != "" ]; then
	echo
	echo "Database configuration has some errors, they must be fixed."
	echo
	echo "$dbOk"
	echo
	read "Press any key" key
	exit
fi

chown bitrix:bitrix /home/bitrix/www/bitrix/php_interface/dbconn.php
chown -R bitrix:bitrix /home/bitrix/www/bitrix/modules/cluster


test -d "/etc/bx_cluster/nodes" && { rm -fr /etc/bx_cluster/nodes ; }
mkdir -p /etc/bx_cluster
mkdir -p /etc/bx_cluster/nodes
echo ${ip} > /etc/bx_cluster/nodes/${hostname};

ln -sf /etc/bx_cluster/nodes/${hostname} /etc/bx_cluster/current.node
ln -sf /etc/bx_cluster/nodes/${hostname} /etc/bx_cluster/master.node

echo ${dbName} > /etc/bx_cluster/dbName.conf
echo ${hostname}"=1" > /etc/bx_cluster/mysql_cluster_nodes.conf
test ! -d /var/log/mysqld && { mkdir -p /var/log/mysqld ; chmod -R 0770 /var/log/mysqld ; chown -R mysql:mysql /var/log/mysqld ; }

arNodeList=
arNodeIpList=
nodeCnt=0;
masterNodeIp=`cat /etc/bx_cluster/master.node`;
currentNodeIp=`cat /etc/bx_cluster/current.node`;
dbName=`cat /etc/bx_cluster/dbName.conf`;
masterNode=
currentNode=
mysqlServerID=

#
# Read bx_cluster config
#

for node in $(ls /etc/bx_cluster/nodes)
do
	arNodeList[$nodeCnt]=$node;
	arNodeIpList[${nodeCnt}]=`cat /etc/bx_cluster/nodes/${node}`;
	if [ ${arNodeIpList[$nodeCnt]} = ${currentNodeIp} ]; then currentNode=$node; fi
	if [ ${arNodeIpList[$nodeCnt]} = ${masterNodeIp} ]; then masterNode=$node; fi
	mysqlServerID[$nodeCnt]=`cat /etc/bx_cluster/mysql_cluster_nodes.conf | grep ${node} |sed "s/${node}\=//g" `;
	let "nodeCnt++";
	isCluster="YES"
done

#
# Add info about cluster nodes to /etc/hosts
#
i=0;
while [ $i -lt $nodeCnt ]
do
	nodeDesc=${arNodeIpList[$i]}" "${arNodeList[$i]};
	test -z "`grep -e "${nodeDesc}\$" /etc/hosts`" &&  echo ${nodeDesc} >> /etc/hosts;
	let "i++";
done

#
# Add info about hostname
#
echo ${currentNode} > /etc/hostname
hostname ${currentNode}

#
# Add firewall rulles
#
test -z "`iptables -L | grep 'Chain BX_CLUSTER'`" && iptables -N BX_CLUSTER || iptables -F BX_CLUSTER;
test -z "`iptables -L INPUT | grep 'BX_CLUSTER'`" && iptables -I INPUT -j BX_CLUSTER;
iptables -A BX_CLUSTER -i lo -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 80 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 443 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 25 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 5222 -j ACCEPT
iptables -A BX_CLUSTER -p tcp --dport 5223 -j ACCEPT
i=0;
while [ $i -lt $nodeCnt ]
do
	iptables -A BX_CLUSTER -p tcp -d ${currentNodeIp} -s ${arNodeIpList[$i]} --dport 3306 -j ACCEPT
	iptables -A BX_CLUSTER -p tcp -d ${currentNodeIp} -s ${arNodeIpList[$i]} --dport 11211 -j ACCEPT
	iptables -A BX_CLUSTER -p tcp -d ${currentNodeIp} -s ${arNodeIpList[$i]} --dport 30865 -j ACCEPT
	iptables -A BX_CLUSTER -p tcp -d ${currentNodeIp} -s ${arNodeIpList[$i]} --dport 8889 -j ACCEPT
	let "i++";
done
iptables -A BX_CLUSTER -p tcp --dport 3306 -j DROP
iptables -A BX_CLUSTER -p tcp --dport 11211 -j DROP
iptables -A BX_CLUSTER -p tcp --dport 30865 -j DROP
iptables -A BX_CLUSTER -p tcp --dport 8889 -j DROP
service iptables save

#
# Start memcached
#

chkconfig memcached on
service memcached restart

#Add mysql master

if [ `mysql -V | grep "Distrib 5.0" | wc -l` -eq 0 ]; then binlogFormat="binlog_format=mixed" ; else binlogFormat="" ; fi

echo "
[mysqld]
${binlogFormat}
bind-address = 0.0.0.0
innodb_flush_log_at_trx_commit = 1
binlog-do-db=${dbName}
server-id=1
binlog_cache_size = 4M
max_binlog_size = 512M
log-bin = /var/log/mysqld/bx_cluster_${dbName}_bin.log
log-bin-index = /var/log/mysqld/bx_cluster_log_${dbName}_bin.index" > /etc/mysql/conf.d/bx_node.cnf;
service mysqld restart

identif="";
pwd="$currentMysqlPasswd";
if [ "$mysqlPasswd" != "" ]; then
    identif="IDENTIFIED BY '${mysqlPasswd}'" ;
    pwd=${mysqlPasswd};
fi

test -z "$currentMysqlPasswd" &&
{
	mysql -u root  -e "GRANT SUPER, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'root'@'%' ${identif};";
	mysql -u root  -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' ${identif}; GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' ${identif};";
	echo '<? $masterHost="'"${hostname}"'"; $dbHost="'"${hostname}"'"; $dbName="'"${dbName}"'"; $dbPasswd="'"${pwd}"'"; ?>' > /root/bitrix-env/tmp/db_connect.php
	dbOk=`php -f /root/bitrix-env/set_master_node_db_conn.php`
} || {
	mysql -u root -p${currentMysqlPasswd} -e "GRANT SUPER, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'root'@'%' ${identif};";
	mysql -u root -p${currentMysqlPasswd} -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' ${identif}; GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' ${identif};";
	echo '<? $masterHost="'"${hostname}"'"; $dbHost="'"${hostname}"'"; $dbName="'"${dbName}"'"; $dbPasswd="'"${pwd}"'"; ?>' > /root/bitrix-env/tmp/db_connect.php
	dbOk=`php -f /root/bitrix-env/set_master_node_db_conn.php`
}

# Add apache mod_status config for apache
i=0;
allowList=
while [ $i -lt $nodeCnt ]
do
	allowList=${allowList}"Allow from ${arNodeIpList[$i]}
";
	let "i++";
done

echo "<IfModule mod_status.c>
    ExtendedStatus On
    <Location /server-status>
	SetHandler server-status
        Order Deny,Allow
        Deny from All
        Allow from 127.0.0.1
        ${allowList}
    </Location>
</IfModule>" > /etc/httpd/bx/conf/bx_status.conf;

#Add nginx conf
i=0;
allowList=
bxClusterServer=
while [ $i -lt $nodeCnt ]
do
	node_="${arNodeList[$i]}"
	if [ "$node_" = "$masterNode" ]; then node_="127.0.0.1:8889"; fi
		bxClusterServer="$bxClusterServer""server $node_;
";
	let "i++";
done

echo "upstream bx_cluster {
	ip_hash;

	${bxClusterServer}
}" > /etc/nginx/bx/site_avaliable/upstream.conf;

test -d /etc/bx_cluster/site_enabled && { rm -rf /etc/bx_cluster/site_enabled ; mkdir -p /etc/bx_cluster/site_enabled ; }

#Add symlink for nginx
ln -sf /etc/nginx/bx/site_avaliable/balancer.conf /etc/nginx/bx/site_enabled
ln -sf /etc/nginx/bx/site_avaliable/ssl.balancer.conf /etc/nginx/bx/site_enabled
ln -sf /etc/nginx/bx/site_avaliable/upstream.conf /etc/nginx/bx/site_enabled
ln -sf /etc/nginx/bx/site_avaliable/cluster_s1.conf /etc/nginx/bx/site_enabled
ln -sf /etc/nginx/bx/conf/master_node_port.conf /etc/nginx/bx/node_port.conf
echo "server_name "${hostname}";" > /etc/nginx/bx/node_host.conf

#
# Add csync2 config for site_files
#

csync2 -k /etc/csync2/csync2.cluster.key
chown root:bitrix /etc/csync2/csync2.cluster.key
chmod 0640 /etc/csync2/csync2.cluster.key
chown root:bitrix /etc/csync2/csync2_ssl_cert.pem
chmod 0640 /etc/csync2/csync2_ssl_cert.pem
chown root:bitrix /etc/csync2/csync2_ssl_key.pem
chmod 0640 /etc/csync2/csync2_ssl_key.pem


echo "group bx_cluster_www {
	host ${arNodeList[@]};
	key /etc/csync2/csync2.cluster.key;
	include /home/bitrix/www;
	exclude /home/bitrix/www/bitrix/cache;
	exclude /home/bitrix/www/bitrix/managed_cache;
	exclude /home/bitrix/www/bitrix/stack_cache;
	exclude /home/bitrix/www/bitrix/modules/xmppd.log;
	exclude /home/bitrix/www/bitrix/modules/smtpd.log;
	include /home/bitrix/.msmtprc;
	auto younger;
}" > /etc/csync2/csync2_bxwww.cfg

#
# Add csync2 config for conf
#
echo "group bx_cluster_conf {
	host ${arNodeList[@]};
	key /etc/csync2/csync2.cluster.key;
	include /etc/csync2;
	exclude /etc/csync2/tmp_slave_hostname;
	exclude /etc/csync2/tmp_hosts;
	exclude /etc/csync2/csync2.cluster.key;
	exclude /etc/csync2/csync2_ssl_cert.pem;
	exclude /etc/csync2/csync2_ssl_key.pem;
	include /etc/nginx/bx/conf;
	include /etc/nginx/bx/site_avaliable;
	include /etc/nginx/bx/site_enabled;
	exclude /etc/nginx/bx/site_enabled/balancer.conf;
	exclude /etc/nginx/bx/site_enabled/ssl.balancer.conf;
	exclude /etc/nginx/bx/site_enabled/upstream.conf;
	include /etc/httpd/bx/conf/bx_status.conf;
	include /etc/bx_cluster;
	exclude /etc/bx_cluster/current.node;
	exclude /etc/bx_cluster/tmp_slave_hostname;
	exclude /etc/bx_cluster/tmp_hosts;
	exclude /etc/bx_cluster/tmp_mysql.sh;
	exclude /etc/bx_cluster/change_master;

	action
	{
		pattern /etc/csync2/*;
		pattern /etc/bx_cluster/*;
		pattern /etc/nginx/bx/*;
		exec "/root/bitrix-env/conf_node.sh";
		logfile "/var/log/csync2_bxconf.log";
	}

	auto first;
}" > /etc/csync2/csync2_bxconf.cfg

#
# Start and rebuild csync2
#

chown -R bitrix:root /var/lib/csync2
chmod -R 0770 /var/lib/csync2

test -f /var/lib/csync2/${hostname}_bxconf.db && { rm -f /var/lib/csync2/${hostname}_bxconf.db ; }
test -f /var/lib/csync2/${hostname}_bxwww.db && { rm -f /var/lib/csync2/${hostname}_bxwww.db ; }

sed -i '/^[\t ]*disable/d' /etc/xinetd.d/csync2
service xinetd restart
chkconfig xinetd on
service httpd restart
service nginx restart

test -f /home/bitrix/www/bitrix/php_interface/after_connect.php && { mv -f /home/bitrix/www/bitrix/php_interface/after_connect.php /home/bitrix/www/bitrix/php_interface/after_connect.backup.php ; }

echo
echo "Create csync2 database of config files"
csync2 -x -C bxconf

echo
echo "Create csync2 database of site files"
sudo -u bitrix csync2 -cIr -C bxwww / > /dev/null &
P=${!}
while [ `ps -p $P h|wc -l` -ne '0' ]; do
	echo -ne "."
	sleep 1
done
echo

sudo -u bitrix csync2 -u -C bxwww > /dev/null &
P=${!}
while [ `ps -p $P h|wc -l` -ne '0' ]; do
	echo -ne "."
	sleep 1
done
echo


echo
echo "Add csync2 to cron on master node"
test -z "`cat /etc/crontab | grep csync2`" && echo "*/5 * * * * bitrix csync2 -cr -C bxwww / csync2 -u -C bxwww
" >> /etc/crontab;


echo
echo "Confirm .htaccess settings"
rule=`cat /home/bitrix/www/.htaccess | grep !/server-status`
test -z "$rule" && { sed -i '/\!\/bitrix\/urlrewrite\.php\$/ a\  RewriteCond \%\{REQUEST_URI\} \!\/server-status\$' /home/bitrix/www/.htaccess ; }

echo '<? $dbHost="'"${hostname}"'"; ?>' > /root/bitrix-env/tmp/db_connect.php
echo
echo "Adding memcache and web server to Bitrix"
echo

php -f /root/bitrix-env/add_master_node.php
chown bitrix:bitrix /home/bitrix/www/bitrix/php_interface/dbconn.php
chown -R bitrix:bitrix /home/bitrix/www/bitrix/modules/cluster
rm -f /root/bitrix-env/tmp/db_connect.php

echo "======================================================="
echo "               Master node configured"
echo "======================================================="
echo

read -p "Finished. Add slave node [ y/N ]: " ok

if [ "$ok" = "y" ]; then /root/bitrix-env/add_slave_node.sh ; fi
