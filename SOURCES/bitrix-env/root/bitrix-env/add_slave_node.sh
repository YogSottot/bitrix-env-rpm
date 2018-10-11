#!/bin/bash

masterNodeIp=`cat /etc/bx_cluster/master.node`;
currentNodeIp=`cat /etc/bx_cluster/current.node`;
dbName=`cat /etc/bx_cluster/dbName.conf`;

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
# Can add slave node only on master node
#

if [ "$masterNodeIp" != "$currentNodeIp" ]; then
	echo
	echo "A slave node can be added to the cluster from the master node ($masterNode)";
	read "Press any key" key
	exit
fi


echo "======================================================="
echo "	           Add slave node for cluster"
echo "======================================================="
echo

endRead="N"
while [ "$endRead" = "N" ]
do
	read -p "Hostname (examle www2.bxcluster): " hostname
	if [ "$hostname" = "" -o "$hostname" = "localhost" ]; then
		echo "Incorrect hostname, try again"
		echo
	else
		echo
		endRead="Y"
	fi
done

endRead="N"
while [ "$endRead" = "N" ]
do
	read -p "IP: " ip
	read -s -p "Slave node root password: " rootPasswd
	#
	# Check unique hostname and ip
	#

	correctNode="Y"
	for node in $(ls /etc/bx_cluster/nodes)
	do
		nodeIp=`cat /etc/bx_cluster/nodes/${node}`;
		if [ $ip = $nodeIp -o $hostname = $node ]; then correctNode='N'; fi
		let "nodeCnt++";
	done

	if [ "$correctNode" != "Y" ]; then
		echo
		echo "Slave ip or hostname cant be same as any other node ip or hostname in cluster"
		echo
	else
		echo '#!/usr/bin/expect
			spawn /usr/bin/ssh -l root '"$ip"' uname -a
			expect {
			-re ".*Are.*.*yes.*no.*" {
				send "yes\r"
				exp_continue
			}
			"*assword:*" { send '"$rootPasswd"'\r\n; interact }
			eof { exit }
		}
		exit' > /root/bitrix-env/tmp/ssh2.sh
		chmod +x /root/bitrix-env/tmp/ssh2.sh
		checkPasswd=`/root/bitrix-env/tmp/ssh2.sh | grep Linux`
		rm -f /root/bitrix-env/tmp/ssh2.sh

		if [ "$checkPasswd" = "" ]; then
			echo "Incorrect ip or root password. Try again"
			echo
		else
			echo "Ip and password is correct"
			endRead="Y"
		fi
	fi
done

endRead="N"
while [ "$endRead" = "N" ]
do
	echo
	read -s -p "Current mysql slave node root password: " currentMysqlPasswd

	if [ "${currentMysqlPasswd}" = "" ]; then
		authLine=""
	else
		authLine="-p${currentMysqlPasswd}"
	fi

	echo '#!/usr/bin/expect
		spawn /usr/bin/ssh -l root '"$ip"' mysql -u root '"$authLine"' < /root/bitrix-env/show_databases.sql
		expect {
		-re ".*Are.*.*yes.*no.*" {
			send "yes\r"
			exp_continue
		}
		"*assword:*" { send '"$rootPasswd"'\r\n; interact }
		eof { exit }
	}
	exit' > /root/bitrix-env/tmp/ssh3.sh
	chmod +x /root/bitrix-env/tmp/ssh3.sh
	checkDBConnect=`/root/bitrix-env/tmp/ssh3.sh | grep Database`

	rm -f /root/bitrix-env/tmp/ssh3.sh

	if [ "$checkDBConnect" = "" ]; then
		echo
		echo "Incorrect ip or slave node mysql root password. Try again"
		echo
	else
		echo
		echo "Ip and slave node mysql root password is correct"
		endRead="Y"
	fi
done

echo
read -p "Change mysql root password? [ y/N ]: " chPasswd

if [ "$chPasswd" = 'Y' -o "$chPasswd" = 'y' ]; then
	read -s -p "New mysql root password: " mysqlPasswd
fi

