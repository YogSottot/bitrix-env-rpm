#!/bin/bash

correctData="N"
while [ "$correctData" = "N" ]
do


echo "======================================="
echo "	NTLM Authentication"
echo "======================================="
echo

readEnd="N"
while [ "$readEnd" = "N" ]
do
	read -p "Netbios domain name (TEST): " DN
	if [ "$DN" = "" ]; then
		echo "Incorrect netbios domain name, try again"
		echo
	else
		readEnd="Y"
	fi
done

readEnd="N"
while [ "$readEnd" = "N" ]
do
	read -p "Full domain name (TEST.LOCAL): " DNF
	if [ "$DNF" = "" ]; then
		echo "Incorrect full domain name, try again"
		echo
	else
		readEnd="Y"
		DNFS=`echo "$DNF" | tr A-Z a-z`
	fi
done

readEnd="N"
while [ "$readEnd" = "N" ]
do
	read -p "Domain password server (TEST-DC-SP.TEST.LOCAL): " DPS
	if [ "$DPS" = "" ]; then
		echo "Incorrect domain password server, try again"
		echo
	else
		readEnd="Y"
	fi
done

readEnd="N"
while [ "$readEnd" = "N" ]
do
	read -p "Server netbios name (PORTAL): " NBSName
	if [ "$DPS" = "" ]; then
		echo "Incorrect server netbios name, try again"
		echo
	else
		readEnd="Y"
	fi
done


readEnd="N"
while [ "$readEnd" = "N" ]
do
	read -p "Domain administrator user name (Administrator): " DU
	if [ "$DU" = "" ]; then
		echo "Incorrect domain user name, try again"
		echo
	else
		readEnd="Y"
	fi
done

ipCnt=0;
for ip_ in $(ifconfig | grep Bcast | grep -v 127.0.0.1 | awk '{print $2}' | sed 's/addr://')
do
	ipList[${ipCnt}]="$ip_"
	let "ipCnt++";
done

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

echo
echo
echo "======================================="
echo " Current NTLM Authentication settings"
echo "======================================="
echo
echo "Netbios domain name: $DN"
echo
echo "Full domain name: $DNF"
echo
echo "Domain password server: $DPS"
echo
echo "Server netbios name: $NBSName"
echo
echo "Domain administrator user name: $DU"
echo
echo "Server ip address: $ip"

read -p "Save changes? (y/n): " save

if [ "$save" = "y" -o "$save" = "Y"  ]; then
	correctData="Y"
fi

done


dateUP=`date +%s`

test ! -f /etc/samba/smb.conf && { mv -f /etc/samba/smb.conf /etc/samba/smb.conf."$dateUP".back ; }
cp /root/bitrix-env/etc/samba/smb.conf /etc/samba/smb.conf
sed -i "s/#DN#/$DN/g" /etc/samba/smb.conf
sed -i "s/#DNF#/$DNF/g" /etc/samba/smb.conf
sed -i "s/#DPS#/$DPS/g" /etc/samba/smb.conf
sed -i "s/#NBSName#/$NBSName/g" /etc/samba/smb.conf

test ! -f /etc/krb5.conf && { mv -f /etc/krb5.conf /etc/krb5.conf."$dateUP".back ; }
cp /root/bitrix-env/etc/krb5.conf /etc/krb5.conf
sed -i "s/#DN#/$DN/g" /etc/krb5.conf
sed -i "s/#DNF#/$DNF/g" /etc/krb5.conf
sed -i "s/#DPS#/$DPS/g" /etc/krb5.conf
sed -i "s/#DNFS#/$DNFS/g" /etc/krb5.conf
sed -i "s/#NBSName#/$NBSName/g" /etc/krb5.conf

sed -i".bak" "s/^passwd\: .*/passwd\: compat winbind/" /etc/nsswitch.conf
sed -i".bak" "s/^group\: .*/group\: compat winbind/" /etc/nsswitch.conf
sed -i".bak" "s/^shadow\: .*/shadow\: compat/" /etc/nsswitch.conf

echo "
search          $DNF
domain          $DNF

" >> /etc/resolv.conf

echo "
$ip	$NBSName.$DNF	$NBSName
" >> /etc/hosts

# Prepare apache server
LIMIT=1 ;
mywwwntlmvar=0 ;

until  test "$mywwwntlmvar" -eq "$LIMIT"
do
test -d "/home/bitrix/www_ntlm.$mywwwntlmvar" && { (( mywwwntlmvar++ )) ; (( LIMIT++ )) ; } || LIMIT=`expr $mywwwntlmvar`
done

test -d /home/bitrix/www_ntlm && { mv -f /home/bitrix/www_ntlm "/home/bitrix/www_ntlm.$mywwwntlmvar" ; echo "Directory /home/bitrix/www_ntlm was moved to /home/bitrix/www_ntlm.$mywwwntlmvar" ; }
mkdir -p /home/bitrix/www_ntlm

ln -sf /home/bitrix/www/bitrix /home/bitrix/www_ntlm
ln -sf /home/bitrix/www/upload /home/bitrix/www_ntlm
ln -sf /home/bitrix/www/images /home/bitrix/www_ntlm
cd /home/bitrix/www_ntlm
tar xzf /root/bitrix-env/vm_ntlm.tar.gz
cd /root
chown -R bitrix:bitrix /home/bitrix/www_ntlm

test ! -f /etc/httpd/bx/conf/mod_ntlm.conf && { cp -f /root/bitrix-env/etc/httpd/mod_ntlm.conf /etc/httpd/bx/conf ; }

usermod -G wbpriv bitrix
service smb restart
service winbind restart
chkconfig smb on
chkconfig winbind on

net ads join -U $DU

service smb restart
service winbind restart
service nginx restart
service httpd restart

php -f /root/bitrix-env/ntlm_on.php

echo
echo "The ntlm has been successfully configured."
read -p "Press any key" key