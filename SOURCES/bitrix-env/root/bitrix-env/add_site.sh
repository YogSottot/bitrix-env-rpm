#!/bin/bash
echo
echo "Important! This wizard doesn’t support cluster configurations.";
read -p "Press any key" key

#
# Get sitename
#

arSite=
siteCnt=0;
for siteDName in $(ls /home/bitrix/ext_www); do
	if [ -d /tmp/php_sessions/ext_www/"$siteDName" -a -d /tmp/php_upload/ext_www/"$siteDName" ]; then
		arSite[$siteCnt]=$siteDName;
		let "siteCnt++";
	fi
done

endRead="N"
while [ "$endRead" = "N" ]
do
	read -p "Website address, without www (e.g.: mysite.com): " sitename
	if [ "$sitename" = "" -o "$sitename" = "localhost" ]; then
		echo "Incorrect website address. Please try again"
		echo
	else
		siteExist='N'
		for item in $(ls /etc/nginx/bx/site_avaliable | grep "bx_ext_") ; do
			tmpName=`cat /etc/nginx/bx/site_avaliable/$item | grep "server_name " | sed 's/\t\tserver_name //g'` ;
			newName="$sitename www.$sitename;" ;
			if [ "$tmpName" == "$newName" ]; then
				siteExist='Y' ;
			fi
		done

		if [ "$siteExist" == 'Y' ]; then
			echo ;
			echo "This website already exists in the configuration. Please try again." ;
		else
			echo
			endRead="Y"
		fi
	fi
done

#
# Get folder name
#

endRead="N"
while [ "$endRead" = "N" ]
do
	read -p "Directory name for website files (e.g.: mysite): " sitedir
	if [ "$sitedir" = "" -o -d "/home/bitrix/ext_www/$sitedir" -o -d "/tmp/php_sesions/ext_www/$sitedir" -o -d "/tmp/php_upload/ext_www/$sitedir" ]; then
		echo "The directory name is incorrect, or such directory already exists."
		echo
	else
		echo
		endRead="Y"
	fi
done

mkdir -p /home/bitrix/ext_www/"$sitedir"
mkdir -p /tmp/php_sessions/ext_www/"$sitedir"
mkdir -p /tmp/php_upload/ext_www/"$sitedir"

#
# Get encoding
#

echo
echo "Specify the website charset"
endRead="N"
while [ "$endRead" = "N" ]
do
	echo
	echo "0 - utf8"
	echo "1 - cp1251"
	read -p "Enter you choise number: " encNum
	if [ "$encNum" = '0' -o "$encNum" = '1' ]; then
		endRead="Y";
	else
		echo
		echo "Your choice is incorrect. Please try again."
	fi
done

if [ $encNum -eq 0 ]; then
	encoding="utf-8";
else
	encoding="cp1251"
fi

#
# Some character settings
#

if [ $encNum -eq 0 ]; then
	character="DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci";
	charset="utf-8";
	phpOverload=" ";
	phpInternal=" ";
else
	character="DEFAULT CHARACTER SET cp1251 COLLATE cp1251_general_ci";
	charset="windows-1251";
	phpOverload="php_admin_value mbstring.func_overload 0";
	phpInternal="php_admin_value mbstring.internal_encoding latin";
fi

#
# Need create symlink
#

echo
read -p "Create symbolic links to existing Bitrix kernel? [ y/N ]: " needSymLink

if [ "$needSymLink" = 'Y' -o "$needSymLink" = 'y' ]; then
	endRead="N"
	while [ "$endRead" = "N" ]
	do
		echo
		read -p "The full path to the Bitrix installation directory: " kernelFolder

		correctDR="Y"
		test -d "$kernelFolder/bitrix" && {
			echo "The folder \"bitrix\" exists." ;
		} || {
			echo "The \"bitrix\" folder doesn’t exist." ;
			correctDR="N" ;
		}

		test -d "$kernelFolder/upload" && {
			echo "The folder \"upload\" exists." ;
		} || {
			echo "The \"upload\" folder doesn’t exist." ;
			correctDR="N" ;
		}

		test -d "$kernelFolder/images" && {
			echo "The folder \"images\" exists." ;
		} || {
			echo "The \"images\" folder doesn’t exist." ;
			correctDR="N" ;
		}

		if [ "$correctDR" = "Y" ]; then
			ln -sf  "$kernelFolder/bitrix" /home/bitrix/ext_www/"$sitedir" ;
			ln -sf  "$kernelFolder/upload" /home/bitrix/ext_www/"$sitedir" ;
			ln -sf  "$kernelFolder/images" /home/bitrix/ext_www/"$sitedir" ;
			endRead="Y" ;
		else
			echo ;
			echo "The folder is incorrect. Please try again." ;
		fi
	done