endRead="N"
while [ "$endRead" = "N" ]
do
	echo
	read -s -p "Master mysql root password: " mysqlMasterPasswd
	if [ "$mysqlMasterPasswd" = "" ]; then
		res=`mysql -h "$masterNodeIp" -e "use $dbName; show tables;" | grep Tables_in_"$dbName"`
	else
		res=`mysql -h "$masterNodeIp" -p"$mysqlMasterPasswd" -e "use $dbName; show tables;" | grep Tables_in_"$dbName"`
	fi

	if [ "$res" = "" ]; then
		echo "Check master database root password."
		echo
		echo "Try, again."
		echo
	else
		echo
		echo "Mysql master root password correct"
		echo
		endRead="Y"
	fi
done


echo
echo "======================================================="
echo "	         Current slave node parameters"
echo "======================================================="
echo Hostname: ${hostname}
echo IP: ${ip}
echo "======================================================="
echo

read -p "Save changes? [ y/N ]: " save

arNodeList=
arNodeIpList=
nodeCnt=0;
masterNode=
currentNode=
mysqlServerID=

declare -i serverID=1;
declare -i tmpSID=0;

nodeCnt=0;
for node in $(ls /etc/bx_cluster/nodes)
do
	nip=`cat /etc/bx_cluster/nodes/${node}`;
	if [ "$nip" = "$masterNodeIp" ]; then
		masterNode=$node;
		rm -f /etc/bx_cluster/master.node
		ln -sf /etc/bx_cluster/nodes/${masterNode} /etc/bx_cluster/master.node
	fi
	let "nodeCnt++";
done

if [ "$save" != "y" -a "$save" != "Y" ]; then
	echo
	echo "You have canceled adding a slave node to the cluster"
	read "Press any key" key
	exit
fi

echo
echo "Start adding slave node to cluster"

echo
echo "Clean /etc/bx_cluster/nodes on slave node"
echo '#!/usr/bin/expect
	spawn /usr/bin/ssh -l root '"$ip"' /root/bitrix-env/clean_slave_node.sh
	expect {
		-re ".*Are.*.*yes.*no.*" {
		send "yes\r"
		exp_continue
	}
	"*assword:*" { send '"$rootPasswd"'\r\n; interact }
	eof { exit }
}
exit' > /root/bitrix-env/tmp/ssh3.sh
chmod +x /root/bitrix-env/tmp/ssh3.sh
/root/bitrix-env/tmp/ssh3.sh
rm -f /root/bitrix-env/tmp/ssh3.sh

echo
echo "Add info about slave node"
echo ${ip} > /etc/bx_cluster/nodes/${hostname};

#
# Read bx_cluster config
#

nodeCnt=0;
for node in $(ls /etc/bx_cluster/nodes)
do
	arNodeList[$nodeCnt]=$node;
	arNodeIpList[${nodeCnt}]=`cat /etc/bx_cluster/nodes/${node}`;
	if [ "$arNodeIpList[$nodeCnt]" = "$currentNodeIp" ]; then currentNode=$node; fi
	if [ "$arNodeIpList[$nodeCnt]" = "$masterNodeIp" ]; then masterNode=$node; fi
	tmpNodeCnt=`cat /etc/bx_cluster/mysql_cluster_nodes.conf | grep ${node} |sed "s/${node}\=//g" `;
	mysqlServerID[$nodeCnt]=$tmpNodeCnt;
	tmpSID=$tmpNodeCnt;
	if [ $serverID -lt $tmpSID ]; then serverID=$tmpSID; fi
	let "nodeCnt++";
done

let "serverID++";
echo ${hostname}"="${serverID} >> /etc/bx_cluster/mysql_cluster_nodes.conf

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
# Add firewall rulles
#

echo
echo "Update firewall rules on master server"

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
	echo
	echo "Add custom rules for ${arNodeList[$i]} (${arNodeIpList[$i]})"
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

service httpd restart


#Add nginx conf
i=0;
allowList=
bxClusterServer=
while [ $i -lt $nodeCnt ]
do
	node_=${arNodeList[$i]}
	if [ "$node_" = "$masterNode" ]; then node_="127.0.0.1:8889" ; fi
	bxClusterServer=${bxClusterServer}"server $node_;
";
	let "i++";
done

echo "upstream bx_cluster {
	ip_hash;
	${bxClusterServer}
}" > /etc/nginx/bx/site_avaliable/upstream.conf;

