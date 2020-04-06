# This file is just to source the common variables and functions

CentOSversion=CentOS-7
# These are basic values which might be replaced by commandline optiuons. This is partly already been done by some command options for the database hosts.
IPsNeeded=3
CoresNeeded=5
RAMNeeded=5
HDNeeded=67
SSDNeeded=0

APIversion=v4
InvokeSSH="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no -o ForwardAgent=yes -q"
CurlHeader="--header "'Content-Type: application/vnd.profitbricks.resource+json'""
CurlInvoke='/usr/bin/curl -s --include --user '
CurlPost='/usr/bin/curl -s --include --request POST --user '
CurlPatch='/usr/bin/curl -s --include --request PATCH --user '
CurlPut='/usr/bin/curl -s --include --request PUT --user '

PersistendPassword=$(pwgen -N 1 12)

User=$(cat ~/ionos/.config) # put your credentials in here or at another place in the form user@profitbricks.com:password
PubKey=$(cat ~/.ssh/id_rsa.pub)
AuthKeys="$HOME/.ssh/authorized_keys"
if [ ! -e $AuthKeys ] ; then AuthKeys="$HOME/.ssh/id_rsa.pub" ; fi
AuthKeys=$(cat $AuthKeys | while read ; do echo '"'$REPLY'"' ; done | tr "\n" ",")
AuthKeys=${AuthKeys%\",} # Keys need to be set between '"' but the first and the last are disturbing variable distribution
AuthKeys=${AuthKeys#\"}

MainSubNet=10.99
ManagementLan=${MainSubNet}.1
GatewayPartnerLan=${MainSubNet}.2
ProductiveLan=${MainSubNet}.3
PostgreSQLPartnerLan=${MainSubNet}.4

ManagementHostIP=${ManagementLan}.1
ManagementLanVirtIP=${ManagementLan}.4
ProductiveLanVirtIP=${ProductiveLan}.3
PostgreSQLVirtIP=${ProductiveLan}.6

AuthPassVRRP=$(pwgen -N 1 8)

function AvailableResources {

    if [[ "${StorageType}" == "SSD" ]] ; then
        SSDNeeded=$(( ${DBVolume} * 2 ))
    else
        HDNeeded=$(( (${DBVolume} * 2) + ${HDNeeded} ))
    fi

    Resources=$(curl -Ss --include --request GET --user ${User} https://api.profitbricks.com/cloudapi/${APIversion}/contracts)
    Resources=( $(echo ${Resources} | perl -p -e '{{s/.*coresPerContract/coresPerContract/} ; {s/, "/\n/g} ; {s/[":}]//g}}') )

    coresPerContract=${Resources[1]}
    coresProvisioned=${Resources[3]}
    ramPerContract=${Resources[7]}
    ramProvisioned=${Resources[9]}
    hddLimitPerContract=${Resources[13]}
    hddVolumeProvisioned=${Resources[15]}
    ssdLimitPerContract=${Resources[19]}
    ssdVolumeProvisioned=${Resources[21]}
    reservableIps=${Resources[23]}
    reservedIpsOnContract=${Resources[25]}

    CompIPs=$((     ${reservableIps}       - ${reservedIpsOnContract}           - ${IPsNeeded}   ))
    CompCores=$((   ${coresPerContract}    - ${coresProvisioned}                - ${CoresNeeded} ))
    CompRAM=$(( ( ( ${ramPerContract}      - ${ramProvisioned} )       / 1024 ) - ${RAMNeeded}   ))
    CompHD=$((  ( ( ${hddLimitPerContract} - ${hddVolumeProvisioned} ) / 1024 ) - ${HDNeeded}    ))
    CompSSD=$(( ( ( ${ssdLimitPerContract} - ${ssdVolumeProvisioned} ) / 1024 ) - ${SSDNeeded}   ))

    echo
    echo "Available resources after script run:"

    for item in                  \
        "IPs: ${CompIPs}"        \
        "Cores: ${CompCores}"    \
        "RAM: ${CompRAM} in GB"  \
        "HDD: ${CompHD} in GB"   \
        "SSD: ${CompSSD} in GB"
    do
        echo -n ${item}
        if [[ "${item}" =~ "-" ]] ; then echo -n " =>> Increase your limit!" ; IncreaseNeeded=yes ; fi
        echo
    done
    if [[ "${IncreaseNeeded}" == "yes" ]] ; then
        echo "Please contact the enterprise support to get more resources available, otherwise the setup of the VDC would fail."
        echo "Ending."
        exit 2
    fi

}

function SetDNS {
    DNSfile=/tmp/resolv.conf.$$
    case $Place in
    fra)
        echo "nameserver 185.48.118.6"   > $DNSfile
        echo "nameserver 185.48.116.10" >> $DNSfile
        ;;
    fkb)
        echo "nameserver 46.16.74.70"  > $DNSfile
        echo "nameserver 46.16.72.37" >> $DNSfile
        ;;
    lhr)
        echo "nameserver 77.68.110.243"  > $DNSfile
        ;;
    txl)
        echo "nameserver 185.132.46.123"  > $DNSfile
        ;;
    las)
        echo "nameserver 208.94.37.18"   > $DNSfile
        echo "nameserver 162.254.24.10" >> $DNSfile
        ;;
    ewr)
        echo "nameserver 157.97.105.67"  > $DNSfile
        echo "nameserver 157.97.104.10" >> $DNSfile
        ;;
    icn)
        echo "nameserver 112.107.15.243"  > $DNSfile
        echo "nameserver 112.107.14.130" >> $DNSfile
        ;;
    esac
    echo "Setting nameserver for $Place:"
    cat $DNSfile
}

