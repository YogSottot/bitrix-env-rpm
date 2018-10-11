#!/bin/bash

masterNodeIp=`cat /etc/bx_cluster/master.node`;
currentNodeIp=`cat /etc/bx_cluster/current.node`;
dbName=`cat /etc/bx_cluster/dbName.conf`;
hostname=`hostname`

if [ "$masterNodeIp" = "" ]; then
	echo
	echo "Incorrect cluster configuration, check /etc/bx_cluster/master.node"
	read "Press any key" key
	exit
fi

if [ "$currentNodeIp" = "" ]; then
	echo
	echo "Incorrect cluster configuration, check /etc/bx_cluster/current.node"
	read "Press any key" key
	exit
fi

if [ "$dbName" = "" ]; then
	echo
	echo "Incorrect cluster configuration, check /etc/bx_cluster/dbName.conf"
	read "Press any key" key
	exit
fi

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
	read "Press any key" key
	exit
fi

#
# Can change master node only on slave node
#

if [ "$masterNodeIp" = "$currentNodeIp" ]; then
	echo
	echo "Change master node you can do from the slave node";
	read "Press any key" key
	exit
fi

echo
echo "Before change master, you must stop old master node."
echo
echo
read -p "Yes, I have already stoped master node [ y/N ]: " isInstalled
echo
echo

if [ "$isInstalled" = "y" -o "$isInstalled" = "Y" ]; then
	echo
	echo "Start changed master node"
else
	exit;
fi

echo "======================================================="
echo "	          Change master node in cluster"
echo "======================================================="
echo

#
# Remove old master from config
#

echo
echo "Remove old master server from cluster config"

nodeCnt=0;
for node in $(ls /etc/bx_cluster/nodes)
do
	nip=`cat /etc/bx_cluster/nodes/${node}`;
	if [ "$nip" = "$masterNodeIp" ]; then
		masterOldNode="$node"
		rm -f /etc/bx_cluster/nodes/${node}
	fi

	if [ "$nip" = "$currentNodeIp" ]; then
		masterNode=$node;
		currentNode=$node;
		rm -f /etc/bx_cluster/master.node
		ln -sf /etc/bx_cluster/nodes/${masterNode} /etc/bx_cluster/master.node
	fi
	let "nodeCnt++";
done

masterNodeIp="$currentNodeIp"

#
# Change mysql server id list
#

echo "$masterNode=1" > /etc/bx_cluster/mysql_cluster_nodes.conf

mysqlSID=2;
nodeCnt=0;
for node in $(ls /etc/bx_cluster/nodes)
do
	if [ "$node" != "$masterNode" ]; then
		echo "$node=$mysqlSID" >> /etc/bx_cluster/mysql_cluster_nodes.conf ;
		let "mysqlSID++" ;
	fi
done


#
# Read information about cluster
#

echo
echo "Read information about new cluster confuguration"

nodeCnt=0;
serverID=0;
for node in $(ls /etc/bx_cluster/nodes)
do
	arNodeList[$nodeCnt]=$node;
	arNodeIpList[${nodeCnt}]=`cat /etc/bx_cluster/nodes/${node}`;
	if [ "$arNodeIpList[$nodeCnt]" = "$currentNodeIp" ]; then currentNode=$node; fi
	if [ "$arNodeIpList[$nodeCnt]" = "$masterNodeIp" ]; then masterNode=$node; fi
	tmpNodeCnt=`cat /etc/bx_cluster/mysql_cluster_nodes.conf | grep ${node} |sed "s/${node}\=//g" `;
	mysqlServerID[$nodeCnt]=$tmpNodeCnt;
	tmpSID=$tmpNodeCnt;
	if [ $serverID -lt $tmpSID ]; then serverID=$tmpSID ; fi
	let "nodeCnt++";

done

#
# MySQL nodes passwd
#

echo
echo "Input mysql root password from all nodes"
echo

mysqlPasswdList=
i=0;
while [ $i -lt $nodeCnt ]
do
	endRead="N"
	while [ "$endRead" = "N" ]
	do
		echo
		read -s -p "MySQL root password from node - ${arNodeList[$i]} (${arNodeIpList[$i]}): " tmpPasswd
		if [ "$tmpPasswd" = "" ]; then
			res=`mysql -h "${arNodeIpList[$i]}" -e "use $dbName; show tables;" | grep Tables_in_"$dbName"`
		else
			res=`mysql -h "${arNodeIpList[$i]}" -p"$tmpPasswd" -e "use $dbName; show tables;" | grep Tables_in_"$dbName"`
		fi

		if [ "$res" = "" ]; then
			echo "Check mysql database root password for node ${arNodeList[$i]} (${arNodeIpList[$i]})."
			echo
			echo "Try, again."
			echo
		else
			echo
			echo "Mysql root password correct"
			echo
			mysqlPasswdList[$i]=$tmpPasswd
			if [ "$arNodeIpList[$nodeCnt]" = "$masterNodeIp" ]; then $masterNodePassword=$tmpPasswd; fi
			endRead="Y"
		fi
	done
	let "i++";
