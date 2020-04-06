#!/bin/bash
# Script usable only if just one standby is accompanying the master

short_date=$(/bin/date +%s)
exec 100>>/tmp/"$short_date"_cluster.log
BASH_XTRACEFD=100
set -x

User=$(id | grep -o 'uid=[0-9]*(postgres)')

if [ ! $User ] ; then
    echo "This script must be executed as user postgres!" 
    echo $Help
    exit 2
fi

while test $# -gt 0 ; do
    case "$1" in
        -f) shift
            Function=$1
            shift ;;
        -t) shift
            TargetHost=$1
            shift ;;
         *) echo "ERROR: Unrecognized option $1"
            exit 2 ;;
    esac
done

source ~/.bash_profile
Config=${PGDATA}/postgresql.conf
Recovery=${PGDATA}/recovery.conf
Bin=/var/lib/pgsql/bin
InvokeSCP="scp -o StrictHostKeyChecking=no -o ConnectTimeout=1"
InvokeSSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=1"

FailoverTrigger=/var/lib/pgsql/postgresql.trigger.5432
ClusterNodeStatus=/var/lib/pgsql/ClusterNodeStatus

TimeStamp=$(date +%s)
TimeHR=$(date --date '@'"${TimeStamp}"'')
PartnerNet=10.99.4       
Localhost=$(hostname)
ActiveHost=$(ip a s | grep -o -E "${PartnerNet}.[0-9]*/")
ActiveHost=${ActiveHost%/}
if [ "${ActiveHost##*\.}" == "1" ] ; then PartnerHost=${PartnerNet}.2 ; fi
if [ "${ActiveHost##*\.}" == "2" ] ; then PartnerHost=${PartnerNet}.1 ; fi

function write_ClusterNodeStatus {

	if [ "${PGPoolMaster}" == "" ] ; then PGPoolMaster=$(grep primary /tmp/pgpool.node.state | cut -d ' ' -f1) ; fi

	if ps ax | grep -E "postgres: wal (sender|writer)" > /dev/null ; then 
		HostState="$Localhost is PostgresMaster with $ActiveHost"
	elif ps ax | grep "postgres: wal receiver process" > /dev/null ; then
		HostState="$Localhost is PostgresStandby with $ActiveHost"
	elif [[ "$HostState" == "" ]] ; then
		HostState="$Localhost has not Postgres instance running."
	fi

	(   echo "PGPool and PostgreSQL node status at last watchdog escalation:"
        echo "Time $TimeStamp \"$TimeHR\""
    echo "$HostState"
    echo "$Localhost is PGPoolMaster with $PGPoolMaster"
    ) > $ClusterNodeStatus

}

function wd_escalation {

    if [ "${ActiveHost##*\.}" == "1" ] ; then PGPoolMaster=${PartnerNet}.1 ; PGPoolStandby=${PartnerNet}.2 ; fi
    if [ "${ActiveHost##*\.}" == "2" ] ; then PGPoolMaster=${PartnerNet}.2 ; PGPoolStandby=${PartnerNet}.1 ; fi

    if [ ! -e $ClusterNodeStatus ] && [ -z "$(ps cax | grep postgres)" ]  && \
        $InvokeSSH $PartnerHost '[ ! -e $ClusterNodeStatus ] && [ -z "$(ps cax | grep postgres)" ]'; then
        (pg_ctl start > /dev/null) &
        $InvokeSSH $PartnerHost '(pg_ctl start > /dev/null) &'
        sleep 5
    fi

	write_ClusterNodeStatus 

	cat $ClusterNodeStatus
	$InvokeSCP $ClusterNodeStatus $PGPoolStandby:$ClusterNodeStatus

}

function StopLocalInstance {

    echo "As the local Postgres instance is failing it needs to be stopped."
    pg_ctl stop  || echo $InstanceNotReached
    sleep 3
    if ps cax | grep postgres ; then
        for i in $(ps cax | grep postgres | cut -d ' ' -f1) ; do 
            kill -9 $i 
        done
    fi
}