function SetIPBlock {
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary ' {
            "properties": {
                "size": "3",
                "location": "'""${Country}/${Place}""'"
            }
        }' https://api.profitbricks.com/cloudapi/${APIversion}/ipblocks)
    VDCobjectPoll=$(echo $VDCobject | grep -E -o 'https://api.profitbricks.com/cloudapi/'${APIversion}'/ipblocks/[^ ",]+')
    while [[ "$VDCobjectStatus" == "" ]] ; do
        if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader ${VDCobjectPoll} | grep -o "HTTP/2 200")
        sleep 10
    done
    VDCobject=( $(echo $VDCobject | grep -o -E '"ips" : .[^]]+' | grep -o -E '[0-9.]+' | tr "\n" " ") )
    echo ${VDCobject[*]}
}

function CreateVDC {
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary '{
            "properties": {
                "name": "'""${VDCName}""'",
                "description": "'""${Description}""'",
                "location": "'""${Country}/${Place}""'"
            }
         }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters )
    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi
    echo $VDCobject | grep -o -E '"[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}' | tr -d '"'
}

function CreatePublicLan {
    VDC=$1
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary ' {
            "properties": {
                "name": "Internet",
                "public": "true"
            }
        }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/lans)
    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi
    echo $VDCobject | grep -o -E '"id[^0-9]+[0-9]+' | grep -o -E '[0-9]+'
}

function GetSource() {
    Distribution=$1
    Images=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/images?depth=5)
    VDCobject=$(echo $Images | \
              sed 's/ "id"/\n"id"/g' | \
              grep -E "${Distribution}.*?${Country}/${Place}\"" | \
              grep -o -E '"[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}')
    VDCobject=${VDCobject#\"}
    echo "$VDCobject"
}

function CreateVolume() {
    Size=$1
    Name=$2
    Source=$3
    VDC=$4
    VDCobjectStatus=""
    VDCobject=$($CurlPost $User $CurlHeader --data-binary '
            {"properties": 
                { 
                    "size": "'""$Size""'", 
                    "name": "'""$Name""'", 
                    "image": "'""$Source""'",
                    "imagePassword": "'""$PersistendPassword""'",
                    "bus": "VIRTIO", 
                    "sshKeys": ["'"${AuthKeys}"'"],
                    "type": "HDD" 
                }
            }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/volumes) 

    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi

    VDCobject=$(echo $VDCobject | grep -o -E -m 1 'href[^,]+' | grep -o -E '[^/]+$' | tr -d '"')
    while [[ "$VDCobjectStatus" == "" ]] ; do
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/volumes/${VDCobject})
        VDCobjectStatus=$(echo $VDCobjectStatus | grep -o "HTTP/2 200")
        sleep 30
    done
    echo "$VDCobject"
} 

function CreatePureVolume() {
    Size=$1
    Name=$2
    VDC=$3
    if [[ $StorageType == "" ]] ; then StorageType=HDD ; fi
    if [[ $StorageType == "SSD" ]] ; then
        AvailabilityZone=AUTO
    else
        AvailabilityZone=ZONE_$(echo $HostName | grep -E -o "[12]$") 
    fi
    VDCobjectStatus=""
    VDCobject=$($CurlPost $User $CurlHeader --data-binary '
            {"properties": 
                { 
                    "size": "'""$Size""'", 
                    "name": "'""$Name""'", 
                    "type": "'""$StorageType""'", 
                    "licenceType": "LINUX",
                    "availabilityZone": "'""$AvailabilityZone""'"
                }
            }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/volumes)

    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi

    VDCobject=$(echo $VDCobject | grep -o -E -m 1 'href[^,]+' | grep -o -E '[^/]+$' | tr -d '"')
    while [[ "$VDCobjectStatus" == "" ]] ; do
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/volumes/${VDCobject})
        VDCobjectStatus=$(echo $VDCobjectStatus | grep -o "HTTP/2 200")
        sleep 30
    done
    echo "$VDCobject"
}

