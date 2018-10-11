#!/bin/bash

isBackup=`cat /etc/crontab | grep bxbackup` ;
test -z "$isBackup" && { action="start" ; } || { action="stop" ; } ;


dateUp=`date +%s`
ip_=`ifconfig | grep Bcast | grep -v 127.0.0.1 | awk '{print $2}' | sed 's/addr://'`

echo
echo "Master configuration and start or stop backup"
echo "Be careful: this master can remove your old backup settings"
echo
read -p "Do you want $action backup? [ y/N ]: " YN
echo
echo

if [ "$YN" != "y" -a "$YN" != "Y" ]; then
	exit;
fi

if [ "$action" == "stop" ]; then

	echo ;
	echo "Stopping backup" ;
	sed  -i".bak" '/bxbackup/d' /etc/crontab

	echo ;
	echo "Backup stopped." ;
	read -p "Press any key" key ;

else

endReadN="N" ;
while [ "$endReadN" = "N" ]
do

echo ;
echo "How often do you want to create a backup?" ;
echo "0 - once a day" ;
echo "1 - once a week" ;
echo "2 - once a month" ;

read -p "Enter your choice: " backupPeriod ;

if [ "$backupPeriod" == "0" -o "$backupPeriod" == "1" -o "$backupPeriod" == "2" ]; then
	endReadN="Y" ;
else
	echo ;
	echo "Incorrect choice, try again " ;
	echo ;
fi
done

#
# Set backup hour
#
echo ;
endReadN="N" ;
while [ "$endReadN" = "N" ]
do

read -p "Choice a hour for creating backup (0 - 23): " dayHour ;

if [ $dayHour -ge 0 -a $dayHour -le 23 ]; then
	endReadN="Y" ;
else
	echo ;
	echo "Invalid hour, try again " ;
	echo ;
fi
done

#
# Set day of week
#

if [ "$backupPeriod" == "1" ]; then

echo ;
endReadN="N" ;
while [ "$endReadN" = "N" ]
do

read -p "Choose a day of week for creating backup (0 - 6): " weekDay ;
if [ $weekDay -ge 0 -a $weekDay -le 6 ]; then
	endReadN="Y" ;
else
	echo ;
	echo "Invalid day of week, try again " ;
	echo ;
fi
done
fi

#
# Set mounth day
#

if [ "$backupPeriod" == "2" ]; then

echo ;
endReadN="N" ;
while [ "$endReadN" = "N" ]
do

read -p "Choose a day of month for creating backup (1 - 31): " mountDay ;
if [ $mountDay -ge 1 -a $mountDay -le 31 ]; then
	endReadN="Y" ;
else
	echo ;
	echo "Invalid day of month, try again " ;
	echo ;
fi
done
fi


echo ;
read -p "Add additional site folder for backup? (y/N) :" addExt ;
echo

if [ "$addExt" == "y" -o "$addExt" == "Y" ]; then

arSite=
siteCnt=0;
for siteDName in $(ls /home/bitrix/ext_www); do
	if [ -d /tmp/php_sessions/ext_www/"$siteDName" -a -d /tmp/php_upload/ext_www/"$siteDName" ]; then
		arSite[$siteCnt]=$siteDName;
		let "siteCnt++";
	fi
done

echo
echo "Select site folder for adding to backup"
echo
endRead="N"
while [ "$endRead" == "N" ]
do
	i=0;
	while [ $i -lt $siteCnt ]
	do
		echo "$i - ${arSite[$i]}"
		let "i++";
	done
	echo
	read -p "Enter the number of your choice: " siteNum

	if [ -d /tmp/php_sessions/ext_www/"${arSite[$siteNum]}" ]; then
		endRead="Y";
	else
		echo
		echo "Your choice is invalid. Please try again."
	fi
done

echo "/home/bitrix/ext_www/${arSite[$siteNum]}" > /home/bitrix/backup/scripts/extsite.txt

fi


test ! -d /home/bitrix/backup/archive && { mkdir -p /home/bitrix/backup/archive ; } ;
test ! -d /home/bitrix/backup/scripts && { mkdir -p /home/bitrix/backup/scripts ; } ;
test ! -f /home/bitrix/backup/scripts/bxbackup.sh && { cp -f /root/bitrix-env/bxbackup.sh /home/bitrix/backup/scripts ; } ;
test ! -f /home/bitrix/backup/scripts/ex.txt && { cp -f /root/bitrix-env/ex.txt /home/bitrix/backup/scripts ; } ;
test ! -f /home/bitrix/backup/scripts/get_mysql_settings.php && { cp -f /root/bitrix-env/get_mysql_settings.php /home/bitrix/backup/scripts ; } ;
chown -R bitrix:bitrix /home/bitrix/backup ;
chmod -R 0770 /home/bitrix/backup/archive ;


if [ "$backupPeriod" == "0" ]; then
echo "10 $dayHour * * * bitrix test -f /home/bitrix/backup/scripts/bxbackup.sh && { /home/bitrix/backup/scripts/bxbackup.sh ; } >/dev/null 2>&1
" >> /etc/crontab;
fi

if [ "$backupPeriod" == "1" ]; then
echo "10 $dayHour * * $weekDay bitrix test -f /home/bitrix/backup/scripts/bxbackup.sh && { /home/bitrix/backup/scripts/bxbackup.sh ; } >/dev/null 2>&1
" >> /etc/crontab;
fi

if [ "$backupPeriod" == "2" ]; then
echo "10 $dayHour $mountDay * * bitrix test -f /home/bitrix/backup/scripts/bxbackup.sh && { /home/bitrix/backup/scripts/bxbackup.sh ; } >/dev/null 2>&1
" >> /etc/crontab;
fi

echo ;
echo "Backup started." ;
read -p "Press any key" key ;


fi