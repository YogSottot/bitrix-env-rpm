#!/bin/bash

test -f /root/bitrix-env/monitoring.on && {
	action="stop" ;
	serverMonitoring="ON" ;
} || {
	action="start" ;
	serverMonitoring="OFF" ;
}

dateUp=`date +%s`
ip_=`ifconfig | grep Bcast | grep -v 127.0.0.1 | awk '{print $2}' | sed 's/addr://'`

echo
echo "Master configuration and start or stop server monitoring"
echo "Be careful: this master can remove your settings for munin and nagios"
if [ "$serverMonitoring" == "ON" ]; then
echo "Munin http://$ip_/munin/ or https://$ip_/munin/"
echo "Nagios http://$ip_/nagios/ or https://$ip_/nagios/"
fi
echo
read -p "Do you want to $action server monitoring? [ y/N ]: " YN
echo
echo

if [ "$YN" = "y" -o "$YN" = "Y" ]; then
	echo
else
	exit;
fi

if [ "$action" == "stop" ]; then
	echo ;
	echo "Stopping server monitoring" ;
	echo ;

	ln -sf /etc/nginx/bx/server_monitor.conf /etc/nginx/bx/conf/blank.conf ;
	service munin-node stop ;
	chkconfig --del munin-node >/dev/null 2>&1 ;

	service nagios stop ;
	chkconfig --del nagios >/dev/null 2>&1 ;

	mv -f /etc/httpd/bx/conf/munin.conf /etc/httpd/bx/conf/munin.conf.disabled ;
	mv -f /etc/httpd/bx/conf/nagios.conf /etc/httpd/bx/conf/nagios.conf.disabled ;
	rm -f /etc/nginx/bx/site_enabled/server_status.conf ;

	service nginx restart ;
	service httpd restart ;
	rm -f /root/bitrix-env/monitoring.on ;

	echo ;
	echo "Monitoring stopped." ;
	read -p "Press any key" key ;

else

#
# Configure some munin plugins
#

echo ;
echo "Starting server monitoring" ;
echo ;


echo "
[apache_*]
    env.url	http://127.0.0.1:8888/server-status?auto
    env.ports 8888

[nginx*]
      env.url http://127.0.0.1:8886/
" > /etc/munin/plugin-conf.d/bx ;

echo ;
endReadN="N" ;
while [ "$endReadN" = "N" ]
do
	read -p "Munin user login: " muninLogin ;
	if [ "$muninLogin" != "" -a "$muninLogin" != "root" ]; then
		endReadN="Y" ;
	else
		echo ;
		echo "Incorrect munin user login " ;
		echo ;
	fi
done

echo ;
endReadN="N" ;
while [ "$endReadN" = "N" ]
do
	read -s -p "Munin user password: " muninPassword ;
	if [ "$muninPassword" != "" ]; then
		endReadN="Y" ;
	else
		echo ;
		echo "Incorrect munin password " ;
		echo ;
	fi
done

echo ;
endReadN="N" ;
while [ "$endReadN" = "N" ]
do
	read -s -p "Password for nagiosadmin user: " nagiosPassword ;
	if [ "$nagiosPassword" != "" ]; then
		endReadN="Y" ;
	else
		echo ;
		echo "Incorrect nagiosadmin password " ;
		echo ;
	fi
done

echo ;
endReadN="N" ;
while [ "$endReadN" = "N" ]
do
	read -p "Administrator email: " nagiosEmail ;
	if [ "$nagiosEmail" != "" ]; then
		endReadN="Y" ;
	else
		echo ;
		echo "Incorrect administrator email " ;
		echo ;
	fi
done

#
# Install munin plugins
#