#
# Add csync2 config for site_files
#

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
	exclude /etc/csync2/csync2.cluster.key;
	exclude /etc/csync2/tmp_slave_hostname;
	exclude /etc/csync2/tmp_hosts;
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
# Copy some files to slave node
#

echo ${hostname} > /etc/csync2/tmp_slave_hostname

#
# Add db user
#

identif="";
pwd="";
if [ "$currentMysqlPasswd" != "" ]; then identif="IDENTIFIED BY '""${currentMysqlPasswd}""'"; pwd="$currentMysqlPasswd"; fi
if [ "$mysqlPasswd" != "" ]; then identif="IDENTIFIED BY '""${mysqlPasswd}""'"; pwd="$mysqlPasswd"; fi

test -z "$currentMysqlPasswd" && {
	echo '#!/bin/bash
	mysql -u root -e "GRANT SUPER, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '"'"'root'"'"'@'"'"'%'"'"' '"$identif"'; GRANT SUPER, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '"'"'root'"'"'@'"'"'localhost'"'"' '"$identif"'; GRANT ALL PRIVILEGES ON *.* TO '"'"'root'"'"'@'"'"'%'"'"' '"$identif"'; GRANT ALL PRIVILEGES ON *.* TO '"'"'root'"'"'@'"'"'localhost'"'"' '"$identif"';"' > /etc/csync2/tmp_mysql.sh;
} || {
	echo '#!/bin/bash
	mysql -u root -p'"${currentMysqlPasswd}"' -e "GRANT SUPER, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '"'"'root'"'"'@'"'"'%'"'"' '"$identif"'; GRANT SUPER, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '"'"'root'"'"'@'"'"'localhost'"'"' '"$identif"'; GRANT ALL PRIVILEGES ON *.* TO '"'"'root'"'"'@'"'"'%'"'"' '"$identif"'; GRANT ALL PRIVILEGES ON *.* TO '"'"'root'"'"'@'"'"'localhost'"'"' '"$identif"';"' > /etc/csync2/tmp_mysql.sh;
}

cp -f /etc/hosts /etc/csync2/tmp_hosts
echo '#!/usr/bin/expect
	spawn /usr/bin/scp /etc/csync2/csync2_ssl_cert.pem /etc/csync2/csync2_ssl_key.pem /etc/csync2/csync2.cluster.key /etc/csync2/csync2_bxconf.cfg /etc/csync2/csync2_bxwww.cfg /etc/csync2/tmp_slave_hostname /etc/csync2/tmp_hosts /etc/csync2/tmp_mysql.sh root@'"$ip"':/etc/csync2
	expect {
		-re ".*Are.*.*yes.*no.*" {
		send "yes\r"
		exp_continue
	}
	"*assword:*" { send '"$rootPasswd"'\r\n; interact }
	eof { exit }
}
exit' > /root/bitrix-env/tmp/scp.sh
chmod +x /root/bitrix-env/tmp/scp.sh
/root/bitrix-env/tmp/scp.sh
rm -f /root/bitrix-env/tmp/scp.sh
rm -f /etc/csync2/tmp_slave_hostname
rm -f /etc/csync2/tmp_hosts
rm -f /etc/csync2/tmp_mysql.sh

echo '#!/usr/bin/expect
	spawn /usr/bin/ssh -l root '"$ip"' /root/bitrix-env/start_slave_node.sh
	expect {
		-re ".*Are.*.*yes.*no.*" {
		send "yes\r"
		exp_continue
}

"*assword:*" { send '"$rootPasswd"'\r\n; interact }
eof { exit }
}
exit' > /root/bitrix-env/tmp/ssh.sh
chmod +x /root/bitrix-env/tmp/ssh.sh
/root/bitrix-env/tmp/ssh.sh
rm -f /root/bitrix-env/tmp/ssh.sh

#
# Create site backup and copy to slave node
#

test -f /home/bitrix/tmp_add_slave_backup.tar.gz && { rm -f /home/bitrix/tmp_add_slave_backup.tar.gz ; }

echo
echo "Create backup of site files (/home/bitrix/tmp_add_slave_backup.tar.gz)"
tar --exclude-from=/root/bitrix-env/exclude -zcf /home/bitrix/tmp_add_slave_backup.tar.gz -C /home/bitrix/ www > /dev/null &
P=${!}
while [ `ps -p $P h|wc -l` -ne '0' ]; do
	echo -ne "."
	sleep 1