function CreateHost() {
    Name=$1
    Volume=$2
    AvailabilityZone=$3
    VDC=$4
    cpuFamily=$5
    if [[ $cpuFamily == "" ]] ; then cpuFamily=AMD_OPTERON ; fi

    Name=${Name}_${AvailabilityZone}
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary '{
               "entities":{
                  "volumes":{
                     "items":[
                        { "id":"'""$Volume""'" }
                     ]
                  }
               },
               "properties":{
                  "cores": 1,
                  "ram": "4096",
                  "cpuFamily": "'""$cpuFamily""'",
                  "name": "'""$Name""'",
                  "bootVolume": { "id":"'""$Volume""'" },
                  "availabilityZone": "'""$AvailabilityZone""'"
                }
            }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers)

    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi

    VDCobject=$(echo $VDCobject | grep -o -m 1 -E '"[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}' | head -n 1 | tr -d '"')
    while [[ "$VDCobjectStatus" == "" ]] ; do
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/${VDCobject})
        VDCobjectStatus=$(echo $VDCobjectStatus | grep -o "HTTP/2 200")
        sleep 30
    done
    echo $VDCobject
}

function AddPublicNic() { 
    HostId=$1
    PublicLanID=$2
    HostIP=$3
    VDC=$4
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary ' {
          "properties": {
            "ips": ["'""$HostIP""'"],
            "dhcp": "true",
            "lan": "'""$PublicLanID""'",
            "firewallActive": "false"
          }
        }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/${HostId}/nics)
    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi
    VDCobject=$(echo $VDCobject | grep -o -E '"[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}' | tr -d '"')
    while [[ "$VDCobjectStatus" == "" ]] ; do
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/${HostId}/nics/${VDCobject})
        VDCobjectStatus=$(echo $VDCobjectStatus | grep -o "HTTP/2 200")
        sleep 20
    done
    echo $VDCobject
}

function AddIPPublicNic() {
    HostId=$1
    PublicLanID=$2
    HostIP1=$3
    HostIP2=$4
    NicId=$5
    VDC=$6
    VDCobjectStatus=""
    VDCobject=$( $CurlPut $User $CurlHeader --data-binary '{
          "properties": {
            "ips": ["'""$HostIP1""'","'""$HostIP2""'"],
            "dhcp": "true",
            "lan": "'""$PublicLanID""'"
          }
        }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/${HostId}/nics/${NicId} )
    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi
    VDCobject=$(echo $VDCobject | grep -o -E '"[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}' | tr -d '"' | uniq)
    while [[ "$VDCobjectStatus" == "" ]] ; do
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/${HostId}/nics/${VDCobject})
        VDCobjectStatus=$(echo $VDCobjectStatus | grep -o "HTTP/2 200")
        sleep 20
    done
    echo $VDCobject
}

function CreateIPFailover {
    PublicLanID=$1
    NicId=$2
    VirtIP=$3
    VDC=$4
    VDCobjectStatus=""
    VDCobject=$( $CurlPatch $User $CurlHeader --data-binary '{
            "ipFailover": [
              {
                "ip": "'""$VirtIP""'",
                "nicUuid": "'""$NicId""'"
              }
            ],
            "public": "true"
    }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/lans/${PublicLanID} )
}

function CreateInternalLan {
    Name=$1
    VDC=$2
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary ' {
            "properties": {
                "name": "'""$Name""'",
                "public": "false"
            }
        }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/lans)
    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi
    VDCobject=$(echo $VDCobject | grep -o -E '"id[^0-9]+[0-9]+' | grep -o -E '[0-9]+')
    while [[ "$VDCobjectStatus" == "" ]] ; do
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/lans/${VDCobject})
        VDCobjectStatus=$(echo $VDCobjectStatus | grep -o "HTTP/2 200")
        sleep 5
    done
    echo $VDCobject
}

function AddInternalNic() { 
    HostId=$1
    InternalLanID=$2
    HostIP=$3
    VDC=$4
    NicStatus=""
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary ' {
          "properties": {
            "ips": ["'""$HostIP""'"],
            "dhcp": "true",
            "lan": "'""$InternalLanID""'"
          }
        }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/${HostId}/nics)
    VDCobject=$(echo $VDCobject | grep -o -E '"[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}' | tr -d '"')
    while [[ "$VDCobjectStatus" == "" ]] ; do
        VDCobjectStatus=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/${HostId}/nics/${VDCobject})
        VDCobjectStatus=$(echo $VDCobjectStatus | grep -o "HTTP/2 200")
        sleep 15
    done
    ##echo $VDCobject 
}

