#!/bin/bash
echo "======================================="
echo "  Bitrix virtual appliance"
echo "	Ethernet interface manual setting"
echo "======================================="
echo

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

read -p "Type IP address (for example, 192.168.0.1) and press ENTER: " address ;
read -p "Type broadcast (for example, 192.168.0.255) and press ENTER: " broadcast ;
read -p "Type default gateway IP address and press ENTER: " gateway ;
read -p "Type network mask and press ENTER: " netmask ;
read -p "Type DNS server IP address and press ENTER: " dns ;

echo "======================================="
echo "	Custom network parameters"
echo "======================================="
echo IP address: $address
echo broadcast: $broadcast
echo default gateway: $gateway
echo network mask: $netmask
echo DNS server: $dns
echo "======================================="
echo
read -p "Save changes? (y/N) " key ;
if [ $key == "Y" -o $key == "y" ]; then

echo "
DEVICE=$ifName
#HWADDR=
IPADDR=$address
NETMASK=$netmask
BROADCAST=$broadcast
GATEWAY=$gateway
ONBOOT=yes
" > /etc/sysconfig/network-scripts/ifcfg-$ifName

sed -i".bak" '/nameserver/d' /etc/resolv.conf
echo "nameserver " $dns >> /etc/resolv.conf

service network restart

fi;
echo ;
read -p "Press any key" key ;