function StopRemoteInstance {
    if $InvokeSSH $PartnerHost "echo Host $(hostname) still running"  ; then
        echo "As the remote Postgres instance is failing it needs to be stopped."
        $InvokeSSH $PartnerHost "ps cax | grep postgres | cut -d ' ' -f1 | while read ; do kill -9 \$REPLY; done" 
    fi
}

function PromoteStandby {

    touch $FailoverTrigger
    cp ${Config}_master ${Config}
    mv ${Recovery} ${Recovery}.deactivated
    (pg_ctl restart > /dev/null) &
    # Fill in a run check here which is much better then just a sleep command.
    sleep 3

    if ps ax | grep "postgres: wal writer" > /dev/null ; then 
        HostState="$Localhost is PostgresMaster with $ActiveHost"
    elif [[ "$HostState" == "" ]] ; then
        HostState="$Localhost has no Postgres instance running!"
    fi

    if [[ "$PGPoolMaster" == "" ]] ; then PGPoolMaster=$ActiveHost ; fi
    
	echo "$Localhost is PGPoolMaster with $PGPoolMaster"
    
    (   echo "PostgreSQL node status after last Postgres failover:"
        echo "Time $TimeStamp \"$TimeHR\""
        echo "$HostState"
        echo "$Localhost is PGPoolMaster with $PGPoolMaster"
    ) > $ClusterNodeStatus

    cat $ClusterNodeStatus

}