done
echo

echo
echo "Copy site backup to slave node"
echo '#!/usr/bin/expect
	spawn /usr/bin/scp /home/bitrix/tmp_add_slave_backup.tar.gz root@'"$ip"':/home/bitrix
	expect {
		-re ".*Are.*.*yes.*no.*" {
		send "yes\r"
		exp_continue
	}
	"*assword:*" { send '"$rootPasswd"'\r\n; interact }
	eof { exit }
}
exit' > /root/bitrix-env/tmp/scp.sh
chmod +x /root/bitrix-env/tmp/scp.sh
/root/bitrix-env/tmp/scp.sh
rm -f /root/bitrix-env/tmp/scp.sh

echo
echo "Remove tmp_add_slave_backup.tar.gz from master node"
test -f /home/bitrix/tmp_add_slave_backup.tar.gz && { rm -f /home/bitrix/tmp_add_slave_backup.tar.gz ; }

echo
echo "Copy config files to slave node"
csync2 -cr -C bxconf /
csync2 -mr /etc/bx_cluster/nodes -C bxconf
csync2 -m /etc/bx_cluster/dbName.conf -C bxconf
csync2 -m /etc/bx_cluster/master.node -C bxconf
csync2 -mr /etc/nginx/bx/site_avaliable -C bxconf
csync2 -mr /etc/nginx/bx/site_enabled -C bxconf
csync2 -u -C bxconf

echo '#!/usr/bin/expect
	spawn /usr/bin/ssh -l root '"$ip"' /root/bitrix-env/start_slave_csync2.sh
	expect {
	-re ".*Are.*.*yes.*no.*" {
	send "yes\r"
	exp_continue
	}
	"*assword:*" { send '"$rootPasswd"'\r\n; interact }
	eof { exit }
}
exit' > /root/bitrix-env/tmp/ssh.sh
chmod +x /root/bitrix-env/tmp/ssh.sh
/root/bitrix-env/tmp/ssh.sh
rm -f /root/bitrix-env/tmp/ssh.sh

#echo
#echo "Sync web site files on nodes"
#sudo -u bitrix csync2 -cr -C bxwww / > /dev/null &
#P=${!}
#while [ `ps -p $P h|wc -l` -ne '0' ]; do
#	echo -ne "."
#	sleep 1
#done
#echo

#sudo -u bitrix csync2 -u -C bxwww > /dev/null &
#P=${!}
#while [ `ps -p $P h|wc -l` -ne '0' ]; do
#	echo -ne "."
#	sleep 1
#done
#echo

#
# Check mysql restarting
#

timeOut=0
while [ $timeOut -le 50 ]; do
	echo -ne "."
	sleep 1
	let "timeOut++";
done
echo

echo '#!/usr/bin/expect
	spawn /usr/bin/ssh -l root '"$ip"' /root/bitrix-env/check_mysql_status.sh
	expect {
	-re ".*Are.*.*yes.*no.*" {
	send "yes\r"
	exp_continue
	}
	"*assword:*" { send '"$rootPasswd"'\r\n; interact }
	eof { exit }
}
exit' > /root/bitrix-env/tmp/ssh.sh
chmod +x /root/bitrix-env/tmp/ssh.sh
/root/bitrix-env/tmp/ssh.sh
rm -f /root/bitrix-env/tmp/ssh.sh

echo
if [ "$pwd" = "" ]; then
	db=`mysql -u root -h "$ip" -e "SHOW DATABASES;"`
else
	db=`mysql -p"$pwd" -u root -h "$ip" -e "SHOW DATABASES;"`
fi

noDB="N"
checkDB=`echo "$db" | grep "$dbName"`
if [ "$checkDB" = "" ]; then noDB="Y" ; fi

checkDB=`echo "$db" | grep ERROR`
if [ "$checkDB" != "" ]; then noDB="ERROR" ; fi

