#!/bin/bash

echo "Persisting DHCP service network configurations."

ProductiveLanVirtIP=$1

DNS1=$(grep -h -m 1 DNS1 /etc/sysconfig/network-scripts/ifcfg*)
DNS2=$(grep -h -m 1 DNS2 /etc/sysconfig/network-scripts/ifcfg*)

for Device in $(ip l | cut -d ' ' -f2) ; do

    Interface=( $(ip address show dev $Device) );
    OutPut=/etc/sysconfig/network-scripts/ifcfg-${Interface[1]%:}

    (
        echo DEVICE=${Interface[1]%:}
        echo BOOTPROTO=none
        echo ONBOOT=yes
        echo NETWORK=${Interface[18]%\.*}.0
        echo TYPE=Ethernet
        echo IPADDR=${Interface[18]%/*}
        echo IPV4_FAILURE_FATAL=no
        echo IPV6INIT=no
        echo NETMASK=255.255.255.0
        echo HWADDR=${Interface[14]}
        echo NAME=System_${Interface[1]%:}
    )   > $OutPut

    if [[ "${Interface[18]%\.*}" == "${ProductiveLanVirtIP%\.*}" ]] ; then
        (
            echo DEFROUTE=yes
            echo GATEWAY=$ProductiveLanVirtIP
            echo ${DNS1}
            echo ${DNS2}
        )   >> $OutPut
    fi  

    echo "System_${Interface[1]%:} done" ; 

done 

