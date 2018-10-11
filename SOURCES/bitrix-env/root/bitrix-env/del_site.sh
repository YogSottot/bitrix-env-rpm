#!/bin/bash
echo
echo "This master remove server configuration file for additional site."
echo "If you want delete site files and databases, you mast do it later manualy!";
read -p "Continue [ y/N ]" key

if [ "$key" = 'Y' -o "$key" = 'y' ]; then

#
# Get ext site
#

arSite=
siteCnt=0;
for siteDName in $(ls /home/bitrix/ext_www); do
	if [ -d /tmp/php_sessions/ext_www/"$siteDName" -a -d /tmp/php_upload/ext_www/"$siteDName" ]; then
		arSite[$siteCnt]=$siteDName;
		let "siteCnt++";
	fi
done

echo
echo "Select site to delete"
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
	read -p "Enter you choise number: " siteNum

	if [ -d /tmp/php_sessions/ext_www/"${arSite[$siteNum]}" ]; then
		endRead="Y";
	else
		echo
		echo "Your choice is incorrect. Please try again."
	fi
done

rm -fr /tmp/php_sessions/ext_www/"${arSite[$siteNum]}"
rm -fr /tmp/php_upload/ext_www/"${arSite[$siteNum]}"
rm -r /etc/nginx/bx/site_avaliable/bx_ext_"${arSite[$siteNum]}".conf
rm -r /etc/nginx/bx/site_ext_enabled/bx_ext_"${arSite[$siteNum]}".conf
rm -r /etc/nginx/bx/site_avaliable/bx_ext_ssl_"${arSite[$siteNum]}".conf
rm -r /etc/nginx/bx/site_ext_enabled/bx_ext_ssl_"${arSite[$siteNum]}".conf
rm -f /etc/httpd/bx/conf/bx_ext_"${arSite[$siteNum]}".conf

service nginx restart
service httpd restart

echo
echo "The configuration of website has been deleted successfully."
read -p "Press any key" key

fi