function PrepareGateAgent() {
    HostIP=$1
    HostName=$2
    VirtExtIP=$3
    VirtIntIP=$4
    
    echo $HostName > /tmp/$HostName.hostname.$$
    scp $InvokeSSH /tmp/$HostName.hostname.$$ root@${HostIP}:/etc/hostname ; rm /tmp/$HostName.hostname.$$
    scp $InvokeSSH /tmp/resolv.conf.$$ root@${HostIP}:/etc/. 
    scp $InvokeSSH sources/load_iptables root@${HostIP}:/etc/network/if-up.d 
    scp $InvokeSSH sources/sysctl.conf root@${HostIP}:/etc/sysctl.conf 
    ssh $InvokeSSH root@${HostIP} "(apt-get update ; apt-get --fix-missing -qq -y install vrrpd keepalived ipvsadm libipset-dev) $AvoidOutput"

    Config=sources/keepalived.conf
    ExtInterfLine=$(grep -n -A 2 "instance VI_PUBLIC_1" $Config  | tail -n 1 | cut -d " " -f1 | grep -E -o '[[:digit:]]+')
    IntInterfLine=$(grep -n -A 2 "instance VI_GATEWAY_1" $Config | tail -n 1 | cut -d " " -f1 | grep -E -o '[[:digit:]]+')
    ProductiveInterfLine=$(grep -n -A 2 "instance VI_PRODUCTIVE_1" $Config | tail -n 1 | cut -d " " -f1 | grep -E -o '[[:digit:]]+')

    case $HostName in
        *1)
        Agent=MASTER ; Priority=100 ;;
        *2)
        Agent=BACKUP ; Priority=50 ;;
    esac

    Interfaces=( $(ssh $InvokeSSH root@${HostIP} "ip -4 addr show" | tr -s ' ' | cut -d ' ' -f 3,8 | grep eth) )
    for i in $(seq 0 ${#Interfaces[*]}) ; do 
        if [[ "${Interfaces[$i]}" =~ "eth" ]] ; then 
            case ${Interfaces[$i]} in
                eth0) eth0=${Interfaces[$i-1]%/*} ;;
                eth1) eth1=${Interfaces[$i-1]%/*} ;;
                eth2) eth2=${Interfaces[$i-1]%/*} ;;
                eth3) eth3=${Interfaces[$i-1]%/*} ;;
            esac
        fi 
    done

    if   [[ "$eth0" =~ "$HostIP" ]]            ; then ExtInterf=${!eth0@}
    elif [[ "$eth0" =~ "$ManagementLan" ]]     ; then IntInterf=${!eth0@}
    elif [[ "$eth0" =~ "$GatewayPartnerLan" ]] ; then SyncInterf=${!eth0@}
    elif [[ "$eth0" =~ "$ProductiveLan" ]]     ; then ProductiveInterf=${!eth0@}; fi

    if   [[ "$eth1" =~ "$HostIP" ]]            ; then ExtInterf=${!eth1@}
    elif [[ "$eth1" =~ "$ManagementLan" ]]     ; then IntInterf=${!eth1@}
    elif [[ "$eth1" =~ "$GatewayPartnerLan" ]] ; then SyncInterf=${!eth1@}
    elif [[ "$eth1" =~ "$ProductiveLan" ]]     ; then ProductiveInterf=${!eth1@}; fi

    if   [[ "$eth2" =~ "$HostIP" ]]            ; then ExtInterf=${!eth2@}
    elif [[ "$eth2" =~ "$ManagementLan" ]]     ; then IntInterf=${!eth2@}
    elif [[ "$eth2" =~ "$GatewayPartnerLan" ]] ; then SyncInterf=${!eth2@}
    elif [[ "$eth2" =~ "$ProductiveLan" ]]     ; then ProductiveInterf=${!eth2@}; fi

    if   [[ "$eth3" =~ "$HostIP" ]]            ; then ExtInterf=${!eth3@}
    elif [[ "$eth3" =~ "$ManagementLan" ]]     ; then IntInterf=${!eth3@}
    elif [[ "$eth3" =~ "$GatewayPartnerLan" ]] ; then SyncInterf=${!eth3@}
    elif [[ "$eth3" =~ "$ProductiveLan" ]]     ; then ProductiveInterf=${!eth3@}; fi

    sed "s/state .*/state ${Agent}/ ; 
         s/lvs_sync_daemon_inteface.*/lvs_sync_daemon_inteface ${SyncInterf}/ ; 
         s/auth_pass.*/auth_pass ${AuthPassVRRP}/ ; 
         s/85.184.250.169/${VirtExtIP}/ ; 
         s/10.99.1.4/${VirtIntIP}/ ; 
         s/10.99.3.3/${ProductiveLanVirtIP}/ ; 
         ${ExtInterfLine}s/interface eth0/interface ${ExtInterf}/ ;
         ${IntInterfLine}s/interface eth2/interface ${IntInterf}/ ;
         ${ProductiveInterfLine}s/interface eth3/interface ${ProductiveInterf}/ ;
         s/priority .*/priority ${Priority}/" sources/keepalived.conf > /tmp/keepalived.conf.$$

    scp $InvokeSSH /tmp/keepalived.conf.$$ root@${HostIP}:/etc/keepalived/keepalived.conf 
    rm /tmp/keepalived.conf.$$

    sed "s#-A firew-before-input -s 95.90.241.12/32 -j ACCEPT#-A firew-before-input -s ${MyIP}/32 -j ACCEPT# ;
         s#-A POSTROUTING -s 10.99.1.0/24 -o eth0 -j MASQUERADE#-A POSTROUTING -s ${ManagementLan}.0/24 -o ${ExtInterf} -j MASQUERADE# ;
         s#-A POSTROUTING -s 10.99.3.0/24 -o eth0 -j MASQUERADE#-A POSTROUTING -s ${ProductiveLan}.0/24 -o ${ExtInterf} -j MASQUERADE# ;
         s#-A.*22222.*#-A PREROUTING -i ${ExtInterf} -p tcp -m tcp --dport 22222 -j DNAT --to-destination ${ManagementHostIP}:22# ;
         s#-A.*5432.*#-A PREROUTING -i ${ExtInterf} -p tcp -m tcp --dport 25432 -j DNAT --to-destination ${PostgreSQLVirtIP}:22#" \
         sources/iptables.rules > /tmp/iptables.rules.$$

    scp $InvokeSSH /tmp/iptables.rules.$$ root@${HostIP}:/etc/iptables.rules 
    rm /tmp/iptables.rules.$$

    ssh $InvokeSSH root@$HostIP "(shutdown -r 1 &) ; exit"
    sleep 60
}

function PrepareManagementHost {
    sleep 60
    DNShosts=$(cut -d " " -f2 /tmp/resolv.conf.$$ | tr "\n" " " | sed 's/ /, /')
    MgmtInterface=$(ssh $InvokeSSH root@${IPBlock[1]} "ssh $InvokeSSH root@${ManagementHostIP} 'ip link show' | grep -E '^2: ' | cut -d ' ' -f2")

    cat <<-EOM >> /tmp/01-netcfg.yaml.$$
    network:
      version: 2
      renderer: networkd
      ethernets:
        ${MgmtInterface}
          dhcp4: no
          gateway4: ${ManagementLanVirtIP}
          addresses: [${ManagementHostIP}/24]
          nameservers:
            addresses: [${DNShosts}]
EOM

    scp $InvokeSSH /tmp/01-netcfg.yaml.$$ root@${IPBlock[1]}:/root/01-netcfg.yaml
    ssh $InvokeSSH root@${IPBlock[1]} "ping -c 5 ${ManagementHostIP}"
    ssh $InvokeSSH root@${IPBlock[1]} "scp $InvokeSSH /root/01-netcfg.yaml root@${ManagementHostIP}:/etc/netplan/01-netcfg.yaml"
    ssh $InvokeSSH root@${IPBlock[1]} "ssh $InvokeSSH root@${ManagementHostIP} 'echo management1 > /etc/hostname'"
    ssh $InvokeSSH root@${IPBlock[1]} "ssh $InvokeSSH root@${ManagementHostIP} 'shutdown -r now'"

    echo "Giving management host some time to reboot."

    if [ "$DB" == "yes" ] ; then
        sleep 180
        SetupSaltMaster
    fi
}

function SetupSaltMaster {
    scp -r $InvokeSSH -P 22222 sources/salt root@${IPBlock[2]}:/srv/.
    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "
        mkdir /srv/dumps
        apt-get update
        apt-get install -y nfs-kernel-server iperf3
        echo 'NEED_SVCGSSD=no' > /etc/default/nfs-kernel-server
        echo '[Mapping]' > /etc/idmapd.conf
        echo 'Nobody-User = nobody' >> /etc/idmapd.conf
        echo 'Nobody-Group = nogroup' >> /etc/idmapd.conf
        echo '/srv/dumps '"${ManagementLan}"'.0/24(rw,nohide,insecure,no_subtree_check,async,no_root_squash)' > /etc/exports
        systemctl restart nfs-server
        systemctl enable nfs-server
    "
    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "
        apt-get -y install python-software-properties ;
        add-apt-repository -y ppa:saltstack/salt ;
        apt-get -y install salt-master;
    "
    scp $InvokeSSH -P 22222 sources/salt-master root@${IPBlock[2]}:/etc/salt/master
    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "echo 'file_ignore_glob: []' >> /etc/salt/master"
    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "service salt-master restart"
    scp $InvokeSSH -P 22222 sources/bootstrap-salt.sh root@${IPBlock[2]}:/root
   
    PWpgpool=$(pwgen -N 1 12 | tr -d '\n') 
    PWpgpoolmd5=$(echo -n $PWpgpool | md5sum | cut -d ' ' -f1) 
    PWrepuser=$(pwgen -N 1 12 | tr -d '\n') 

    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "perl -p -i -e \
      \"s/..:.:pgpool:.*/'*:*:pgpool:$PWpgpool'/;
        s/repl: .recovery_password = .*/repl: \\\"recovery_password = '${PWpgpool}'\\\"/;
        s/ pgpool:.*/ pgpool:"$PWpgpoolmd5"/;
      \" /srv/salt/postgresql/ha.sls
      perl -p -i -e 's/password: repuserpw/password: '"$PWrepuser"'/' /srv/salt/postgresql/ha_master.sls
    "

    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "perl -p -i -e \
        's/10.99.4/'"${PostgreSQLPartnerLan}"'/;
         s/10.99.3/'"${ProductiveLan}"'/;
         s/10.99.1/'"${ManagementLan}"'/;
        ' /srv/salt/postgresql/*.sls
    "

    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "
        perl -p -i -e 's/10.99.4/'"${PostgreSQLPartnerLan}"'/' /srv/salt/postgresql/cluster_connection.sh
        perl -p -i -e \"s/.*primary_conninfo =.*/        primary_conninfo = 'host="${PostgreSQLPartnerLan}.1" user=repuser password="$PWrepuser"'/\" /srv/salt/postgresql/ha_standby.sls
        perl -p -i -e \"s/.*primary_conninfo =.*/        primary_conninfo = 'host="${PostgreSQLPartnerLan}.2" user=repuser password="$PWrepuser"'/\" /srv/salt/postgresql/ha_master.sls
        perl -p -i -e \"s/replication:repuser:.*/replication:repuser:'"$PWrepuser"'\'/\" /srv/salt/postgresql/postgresql.sls
        perl -p -i -e \"s/postgres:pgpool:.*/postgres:pgpool:'"$PWpgpool"'\'/\" /srv/salt/postgresql/postgresql.sls
    "

    PWpostgres=$(pwgen -N 1 12) 
    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "perl -p -i -e  \
      \"s/repl: .sr_check_password = .*/repl: \\\"sr_check_password = '$PWpostgres'\\\"/;
        s/repl: .health_check_password = .*/repl: \\\"health_check_password = '$PWpostgres'\\\"/;
        s/repl: .wd_lifecheck_password = .*/repl: \\\"wd_lifecheck_password = '$PWpostgres'\\\"/;
        s/repl: .trusted_servers = .*/repl: \\\"trusted_servers = '${ManagementHostIP},${ManagementLanVirtIP},${ProductiveLanVirtIP}'\\\"/;
        s/repl: .backend_hostname0 = .*/repl: \\\"backend_hostname0 = '${PostgreSQLPartnerLan}.1'\\\"/;
        s/repl: .backend_hostname1 = .*/repl: \\\"backend_hostname1 = '${PostgreSQLPartnerLan}.2'\\\"/;
        s/repl: .delegate_IP = .*/repl: \\\"delegate_IP = '${PostgreSQLVirtIP}'\\\"/;
      \" /srv/salt/postgresql/ha.sls
    "

    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "
        perl -p -i -e 's/password: postgrespw/password: '"$PWpostgres"'/' /srv/salt/postgresql/ha_master.sls
        perl -p -i -e \"s/postgres:postgres:.*/postgres:postgres:'"$PWpostgres"'\'/\" /srv/salt/postgresql/postgresql.sls
    "

    HC="'"
    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} '
        perl -p -i -e  "s/postgres WITH PASSWORD.*/postgres WITH PASSWORD '"$HC"''"$PWpostgres"''"$HC"'\"/" /srv/salt/postgresql/ha_master.sls
        perl -p -i -e  "s/repuser WITH PASSWORD.*/repuser WITH PASSWORD '"$HC"''"$PWrepuser"''"$HC"'\"/" /srv/salt/postgresql/ha_master.sls
    '

    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "perl -p -i -e \"
        s/repl: .wd_hostname = .*/repl: \\\"wd_hostname = '${PostgreSQLPartnerLan}.1'\\\"/;
        s/repl: .heartbeat_destination0 = .*/repl: \\\"heartbeat_destination0 = '${PostgreSQLPartnerLan}.2'\\\"/;
        s/repl: .other_pgpool_hostname0 = .*/repl: \\\"other_pgpool_hostname0 = '${PostgreSQLPartnerLan}.2'\\\"/;
        \" /srv/salt/postgresql/ha_master.sls
    "

    ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "perl -p -i -e \"
        s/repl: .wd_hostname = .*/repl: \\\"wd_hostname = '${PostgreSQLPartnerLan}.2'\\\"/;
        s/repl: .heartbeat_destination0 = .*/repl: \\\"heartbeat_destination0 = '${PostgreSQLPartnerLan}.1'\\\"/;
        s/repl: .other_pgpool_hostname0 = .*/repl: \\\"other_pgpool_hostname0 = '${PostgreSQLPartnerLan}.1'\\\"/
        \" /srv/salt/postgresql/ha_standby.sls
    "

    if [[ "$StorageType" == "SSD" ]] ; then
        ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "(
            echo ''
            echo 'disable rotational for ssd:'
            echo '  cmd.run:'
            echo '    - name: echo 0 > /sys/block/vdb/queue/rotational'
            echo ''
            echo 'disable rotational in rc.local:'
            echo '  file.append:'
            echo '    - name: /etc/rc.d/rc.local'
            echo '    - text: |'
            echo '        echo 0 > /sys/block/vdb/queue/rotational'
            echo ''
            ) >> /srv/salt/postgresql/postgresql.sls
        "
    fi

    if [[ "$MusicBrainz" == "yes" ]] ; then
        ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "perl -p -i -e 's/- postgresql/$&\n    - prepare_musicbrainz/' /srv/salt/top.sls"
        ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "perl -p -i -e \"s/- switchtopgpool/$&\n  'Postgres*1':\n    - import_musicbrainz/\" /srv/salt/top.sls"
        ssh $InvokeSSH -p 22222 root@${IPBlock[2]} "(
            echo ''
            echo 'start_plackup:'
            echo '  cmd.run:'
            echo '    - cmd.run:'
            echo '    - name: /usr/local/bin/plack_for_musicbrainz.sh start 2>&1 > /dev/null &'
            echo '    - require:'
            echo '        - restart_pgpool'
            echo ''
            ) >> /srv/salt/postgresql/switchtopgpool.sls
        "
    fi
}