done

#
# Stop replication on slave nodes
#

echo
echo "Stop replication on all slave nodes"

i=0;
while [ $i -lt $nodeCnt ]
do

	echo
	echo "Stop replication on node ${arNodeList[$i]} (${arNodeIpList[$i]})"

	if [ "${mysqlPasswdList[$i]}" = "" ]; then
		passwdStr=""
	else
		passwdStr="-p${mysqlPasswdList[$i]}"
	fi

	res=`mysql -h "${arNodeIpList[$i]}" "$passwdStr" -e "STOP SLAVE IO_THREAD;" | grep Tables_in_"$dbName"`

	isStoped="N"
	while [ "$isStoped" = "N" ]
	do
		echo -ne "."
		res=`mysql -h "${arNodeIpList[$i]}" "$passwdStr" -e "show slave status\G"`
		rrow=`echo "$res" | grep Read_Master_Log_Pos | awk '{print $2}'`
		erow=`echo "$res" | grep Exec_Master_Log_Pos | awk '{print $2}'`
		if [ $rrow -eq $erow ]; then
			isStoped="Y"
			res=`mysql -h "${arNodeIpList[$i]}" "$passwdStr" -e "STOP SLAVE; RESET SLAVE; RESET MASTER;"`
		else
			sleep 5
		fi
	done
	echo
	let "i++"
done


#
# Configure slave node as master
#

echo
echo "Configuring master node"

service memcached restart

echo
echo "Configuring master mysql server"

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

echo
echo "Configuring apache server"

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

echo
echo "Configuring nginx server"

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

service xinetd restart

echo
echo "Create csync2 database of config files"
csync2 -cr -C bxconf /
csync2 -mr /etc/bx_cluster/nodes -C bxconf
csync2 -m /etc/bx_cluster/nodes/${masterOldNode} -C bxconf
csync2 -m /etc/bx_cluster/dbName.conf -C bxconf
csync2 -m /etc/bx_cluster/master.node -C bxconf
csync2 -mr /etc/nginx/bx/site_avaliable -C bxconf
csync2 -mr /etc/nginx/bx/site_enabled -C bxconf
csync2 -u -C bxconf

# Reconfigure memcache list in cluster config
i=0;
memcacheList=""

while [ $i -lt $nodeCnt ]
do
	if [ $i -gt 0 ]; then
		memcacheList="$memcacheList, "
	fi
	memcacheList="$memcacheList\"${arNodeList[$i]}\""
	let "i++"
done

echo "<? \$memcacheList=array("$memcacheList"); ?>" > /root/bitrix-env/tmp/memcache_node_list.php
test -f /home/bitrix/www/bitrix/modules/cluster/memcache.php && { rm -f /home/bitrix/www/bitrix/modules/cluster/memcache.php ; }
echo '<? $masterHost="'"${masterNode}"'"; $dbHost="'"${hostname}"'"; $dbName="'"${dbName}"'"; $dbPasswd="'"${pwd}"'"; ?>' > /root/bitrix-env/tmp/db_connect.php
resetCluster=`php -f /root/bitrix-env/before_check_slave.php`
php -f /root/bitrix-env/change_master_node.php
rm -f /root/bitrix-env/tmp/db_connect.php
rm -f /root/bitrix-env/tmp/memcache_node_list.php

chown bitrix:bitrix /home/bitrix/www/bitrix/php_interface/dbconn.php
chown -R bitrix:bitrix /home/bitrix/www/bitrix/modules/cluster

echo
echo "Create csync2 database of site files"
sudo -u bitrix csync2 -cIr -C bxwww / > /dev/null &
P=${!}
while [ `ps -p $P h|wc -l` -ne '0' ]; do
	echo -ne "."
	sleep 1
done
echo

csync2 -m /home/bitrix/www/bitrix/php_interface/dbconn.php -C bxwww

sudo -u bitrix csync2 -u -C bxwww > /dev/null &
P=${!}
while [ `ps -p $P h|wc -l` -ne '0' ]; do
	echo -ne "."
	sleep 1
done
echo


#
# Stop replication on slave nodes
#

echo
echo "Swith slave node to new master cluster"

i=0;
while [ $i -lt $nodeCnt ]
do

	if [ "${arNodeList[$i]}" != "$masterNode" ]; then
		echo
		echo "Swith slave node ${arNodeList[$i]} (${arNodeIpList[$i]}) to new master"

		if [ "${mysqlPasswdList[$i]}" = "" ]; then
			passwdStr=""
		else
			passwdStr="-p${mysqlPasswdList[$i]}"
		fi




		echo -ne "."
		res=`mysql -h "${arNodeIpList[$i]}" "$passwdStr" -e "CHANGE MASTER TO MASTER_HOST='$masterNodeIp', MASTER_USER='root', MASTER_PASSWORD='$masterNodePassword'; START SLAVE;"`
	fi
	let "i++"
done

service httpd restart
service nginx restart