# Curently not used! - pg_rewind does not fit to reconnect after master crash
function DemoteMaster {

    Tmpdir=/var/lib/pgsql/tmp_$$

    pg_ctl stop

    mkdir $Tmpdir
    cd /var/lib/pgsql/10/data/
    cp -av pg_hba.conf postgresql.conf* recovery.* $Tmpdir
    echo Executing pg_rewind -P --source-server="host=${PartnerHost} user=postgres password=KeepItSecret" --target-pgdata /var/lib/pgsql/10/data
    pg_rewind -P --source-server="host=${PartnerHost} user=postgres password=KeepItSecret" --target-pgdata /var/lib/pgsql/10/data
    cp -av $Tmpdir/*conf* .
    cp -v  ${Recovery}.deactivated ${Recovery}
    cp ${Config}_standby ${Config}
    rm -rf $Tmpdir

    (pg_ctl start > /dev/null) &

    cat $ClusterNodeStatus
    $InvokeSCP ${PartnerHost}:${ClusterNodeStatus} $ClusterNodeStatus 
    sleep 3

    if ps ax | grep "wal receiver process" > /dev/null ; then 
        HostState="$Localhost is PostgresStandby with $ActiveHost"
    elif [[ "$HostState" == "" ]] ; then
        HostState="$Localhost has not Postgres instance running!"
    fi
}

function PromoteLocalStandby {
    echo "As the remote Postgres instance failed local standby is to be promoted."
    PromoteStandby
    $InvokeSCP $ClusterNodeStatus $PartnerHost:$ClusterNodeStatus
}

function PromoteRemoteStandby {

    echo "As the local master Postgres instance failed remote standby is to be promoted."
    $InvokeSSH $PartnerHost 'source ~/.bash_profile ; bin/cluster_connection.sh -f PromoteStandby'
    $InvokeSCP $PartnerHost:$ClusterNodeStatus $ClusterNodeStatus

}

function check_node_instance {

    if [ ! -e ${ClusterNodeStatus} ] ; then echo ${ClusterNodeStatus} missing!! Exiting. ; exit 2 ;fi

    DBInstance=$(grep -E 'Postgres(S|M)' $ClusterNodeStatus)

    if [[ "${DBInstance}" =~ "Master" ]] ; then

        export DBMasterIP=${DBInstance##* }
        export DBInstance=Master

        if [ "${DBMasterIP##*\.}" == "1" ] ; then export DBStandbyIP=${PartnerNet}.2 ; fi
        if [ "${DBMasterIP##*\.}" == "2" ] ; then export DBStandbyIP=${PartnerNet}.1 ; fi

    elif [[ "${DBInstance}" =~ "Standby" ]] ; then

        export DBStandbyIP=${DBInstance##* }
        export DBInstance=Standby

        if [ "${DBStandbyIP##*\.}" == "1" ] ; then export DBMasterIP=${PartnerNet}.2 ; fi
        if [ "${DBStandbyIP##*\.}" == "2" ] ; then export DBMasterIP=${PartnerNet}.1 ; fi

    fi

    export InstanceNotReached="remote $DBInstance not reachable"
    export HostNotReached="remote host $PartnerHost not reachable"

}

function failover_command {

    check_node_instance

    if  [[ "$DBMasterIP" == "$ActiveHost" ]] && [[ ! $(ps ax | grep -E ": wal (sender|writer)") ]] ; then
        StopLocalInstance
        PromoteRemoteStandby
    elif  [[ "$DBMasterIP" == "$ActiveHost" ]] ; then
        echo "Failover command on master, master persists."
        exit
    elif  [[ "$DBStandbyIP" == "$ActiveHost" ]] ; then
        StopRemoteInstance 
        PromoteLocalStandby 
    elif [[ "$DBStandbyIP" == "$PartnerHost" ]] ; then
        StopLocalInstance 
        PromoteRemoteStandby
    fi

}

function recovery {

    if ps cax | grep postgres ; then
        if [ ! -e ${ClusterNodeStatus} ] ; then
            sleep 30
            ${InvokeSCP} ${PartnerHost}:${ClusterNodeStatus} ${ClusterNodeStatus}
            if [ ! -e ${ClusterNodeStatus} ] ; then
                write_ClusterNodeStatus 
                ${InvokeSCP} ${ClusterNodeStatus} ${PartnerHost}:${ClusterNodeStatus}
            fi
        fi
        echo "Postgres already running, skipping new start."

        exit 0
    fi

    LocalUptime=$(cat /proc/uptime | cut -d '.' -f1)
    Round=0
    while ! PartnerUptime=$(${InvokeSSH} ${PartnerHost} "cat /proc/uptime" | cut -d '.' -f1) && [[ "$Round" -lt "21" ]] ; do
        sleep 2
        Round=$((${Round}+1))
    done

    if [[ "${Round}" == "21" ]] ; then
        echo 'FATAL: Partnerhost not reacheable during local recovery!'
    else
        UptimeDiff=$((${PartnerUptime}-${LocalUptime}))
        if [[ "${UptimeDiff}" =~ "-" ]] ; then UptimeDiff=0 ; fi

        if [[ "${UptimeDiff}" -lt "20" ]] ; then sleep ${UptimeDiff} ; fi

        ${InvokeSCP} ${PartnerHost}:${ClusterNodeStatus} ${ClusterNodeStatus}.${TimeStamp}
        RemoteNodeStateTime=$(grep -m 1 -o -P '[0-9]{10}' ${ClusterNodeStatus}.${TimeStamp})
    fi

    LocalNodeStateTime=$(grep -m 1 -o -P '[0-9]{10}' ${ClusterNodeStatus})

    if [ -e ${ClusterNodeStatus}.${TimeStamp} ] && [[ "${RemoteNodeStateTime}" -gt "${LocalNodeStateTime}" ]] ; then
        echo "Using remote ClusterNodeStatus for recovery."
        mv -v ${ClusterNodeStatus}.${TimeStamp} ${ClusterNodeStatus}
    else
        echo "Using local ClusterNodeStatus for recovery."
        rm -v ${ClusterNodeStatus}.${TimeStamp}
    fi

    check_node_instance

     if   [[ "${ActiveHost}" == "${DBMasterIP}" ]]   && diff ${Config} ${Config}_master > /dev/null ; then
         echo "Starting DB as master instance."
        (pg_ctl start > /dev/null)
     elif [[ "${ActiveHost}" == "${DBStandbyIP}" ]]  && diff ${Config} ${Config}_standby > /dev/null ; then
         echo "Starting DB as standby instance."
         init_repl
         #(pg_ctl start > /dev/null)
     elif [[ "${PartnerHost}" == "${DBMasterIP}" ]]  && diff ${Config} ${Config}_standby > /dev/null ; then
         echo "Starting DB as standby instance."
         init_repl
         #(pg_ctl start > /dev/null)
     elif [[ "${PartnerHost}" == "${DBStandbyIP}" ]] && diff ${Config} ${Config}_master > /dev/null ; then
         echo "Starting DB as master instance."
        (pg_ctl start > /dev/null)
     elif [[ "${ActiveHost}" == "${DBStandbyIP}" ]]  && ! diff ${Config} ${Config}_standby > /dev/null ; then
         echo "Initiate DB as standby instance."
         init_repl
     elif [[ "${PartnerHost}" == "${DBMasterIP}" ]]  && ! diff ${Config} ${Config}_standby > /dev/null ; then
         echo "Initiate DB as standby instance."
         init_repl
     else
        echo 'FATAL: Did not find suitable DB state to start!'
        # exit 2
     fi

}

function failback_command {

    if [[ "$TargetHost" == "$PartnerHost" ]] ; then

        $InvokeSCP ${ClusterNodeStatus} ${PartnerHost}:$ClusterNodeStatus 
        $InvokeSSH $PartnerHost "source ~/.bash_profile ; bin/cluster_connection.sh -f init_repl -t $ActiveHost"

    elif [[ "$TargetHost" == "$ActiveHost" ]] ; then

        $InvokeSCP ${PartnerHost}:${ClusterNodeStatus} $ClusterNodeStatus 
        init_repl

    fi

}

function init_repl {

    if ! ps ax | grep "postgres: wal receiver" | grep -v grep > /dev/null ; then
    
        Tmpdir=/var/lib/pgsql/tmp_$$
        pg_ctl stop
        mkdir $Tmpdir
        cd /var/lib/pgsql/10/data/
        ls -l *conf*
        echo x1x ${Recovery}
        (test -e ${Recovery} && echo OK) || echo "Not ok"
        cat ${Recovery}
        echo x1x ${Recovery}.deactivated
        (test -e ${Recovery}.deactivated && echo OK) || echo "Not ok"
        cat ${Recovery}.deactivated
        cp -av pg_hba.conf postgresql.conf* recovery.* $Tmpdir
        rm -rf /var/lib/pgsql/archive/* /var/lib/pgsql/10/data/*

        count=0
        while ! pg_basebackup -D /var/lib/pgsql/10/data/ -h $PartnerHost -U repuser -c fast -v --wal-method=stream && [[ $count -lt 11 ]] ; do
            count=$((${count}+1)) ;
            sleep 5 ;
            echo "Basebackup failed ${count} times, trying again at most 10 times!"
        done
        if [[ $count -eq 11 ]] ; then 
            echo "Basebackup failed to many times!"
            exit 2
        fi

        cp -av $Tmpdir/*conf* .
        cp postgresql.conf_standby postgresql.conf
        cp -v  ${Recovery}.deactivated ${Recovery}
        echo x2x ${Recovery}
        (test -e ${Recovery} && echo OK) || echo "Not ok"
        cat ${Recovery}
        echo x2x ${Recovery}.deactivated
        (test -e ${Recovery}.deactivated && echo OK) || echo "Not ok"
        cat ${Recovery}.deactivated
        rm -vrf $Tmpdir
        (pg_ctl start > /dev/null) &

    fi
}

$Function
