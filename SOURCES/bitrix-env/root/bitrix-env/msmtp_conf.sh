#!/bin/bash
conf=/home/bitrix/.msmtprc
echo "======================================="
echo "	Mail sending subsystem setting"
#echo "Thanks to Vadim Balabin vbalabin@energosib.ru"
echo "======================================="
echo

read -p "SMTP server name: " smtp

read -p "SMTP port (press ENTER to leave default value, SMTP port = 25): " port
[ "$port" = "" ] && port=25

read -p "Default sender address: " sender

read -p "Is SMTP authorization required? (y/n): " auth
if [ "$auth" = "Y" -o "$auth" = "y" ]; then
	auth="Yes"
	read -p "Username: " username
	read -s -p "Password: " password
else
	auth="No"
fi;

echo
tlsreq="No"
read -p "Is TLS required? (y/n): " tls
if [ "$tls" = "Y" -o "$tls" = "y" ]; then
	tlsstr="tls on\ntls_certcheck off";
	tlsreq="Yes";
fi;

echo "======================================="
echo "	Current SMTP authorization parameters"
echo "======================================="
echo "SMTP server: $smtp"
echo "SMTP port: $port"
echo "Default sender address: $sender"
echo "Is SMTP authorization required?:" $auth
if [ $auth = "Yes" ]; then
	echo "Username: $username"
	echo "Password: *********"
fi;
echo "Is TLS required?: $tlsreq"
echo "======================================="
echo

read -p "Save changes? (y/n): " save

if [ "$save" = "y" -o "$save" = "Y" ]; then
	file="account default\nlogfile /var/log/msmtp.log\nhost $smtp\nport $port\nfrom $sender\nkeepbcc on"
	if [ "$auth" = "Yes" ]; then file="$file\nauth on\nuser $username\npassword $password"
		else file="$file\nauth off"
	fi

	if [ "$tls" = "Y" -o "$tls" = "y" ]; then
		file="$file\n$tlsstr"
	fi

	test -f $conf && { mv -f $conf $conf.ori.$dateUp ; } ;
	echo -e $file > $conf ;
	chown bitrix:bitrix $conf ;
	chmod 600 $conf ;
	ln -sf $conf /etc/msmtprc ;


	test -f /etc/nagios_msmtprc && { mv -f /etc/nagios_msmtprc /etc/nagios_msmtprc.ori.$dateUp ; } ;
	echo -e $file > /etc/nagios_msmtprc ;

	chmod 0700 /etc/nagios_msmtprc ;
	chown nagios:nagios /etc/nagios_msmtprc ;

	test ! -f /var/log/msmtp.log && { touch /var/log/msmtp.log ; } ;
	chmod 0666 /var/log/msmtp.log ;
fi