rm -f /etc/munin/plugins/* ;

ln -sf /usr/share/munin/plugins/apache_accesses /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/apache_processes /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/apache_volume /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/cpu /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/df /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/diskstats /etc/munin/plugins ;

for iface in $(ls /etc/sysconfig/network-scripts | grep ifcfg- | sed "s/ifcfg-//g"); do
	ln -sf /usr/share/munin/plugins/if_ /etc/munin/plugins/if_$iface ;
done

ln -sf /usr/share/munin/plugins/iostat /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/load /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/memory /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/netstat /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/nginx_request /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/nginx_status /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/open_files /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/processes /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/swap /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/threads /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/mysql_bytes /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/mysql_queries /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/mysql_slowqueries /etc/munin/plugins ;
ln -sf /usr/share/munin/plugins/mysql_threads /etc/munin/plugins ;

test -f /etc/munin/munin.conf && { mv -f /etc/munin/munin.conf /etc/munin/munin.conf.ori.$dateUp ; cp /root/bitrix-env/etc/munin/munin.conf /etc/munin/munin.conf ; } ;
test -f /etc/munin/munin-node.conf && { mv -f /etc/munin/munin-node.conf /etc/munin/munin-node.conf.ori.$dateUp ; cp /root/bitrix-env/etc/munin/munin-node.conf /etc/munin/munin-node.conf ; } ;

LIMIT=1 ;
mymuninvar=0 ;

until  test "$mymuninvar" -eq "$LIMIT"
do
test -d /var/www/munin."$mymuninvar" && { (( mymuninvar++ )) ; (( LIMIT++ )) ; } || LIMIT=`expr $mymuninvar` ;
done

test -d /var/www/munin && { mv -f /var/www/munin /var/www."$mymuninvar" ; echo 'Directory /var/www/munin was moved to /var/www/munin.'"$mymuninvar" ; } ;
mkdir -p /var/www/munin ;

chown -R munin:munin /var/www/munin ;
chmod -R 0775 /var/www/munin ;

test -f /etc/httpd/bx/conf/munin.conf && { mv -f /etc/httpd/bx/conf/munin.conf /etc/httpd/bx/conf/munin.conf.ori.$dateUp ; } ;

test -f /home/bitrix/munin_passwd && { mv -f /home/bitrix/munin_passwd /home/bitrix/munin_passwd.ori.$dateUp ; } ;
htpasswd -bc /home/bitrix/munin_passwd $muninLogin $muninPassword ;

test -f /etc/httpd/bx/conf/nagios.conf && { mv -f /etc/httpd/bx/conf/nagios.conf /etc/httpd/bx/conf/nagios.conf.ori.$dateUp ; } ;
cp -f /root/bitrix-env/etc/httpd/nagios.conf /etc/httpd/bx/conf/nagios.conf ;

test -d /usr/lib/nagios/cgi-bin/ && { sed -i "s/#NAGIOS_CGI_DIR#/\/usr\/lib\/nagios\/cgi-bin\//g" /etc/httpd/bx/conf/nagios.conf ; } ;
test -d /usr/lib64/nagios/cgi-bin/ && { sed -i "s/#NAGIOS_CGI_DIR#/\/usr\/lib64\/nagios\/cgi-bin\//g" /etc/httpd/bx/conf/nagios.conf ; } ;

test -f /etc/nagios/objects/commands.cfg && { cp -f /etc/nagios/objects/commands.cfg /etc/nagios/objects/commands.cfg.ori.$dateUp ; } ;
cp -f /root/bitrix-env/etc/nagios/commands.cfg /etc/nagios/objects/commands.cfg ;

test -f /etc/nagios/objects/localhost.cfg && { cp -f /etc/nagios/objects/localhost.cfg /etc/nagios/objects/localhost.cfg.ori.$dateUp ; } ;
cp -f /root/bitrix-env/etc/nagios/localhost.cfg /etc/nagios/objects/localhost.cfg ;

sed -i".bak" "s/nagios@localhost/$nagiosEmail/g" /etc/nagios/objects/contacts.cfg ;

rule=`cat /home/bitrix/www/.htaccess | grep !/server-status`
test -z "$rule" && { sed -i '/\!\/bitrix\/urlrewrite\.php\$/ a\  RewriteCond \%\{REQUEST_URI\} \!\/server-status\$' /home/bitrix/www/.htaccess ; }

rule=`cat /home/bitrix/www/.htaccess | grep !/munin` ;
test -z "$rule" && { sed -i '/\!\/bitrix\/urlrewrite\.php\$/ a\  RewriteCond \%\{REQUEST_URI\} \!\/munin\$' /home/bitrix/www/.htaccess ; } ;

rule=`cat /home/bitrix/www/.htaccess | grep !/nagios` ;
test -z "$rule" && { sed -i '/\!\/bitrix\/urlrewrite\.php\$/ a\  RewriteCond \%\{REQUEST_URI\} \!\/nagios\$' /home/bitrix/www/.htaccess ; } ;

test -f /etc/nagios/passwd && { mv -f /etc/nagios/passwd /etc/nagios/passwd.ori.$dateUp ; } ;
htpasswd -bc /etc/nagios/passwd nagiosadmin $nagiosPassword ;

ln -sf /etc/nginx/bx/site_avaliable/server_status.conf /etc/nginx/bx/site_enabled ;
ln -sf /etc/nginx/bx/conf/server_monitor.conf /etc/nginx/bx/ ;


test ! -f /etc/httpd/bx/conf/bx_status.conf && {

echo "<IfModule mod_status.c>
    ExtendedStatus On
    <Location /server-status>
	SetHandler server-status
        Order Deny,Allow
        Deny from All
        Allow from 127.0.0.1
    </Location>
</IfModule>" > /etc/httpd/bx/conf/bx_status.conf ;

}

chown -R nagios:bitrix /usr/share/nagios/html
chown -R nagios:bitrix /var/log/nagios
chown -R nagios:bitrix /var/spool/nagios

test -f /etc/nagios_msmtprc && { mv -f /etc/nagios_msmtprc /etc/nagios_msmtprc.ori.$dateUp ; } ;
test -f /home/bitrix/.msmtprc && { cp -f /home/bitrix/.msmtprc /etc/nagios_msmtprc ; } ;
chmod 0600 /etc/nagios_msmtprc ;
chown nagios:nagios /etc/nagios_msmtprc ;

test ! -f /var/log/msmtp.log && { touch /var/log/msmtp.log ; } ;
chmod 0666 /var/log/msmtp.log ;

service httpd restart ;
service nginx restart ;
service munin-node restart ;
chkconfig munin-node on ;

service nagios restart ;
chkconfig nagios on ;

touch /root/bitrix-env/monitoring.on ;

echo ;
echo "Monitoring started." ;
read -p "Press any key" key ;

fi