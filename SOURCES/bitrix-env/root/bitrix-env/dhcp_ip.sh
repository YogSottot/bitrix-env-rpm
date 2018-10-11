#!/bin/sh

ifaceCnt=0 ;
arIface= ;
ifName="" ;

for iface in $(ls /etc/sysconfig/network-scripts | grep ifcfg-eth | sed "s/ifcfg-//g"); do
	arIface[$ifaceCnt]=$iface;
	let "ifaceCnt++" ;
done


if [ $ifaceCnt -gt 1 ]; then
	echo ;
	echo "Select interface: " ;
	echo ;

	endRead="N"
	while [ "$endRead" == "N" ]
	do
		i=0;
		while [ $i -lt $ifaceCnt ]
		do
			echo "$i - ${arIface[$i]}"
			let "i++";
		done
		echo
		read -p "Enter you choise number: " ifNum

		if [ $ifNum -ge 0 -a $ifNum -lt $ifaceCnt ]; then
			endRead="Y";
		else
			echo
			echo "Your choice is incorrect. Please try again."
		fi
	done

	ifName="${arIface[$ifNum]}";
else
	ifName="${arIface[0]}"
fi

echo "
DEVICE=$ifName
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
" > /etc/sysconfig/network-scripts/ifcfg-$ifName

service network restart
#/etc/init.d/networking restart > /dev/null 2>&1

echo ;
read -p "Press any key" key ;