function RetrievFullVDC() {
    VDC=$1
    VDCData=$($CurlInvoke $User $CurlHeader https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}?depth=5)
    echo $VDCData
}

function AttachVolume {
    Host=$1
    VolumeId=$2
    VDC=$3
    VDCobjectStatus=""
    VDCobject=$( $CurlPost $User $CurlHeader --data-binary ' {
            "id": "'""${VolumeId}""'"
            }
        }' https://api.profitbricks.com/cloudapi/${APIversion}/datacenters/${VDC}/servers/$Host/volumes)
    if [[ "$VDCobject" =~ "HTTP/2 4" ]] ; then echo $VDCobject; exit 2 ; fi
    echo $VDCobject | grep -o -E '"id[^0-9]+[0-9]+' | grep -o -E '[0-9a-z-]+'
}

function DBHost() {
    # Hostname has to be of the type Postgres_${FileSystem}_${CentOSversion}_1 # last number is the zone
    HostName=$1
    ManagementLanID=$2
    ManagementLanHostIP=${ManagementLan}.$3
    VDC=$4
    if ZONE=$(echo $HostName | grep -E -o "[12]$") ; then ZONE=ZONE_${ZONE} ; else ZONE=Auto ; fi
    Distribution=$(echo $HostName | awk -F _ '{print $3}')

    ImageID=$(GetSource $Distribution)
    Volume=$(CreateVolume 15 ${HostName}_Root $ImageID $VDC)
    Host=$(CreateHost ${HostName} $Volume $ZONE $VDC $cpuFamily)
    Volume=$(CreatePureVolume ${DBVolume} ${HostName}_DB $VDC)
    EatOutput=$(AttachVolume $Host $Volume $VDC)
    ManagementLanNic=$(AddInternalNic $Host $ManagementLanID ${ManagementLanHostIP} $VDC)
    echo $Host
    DNS=$(SetDNS > /dev/null ; X=0 ; grep nameserver /tmp/resolv.conf.$$ | while read ; do X=$(($X+1)) ; echo $REPLY | sed 's/nameserver /DNS'"${X}"'=/'; done)
    DNS1=$(echo "$DNS" | head -n 1)
    DNS2=$(echo "$DNS" | tail -n 1)
    HWADDR=$(ssh $InvokeSSH -p 22222 root@${ExtIP} "ssh $InvokeSSH $ManagementLanHostIP 'ip a s eth0'")
    HWADDR=$(echo $HWADDR | grep -E -o '([a-f0-9]{2}:){5}..' | head -1)

    ssh $InvokeSSH -p 22222 root@${ExtIP} "
echo 'DEVICE=eth0
BOOTPROTO=none
ONBOOT=yes
TYPE=Ethernet
IPADDR='"${ManagementLanHostIP}"'
GATEWAY='"${ManagementLanVirtIP}"'
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=no
HWADDR='"${HWADDR}"'
NAME=System_eth0
'"${DNS1}"'
'"${DNS2}"' ' > /tmp/ifcfg-eth0.${HostName}
    "
    sleep 3
    ssh $InvokeSSH -p 22222 root@${ExtIP} "
        scp $InvokeSSH /tmp/ifcfg-eth0.${HostName} ${ManagementLanHostIP}:/etc/sysconfig/network-scripts/ifcfg-eth0
        ssh $InvokeSSH $ManagementLanHostIP \"echo '"$ManagementHostIP"' management1 >> /etc/hosts\"
        ssh $InvokeSSH $ManagementLanHostIP \"echo '"$HostName"' > /etc/hostname\"
        ssh $InvokeSSH $ManagementLanHostIP \"sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux\"
        ssh $InvokeSSH $ManagementLanHostIP \"sed -i 's/rhgb quiet/rhgb selinux=0 quiet/' /etc/default/grub\"
        ssh $InvokeSSH $ManagementLanHostIP 'setenforce 0'
        ssh $InvokeSSH $ManagementLanHostIP 'grub2-mkconfig -o /boot/grub2/grub.cfg'
        ssh $InvokeSSH $ManagementLanHostIP 'shutdown -r now'
    "
echo " " 
}