else

	#
	# Get DBLogin, DBPasswd, DBName
	#
  mysql_socket=/var/lib/mysqld/mysqld.sock
  mysql_temp_dir=/tmp
  [[ -d /dev/shm ]] && mysql_temp_dir=/dev/shm
  mysql_date=$(date +"%Y-%m-%d")
  mysql_log_file=$mysql_temp_dir/${mysql_date}_mysql.log

	endRead="N"
	while [ "$endRead" = "N" ]
	do
		echo
		read -p "MySQL user login to create the database(defaults: root): " DBLogin
    [[ -z "$DBLogin" ]] && DBLogin=root

		echo
		read -s -p "MySQL user password to create the database: " DBPasswd

    # create file for connection to mysql
    mysql_cnf=$mysql_temp_dir/.my_$sitedir.cnf
    echo '[client]' > $mysql_cnf
    echo "user=$DBLogin" >> $mysql_cnf
    echo "password=$DBPasswd" >> $mysql_cnf
    echo "socket=$mysql_socket" >> $mysql_cnf
    echo >> $mysql_cnf
    chmod 400 $mysql_cnf

    # mysql cmd string
    mysql_cmd="mysql --defaults-file=$mysql_cnf"

    # settings for site connection
		echo
		echo "New mysql user account for working with site"
		echo
		endReadN="N"
		while [ "$endReadN" = "N" ]
		do
			echo ;
			read -p "MySQL user login (Not root or empty): " DBLoginSite ;
			if [ "$DBLoginSite" != "" -a "$DBLoginSite" != "root" ]; then
				endReadN="Y" ;
			fi

			echo ;
			read -s -p "MySQL user password: " DBPasswdSite ;
		done
		echo

    # create database and user for access
		read -p "Database name: " DBName
    if [[ -z "$DBName" ]]; then
      echo
      echo "You must define DB name"
      read -p "Error creating the database. Try again? [ y/N ]: " tryAgain
      [[ $(echo "$tryAgain" | grep -ci '^y$') -gt 0 ]] && endRead=N
    else
      # create sql file with commands
      mysql_sql_file=$mysql_temp/${mysql_date}_$DBName.sql
      printf "CREATE DATABASE \`%s\` %s;\n" \
       "${DBName}" "${character}" > $mysql_sql_file
      printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO \`%s\`@\`%s\` IDENTIFIED BY '%s';\n" \
       "$DBName" "${DBLoginSite}" '%' "$DBPasswdSite"  >> $mysql_sql_file
      printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO \`%s\`@\`%s\` IDENTIFIED BY '%s';\n" \
       "$DBName" "${DBLoginSite}" 'localhost' "$DBPasswdSite" >> $mysql_sql_file

      # run command
      cat $mysql_sql_file | $mysql_cmd  > $mysql_log_file 2>&1
      if [[ $? -gt 0 ]]; then
        echo
        echo "Database creation return error: "
        cat $mysql_log_file
        read -p "Try again? [ y/N ]: " tryAgain
        [[ $(echo "$tryAgain" | grep -ci '^y$') -gt 0 ]] && endRead=N

        [[ "$endRead" != 'N' ]] && exit 1
      else
		    endRead="Y"
      fi
      # delete temporary file
      rm -f $mysql_log_file $mysql_sql_file $mysql_cnf
		fi
	done

	echo
	echo "Unpacking Bitrix enviroment"
	cp /root/bitrix-env/vm.tar.gz /home/bitrix/ext_www/"$sitedir"
	cd /home/bitrix/ext_www/"$sitedir"
	tar -zxf vm.tar.gz
	rm -f vm.tar.gz

  # create configuration dbconn.php for site
  tmp_dir=/root/bitrix-env/tmp
  [[ ! -d $tmp_dir ]] && mkdir -p -m 700 $tmp_dir
	echo '<? $dbHost="localhost"; $dbLogin="'"$DBLoginSite"'"; $dbName="'"${DBName}"'"; $dbPasswd="'"${DBPasswdSite}"'"; $DOCUMENT_ROOT="/home/bitrix/ext_www/'"${sitedir}"'";?>' > $tmp_dir/db_connect.php
	php -f /root/bitrix-env/add_site_change_db.php
  if [[ $? -gt 0 ]]; then
    echo
    echo Error: Failed to create the configuration file dbconn.php
    exit 1
  fi
	rm -f $tmp_dir/db_connect.php
	chown bitrix:bitrix /home/bitrix/www/bitrix/php_interface/dbconn.php

  # create cron task for site
  cron_config=/etc/cron.d/bx_${sitedir}
	chechCronTask=`cat /etc/crontab | grep "/home/bitrix/ext_www/$sitedir"` ;

  if [[ -z "$chechCronTask" ]]; then
    if [[ ! -f $cron_config ]]; then
      cron_events=/home/bitrix/ext_www/$sitedir/bitrix/modules/main/tools/cron_events.php

      echo -e "#\n# cron tasks for site $sitename\n#\n\n" > $cron_config
      echo "* * * * * bitrix test -f $cron_events && { /usr/bin/php -f $cron_events ; } >/dev/null 2>&1" >> $cron_config
      chmod 644 $cron_config
    fi
  fi
fi

phpSessionSavePath="\/tmp\/php_sessions\/ext_www\/$sitedir"
phpUploadTmpDir="\/tmp\/php_upload\/ext_www\/$sitedir"

chown -R bitrix:bitrix /home/bitrix/ext_www/"$sitedir"
chmod -R 0770 /home/bitrix/ext_www/"$sitedir"

chown -R bitrix:bitrix /tmp/php_sessions/ext_www/"$sitedir"
chmod -R 0770 /tmp/php_sessions/ext_www/"$sitedir"

chown -R bitrix:bitrix /tmp/php_upload/ext_www/"$sitedir"
chmod -R 0770 /tmp/php_upload/ext_www/"$sitedir"

test ! -f /etc/httpd/bx/conf/bx_apache_site_name_port.conf && { cp /root/bitrix-env/etc/httpd/bx_apache_site_name_port.conf /etc/httpd/bx/conf ; }

cp /root/bitrix-env/etc/nginx/bx_nginx_site_template.conf /etc/nginx/bx/site_avaliable/bx_ext_"$sitedir".conf
sed -i "s/#SERVER_NAME#/$sitename/g" /etc/nginx/bx/site_avaliable/bx_ext_"$sitedir".conf
sed -i "s/#SERVER_DIR#/$sitedir/g" /etc/nginx/bx/site_avaliable/bx_ext_"$sitedir".conf
sed -i "s/#SERVER_ENCODING#/$charset/g" /etc/nginx/bx/site_avaliable/bx_ext_"$sitedir".conf
ln -sf /etc/nginx/bx/site_avaliable/bx_ext_"$sitedir".conf /etc/nginx/bx/site_ext_enabled

cp /root/bitrix-env/etc/nginx/bx_ssl_nginx_site_template.conf /etc/nginx/bx/site_avaliable/bx_ext_ssl_"$sitedir".conf
sed -i "s/#SERVER_NAME#/$sitename/g" /etc/nginx/bx/site_avaliable/bx_ext_ssl_"$sitedir".conf
sed -i "s/#SERVER_DIR#/$sitedir/g" /etc/nginx/bx/site_avaliable/bx_ext_ssl_"$sitedir".conf
sed -i "s/#SERVER_ENCODING#/$charset/g" /etc/nginx/bx/site_avaliable/bx_ext_ssl_"$sitedir".conf
ln -sf /etc/nginx/bx/site_avaliable/bx_ext_ssl_"$sitedir".conf /etc/nginx/bx/site_ext_enabled

cp /root/bitrix-env/etc/httpd/bx_apache_site_template.conf /etc/httpd/bx/conf/bx_ext_"$sitedir".conf
sed -i "s/#SERVER_NAME#/$sitename/g" /etc/httpd/bx/conf/bx_ext_"$sitedir".conf
sed -i "s/#SERVER_DIR#/$sitedir/g" /etc/httpd/bx/conf/bx_ext_"$sitedir".conf
sed -i "s/#PHP_OVERLOAD#/$phpOverload/g" /etc/httpd/bx/conf/bx_ext_"$sitedir".conf
sed -i "s/#PHP_INTERNAL#/$phpInternal/g" /etc/httpd/bx/conf/bx_ext_"$sitedir".conf
sed -i "s/#PHP_SESSIONS#/php_admin_value session.save_path $phpSessionSavePath/g" /etc/httpd/bx/conf/bx_ext_"$sitedir".conf
sed -i "s/#PHP_UPLOAD#/php_admin_value upload_tmp_dir $phpUploadTmpDir/g" /etc/httpd/bx/conf/bx_ext_"$sitedir".conf

service httpd restart
service nginx restart

echo
echo "The website has been created successfully."
read -p "Press any key" key
