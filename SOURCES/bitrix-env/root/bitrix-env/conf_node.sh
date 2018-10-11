#!/bin/bash

#
# Make new configuration after sync conf
#

ip_=`ifconfig | grep Bcast | grep -v 127.0.0.1 | awk '{print $2}' | sed 's/addr://'`
hostname=`hostname`

ln -sf /etc/bx_cluster/nodes/${hostname} /etc/bx_cluster/current.node

arNodeList=
arNodeIpList=
nodeCnt=0;
masterNodeIp=`cat /etc/bx_cluster/master.node`;
currentNodeIp=`cat /etc/bx_cluster/current.node`;
dbName=`cat /etc/bx_cluster/dbName.conf`;
masterNode=
currentNode=
mysqlServerID=
currentServerID=
isMaster="N";
if [ "$masterNodeIp" = "$currentNodeIp" ]; then isMaster="Y"; fi

#
# Read bx_cluster config
#

for node in $(ls /etc/bx_cluster/nodes)
do
	arNodeList[$nodeCnt]=$node;    
	arNodeIpList[${nodeCnt}]=`cat /etc/bx_cluster/nodes/${node}`;	
	mysqlServerID[$nodeCnt]=`cat /etc/bx_cluster/mysql_cluster_nodes.conf | grep ${node} | sed "s/${node}\=//g" `;
	if [ ${arNodeIpList[$nodeCnt]} = ${currentNodeIp} ]; then currentNode=$node; currentServerID=${mysqlServerID[$nodeCnt]}; fi
	if [ ${arNodeIpList[$nodeCnt]} = ${masterNodeIp} ]; then masterNode=$node; fi
	let "nodeCnt++";
done

#
# Add info about cluster nodes to /etc/hosts
#

i=0;
while [ $i -lt $nodeCnt ]
do
    nodeDesc=${arNodeIpList[$i]}" "${arNodeList[$i]};
    test -z "`cat /etc/hosts | grep "${nodeDesc}"`" &&  echo ${nodeDesc} >> /etc/hosts;
    let "i++";
done

#
# Add firewall rulles
#
echo 
echo "Add firewall rules"

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

#
# Configure mysql node
#

test ! -d /var/log/mysqld && { mkdir -p /var/log/mysqld ; chmod -R 0770 /var/log/mysqld ; chown -R mysql:mysql /var/log/mysqld ; }

if [ "$isMaster" = "N" ]; then

echo 
echo "Configure mysql server node"

#if [ `mysql -V | grep "Distrib 5.0" | wc -l` -eq 0 ]; then binlogFormat="binlog_format=mixed" ; else binlogFormat="" ; fi

echo "
[mysqld]
${binlogFormat}
bind-address = 0.0.0.0
binlog-do-db=${dbName}
server-id=${currentServerID}
binlog_cache_size = 4M
max_binlog_size = 512M
relay-log = /var/log/mysqld/bx_cluster_${dbName}_relay.log
relay-log-info-file = /var/log/mysqld/bx_cluster_${dbName}_relay_log.info
relay-log-index = /var/log/mysqld/bx_cluster_log_${dbName}_relay.index" > /etc/mysql/conf.d/bx_node.cnf;

fi

#
# Nginx reconfigure
#

echo
echo "Configure nginx server node"

ln -sf /etc/nginx/bx/site_avaliable/cluster_s1.conf /etc/nginx/bx/site_enabled
ln -sf /etc/nginx/bx/conf/slave_node_port.conf /etc/nginx/bx/node_port.conf
echo "server_name "${hostname}";" > /etc/nginx/bx/node_host.conf

service mysqld restart
service httpd restart
service nginx restart