if [ "$noDB" = "Y" ]; then

	#
	# Dump db
	#

	echo
	echo "Create database dump"
	if [ "$mysqlMasterPasswd" = "" ]; then
		mysqldump --single-transaction --flush-logs --master-data=2 --opt -u root "$dbName"  > /root/bitrix-env/tmp/db_dump_"$dbName".sql &
		P=${!}
		while [ `ps -p $P h|wc -l` -ne '0' ]; do
			echo -ne "."
			sleep 1
		done
		echo
	else
		mysqldump --single-transaction --flush-logs --master-data=2 --opt -u root -p"$mysqlMasterPasswd" "$dbName"  > /root/bitrix-env/tmp/db_dump_"$dbName".sql &
		P=${!}
		while [ `ps -p $P h|wc -l` -ne '0' ]; do
			echo -ne "."
			sleep 1
		done
		echo
	fi


	echo
	echo "Create database on slave node"
	test -z "$pwd" && { db=`mysql -u root -h "$ip" -e "CREATE DATABASE $dbName;"` ; } || { db=`mysql -p"$pwd" -u root -h "$ip" -e "CREATE DATABASE $dbName;" | grep "$dbName"` ; }
	test -z "$pwd" && { db=`mysql -u root -h "$ip" -e "STOP SLAVE;"` ; } || { db=`mysql -p"$pwd" -u root -h "$ip" -e "STOP SLAVE;" | grep "$dbName"` ; }
	echo '<? $masterHost="'"${masterNode}"'"; $dbHost="'"${hostname}"'"; $dbName="'"${dbName}"'"; $dbPasswd="'"${pwd}"'"; ?>' > /root/bitrix-env/tmp/db_connect.php

	sqlChangeMaster=`head -n 50 /root/bitrix-env/tmp/db_dump_"$dbName".sql | grep "MASTER_LOG_FILE=" |sed "s/${node}//g"`
	skipStr="-- ";
	sqlChangeMaster=`head -n 50 /root/bitrix-env/tmp/db_dump_"$dbName".sql | grep MASTER_LOG_FILE |sed "s/${skipStr}//g"`;
	sqlChangeMaster=`echo "$sqlChangeMaster" |sed "s/;//g"`;

	echo
	echo "Restore data base on slave node"

	if [ "$pwd" = "" ]; then
		mysql -u root -h "$ip" "$dbName"  < /root/bitrix-env/tmp/db_dump_"$dbName".sql &
		P=${!}
		while [ `ps -p $P h|wc -l` -ne '0' ]; do
			echo -ne "."
			sleep 1
		done
		echo
	else
		mysql -p"$pwd" -u root -h "$ip" "$dbName"  < /root/bitrix-env/tmp/db_dump_"$dbName".sql &
		P=${!}
		while [ `ps -p $P h|wc -l` -ne '0' ]; do
			echo -ne "."
			sleep 1
		done
		echo
	fi
	rm -f /root/bitrix-env/tmp/db_dump_"$dbName".sql
	resetCluster=`php -f /root/bitrix-env/before_check_slave.php`
	dbErrStr=`php -f /root/bitrix-env/check_slave_node.php`
	if [ "$dbErrStr" = "" ]; then

		echo
		echo "Change master on slave node"

		sql="	$sqlChangeMaster, MASTER_HOST = '$masterNode', MASTER_USER = 'root', MASTER_PASSWORD = '$mysqlMasterPasswd', MASTER_PORT = 3306; START SLAVE;"

		test -z "$pwd" && { mysql -u root -h "$ip" "$dbName" -e "STOP SLAVE;" > /dev/null ; mysql -u root -h "$ip" "$dbName" -e "$sql" ; } || { mysql -p"$pwd" -u root -h "$ip" "$dbName" -e "STOP SLAVE" > /dev/null ; mysql -p"$pwd" -u root -h "$ip" "$dbName"  -e "$sql" ; }

		php -f /root/bitrix-env/add_slave_node.php
		chown -R bitrix:bitrix /home/bitrix/www/bitrix/modules/cluster

	else
		echo
		echo "Database configuration has some errors, after these errors are fixed you must manually add slave services to Bitrix admin."
		echo
		echo "$dbErrStr"
		echo
	fi
	rm -f /root/bitrix-env/tmp/db_dump_"$dbName".sql
	rm -f /root/bitrix-env/tmp/db_connect.php
else
	echo
	if [ "$noDB" = "ERROR" ]; then
 		echo "Can not connect to slave database"
	else
 		echo "Database exist on slave node. You mast manually add services on Bitrix admin"
	fi
fi

service nginx restart
read -p "Finished. Press any key: " ok