function PrepareMinion {
    # Actually created to use for CentOS systems
    ManagementLanHostIP=${ManagementLan}.$1
    HostName=$2

    scp $InvokeSSH -P 22222 sources/persist_netconfig.sh root@${ExtIP}:/root
    Counter=0
    while ! ssh $InvokeSSH -p 22222 root@${ExtIP} "ssh $InvokeSSH $ManagementLanHostIP 'uptime'" ; do
        sleep 5
        Counter=$((${Counter}+5))
        echo "$ManagementLanHostIP not reached for $Counter seconds, trying again..."
    done

    ssh $InvokeSSH -p 22222 root@${ExtIP} "
        ssh $InvokeSSH $ManagementLanHostIP \"sed -i 's/.*GSSAPIAuthentication yes/GSSAPIAuthentication no/' /etc/ssh/sshd_config\"
        ssh $InvokeSSH $ManagementLanHostIP \"sed -i 's/.*UseDNS yes/UseDNS no/' /etc/ssh/sshd_config\"
        ssh $InvokeSSH $ManagementLanHostIP 'systemctl reload sshd'
    "
    echo " " 
    ssh $InvokeSSH -p 22222 root@${ExtIP} "
        scp $InvokeSSH /root/persist_netconfig.sh ${ManagementLanHostIP}:/usr/local/sbin
        scp $InvokeSSH bootstrap-salt.sh ${ManagementLanHostIP}:
        ssh $InvokeSSH $ManagementLanHostIP 'systemctl status network'
        echo Empty_Line
        ssh $InvokeSSH $ManagementLanHostIP 'ip r s'
        ssh $InvokeSSH $ManagementLanHostIP 'bash -x /usr/local/sbin/persist_netconfig.sh '"$ProductiveLanVirtIP"''
    "
    DBHostNet=( $(ssh $InvokeSSH -p 22222 root@${ExtIP} "ssh $InvokeSSH $ManagementLanHostIP \"ip a s | fgrep ${MainSubNet}. | cut -d ' ' -f12,6\"") )

    echo ${DBHostNet[*]}

    for i in $(seq 0 ${#DBHostNet}) ; do
        echo ${DBHostNet[$i]} 
        if [[ "${DBHostNet[$i]}" =~ "${ProductiveLan}" ]] ; then
            if [[ "${DBHostNet[$i+1]}" != "" ]] ; then
               DBHostNetPubDevice=${DBHostNet[$i+1]}
            fi
        elif [[ "${DBHostNet[$i]}" =~ "${PostgreSQLPartnerLan}" ]] ; then
            if [[ "${DBHostNet[$i+1]}" != "" ]] ; then
               DBHostNetPartnerDevice=${DBHostNet[$i+1]}
            fi
        fi
    done

    ssh $InvokeSSH -p 22222 root@${ExtIP} "
        ssh $InvokeSSH $ManagementLanHostIP '/usr/bin/yum clean all'
    "
    ssh $InvokeSSH -p 22222 root@${ExtIP} "
        ssh $InvokeSSH $ManagementLanHostIP 'sh bootstrap-salt.sh -A management1 -i '"$HostName"''
    "
    ssh $InvokeSSH -p 22222 root@${ExtIP} "
        ssh $InvokeSSH $ManagementLanHostIP \"sed -i 's/.startup_states:.*/startup_states: highstate/' /etc/salt/minion\"
        ssh $InvokeSSH $ManagementLanHostIP \"sed -i 's/.log_level_logfile:.*/log_level_logfile: info/' /etc/salt/minion\"
        ssh $InvokeSSH $ManagementLanHostIP 'shutdown -r now'
    "
}

function PostgresCluster {

    ( set -o posix ; set ) >/tmp/PostgresDBHostVariables.$$.before

    FullVDC=$(RetrievFullVDC $VirtualDC)
    ExtIP=$(echo $FullVDC | grep -E -o 'ips[^(dhcp)]*' | grep -m 1 '",' | tr -d ';[],":' | cut -d ' ' -f 5)
    ManagementLanID=$(echo $FullVDC | grep --colour -o -E "${ManagementLan}.{,40}lan[^,]+" | grep -m 1 -E -o '[0-9]+$')
    CountryPlace=( $(echo $FullVDC | grep -o -m 1 -E "location.*?version*" | grep -o -E '[a-z]*/[a-z]*' | tr '/' ' ') )
    Country=${CountryPlace[0]}
    Place=${CountryPlace[1]}
    
    HostID1=$(DBHost Postgres_${FileSystem}_${CentOSversion}-server_1 $ManagementLanID 5 $VDC | grep -m 1 -E -o "[a-z0-9-]*$")
    HostID2=$(DBHost Postgres_${FileSystem}_${CentOSversion}-server_2 $ManagementLanID 6 $VDC | grep -m 1 -E -o "[a-z0-9-]*$")

    PartnerLanID=$(CreateInternalLan PostgreSQL $VDC )
    PartnerLanNic=$(AddInternalNic $HostID1 $PartnerLanID ${PostgreSQLPartnerLan}.1 $VDC)
    PartnerLanNic=$(AddInternalNic $HostID2 $PartnerLanID ${PostgreSQLPartnerLan}.2 $VDC)
    ProductiveLanID=$(echo $FullVDC | grep -E -o '\[ "'${ProductiveLan}'.{50}' | cut -d ' ' -f9 | uniq | tr -d ',')
    PartnerLanNic=$(AddInternalNic $HostID1 $ProductiveLanID ${ProductiveLan}.4 $VDC)
    PartnerLanNic=$(AddInternalNic $HostID2 $ProductiveLanID ${ProductiveLan}.5 $VDC)

    PrepareMinion 5 Postgres_${FileSystem}_${CentOSversion}-server_1
    PrepareMinion 6 Postgres_${FileSystem}_${CentOSversion}-server_2

    ( set -o posix ; set ) >/tmp/PostgresDBHostVariables.$$.after

}

