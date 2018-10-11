#!/bin/bash

isBackup=`cat /etc/crontab | grep bxbackup` ;
test -z "$isBackup" && { action="start" ; } || { action="stop" ; } ;

dateUp=`date +%s`
ip_=`ifconfig | grep Bcast | grep -v 127.0.0.1 | awk '{print $2}' | sed 's/addr://'`

echo
echo "Master configuration and start or stop sphinx search server"
echo
endRead="N"
while [ "$endRead" = "N" ]
do
	echo "0. Start sphinx"
	echo "1. Stop sphinx"
	echo "2. Show sphinx index"
	echo "3. Add index"
	echo "4. Delete index"
	echo "5. Return to previous menu"
	echo
	read -p "Enter you choise number: " encNum;
	if [ $encNum -ge 0 -a $encNum -le 5 ]; then
		endRead="Y" ;
	else
		echo ;
		echo "Your choice is incorrect. Please try again." ;
	fi
	echo ;
	echo ;
done

# Exit
if [ $encNum -eq 5 ]; then
	exit ;
fi

# Start sphinx
if [ $encNum -eq 0 ]; then

	echo ;
	echo "Starting sphinx" ;
	chkconfig searchd on ;
	service searchd restart ;
	echo ;
	read -p "Press any key" key ;
	exit ;
fi

# Stop sphinx
if [ $encNum -eq 1 ]; then

	echo ;
	echo "Stop sphinx" ;
	chkconfig searchd off ;
	service searchd stop ;
	echo ;
	read -p "Press any key" key ;
	exit ;
fi

# Show sphinx index
if [ $encNum -eq 2 ]; then
	echo
	echo "Spinx index."

	#
	# Get index list
	#
	indexCnt=0;
	for index in $(ls /etc/sphinx/bx/search_index/ | sed 's/\.conf$//g'); do
		echo "$indexCnt - $index" ;
		let "indexCnt++";
	done
	echo ;
	echo ;
	read -p "Press any key" key ;
	exit ;
fi

# Add sphinx index
if [ $encNum -eq 3 ]; then

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
		indexType="utf-8";
	else
		indexType="sbcs"
	fi

	#
	# Get index name
	#
	echo
	echo "Specify a new index name"
	endRead="N"
	while [ "$endRead" = "N" ]
	do
		read -p "Sphinx search index: " indexName
		indexExist='N'
		for index in $(ls /etc/sphinx/bx/search_index/ | awk -F "_" '{print $1}') ; do
			if [ "$indexName" == "$index" ]; then
				indexExist='Y' ;
			fi
		done

		if [ "$indexExist" == 'Y' ]; then
			echo ;
			echo "This index already exists in the configuration. Please try again." ;
		else
			echo
			endRead="Y"
		fi
	done

	indexSuffix=`date | md5sum | awk '{print $1}' | cut -c-11` ;
	indexName="$indexName""_$indexSuffix";
	cp /root/bitrix-env/etc/sphinx/index.conf /etc/sphinx/bx/search_index/"$indexName".conf ;
	sed -i "s/#INDEX_NAME#/$indexName/g" /etc/sphinx/bx/search_index/"$indexName".conf ;
	sed -i "s/#INDEX_TYPE#/$indexType/g" /etc/sphinx/bx/search_index/"$indexName".conf ;

	service searchd restart ;

	echo ;
	echo "Created index: $indexName" ;
	echo  ;
	read -p "Do you want configure bitrix to use sphinx with this index [ y/N ] " key
	if [ "$key" = 'Y' -o "$key" = 'y' ]; then

		#
		# Get ext site
		#

		arSite=
		siteCnt=1;
		for siteDName in $(ls /home/bitrix/ext_www); do
			if [ -d /tmp/php_sessions/ext_www/"$siteDName" -a -d /tmp/php_upload/ext_www/"$siteDName" ]; then
				arSite[$siteCnt]=$siteDName;
				let "siteCnt++";
			fi
		done

		let "siteCnt--";

		echo ;
		echo "Select site to configure" ;
		echo ;
		endRead="N" ;
		echo "0 - Main site" ;
		while [ "$endRead" == "N" ]
		do
			i=1 ;
			let "siteCnt++" ;
			while [ $i -lt $siteCnt ]
			do
				echo "$i - ${arSite[$i]}" ;
				let "i++" ;
			done
			echo ;
			read -p "Enter you choise number: " siteNum ;

			if [ -d /tmp/php_sessions/ext_www/"${arSite[$siteNum]}" -o $siteNum -eq 0 ]; then
				endRead="Y" ;
			else
				echo ;
				echo "Your choice is incorrect. Please try again." ;
			fi
		done

		if [ $siteNum -eq 0 ]; then
			/root/bitrix-env/sphinx_search_on.php "/home/bitrix/www/" "$indexName" ;
		else
			/root/bitrix-env/sphinx_search_on.php "/home/bitrix/ext_www/${arSite[$siteNum]}" "$indexName" ;
		fi

		echo "Sphinx search configuried" ;
		read -p "Press any key" key ;
		exit ;
	else
		echo ;
		echo "You shold configuried search module" ;
		read -p "Press any key" key ;
		exit ;
	fi
fi

# Delete sphinx index
if [ $encNum -eq 4 ]; then
	echo
	echo "This master remove spinx index."
	read -p "Continue [ y/N ] " key

	if [ "$key" = 'Y' -o "$key" = 'y' ]; then

		#
		# Get ext site
		#
		arIndex=
		indexCnt=0;
		#for index in $(ls /etc/sphinx/bx/search_index/ | awk -F "_" '{print $1}'); do
		for index in $(ls /etc/sphinx/bx/search_index/ | grep ".conf" | sed 's/\.conf$//g'); do
			arIndex[$indexCnt]=$index;
			let "indexCnt++";
		done

		echo
		echo "Select index to delete"
		echo
		endRead="N"
		while [ "$endRead" == "N" ]
		do
			i=0;
			while [ $i -lt $indexCnt ]
			do
				echo "$i - ${arIndex[$i]}"
				let "i++";
			done
			echo
			read -p "Enter you choise number: " indexNum

			if [ -f /etc/sphinx/bx/search_index/"${arIndex[$indexNum]}.conf" ]; then
				endRead="Y";
			else
				echo
				echo "Your choice is incorrect. Please try again."
			fi
		done

		service searchd stop

		rm -f "/etc/sphinx/bx/search_index/${arIndex[$indexNum]}.conf" ;
		rm -f "/var/lib/sphinx/${arIndex[$indexNum]}*.conf" ;

		service searchd start ;

		echo ;
		read -p "Press any key" key ;
		exit ;
	fi
fi

echo ;
echo ;
read -p "Press any key" key ;
fi