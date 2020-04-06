adjust grub-conf:
  file.replace:
    - name: /etc/default/grub
    - pattern: "rhgb quiet"
    - repl: "rhgb selinux=0 quiet"
    - show_changes: True
    - backup: false
    
install_httpd:
  pkg.installed:
    - name: httpd
    - skip_verify: true

make sure httpd is running:
  service.running:
    - name: httpd.service
    - enable: true
    - require:
      - install_httpd

pgpool_to_sudoers:
  file.append:
    - name: /etc/sudoers
    - text: |
        pgpool ALL=(postgres) NOPASSWD: /var/lib/pgsql/bin/cluster_connection.sh
        pgpool ALL=(postgres) NOPASSWD: /bin/tee /var/lib/pgsql/postgres_master
        pgpool ALL=(root) NOPASSWD: /usr/sbin/ip
        pgpool ALL=(root) NOPASSWD: /usr/sbin/arping
    - unless: grep "pgpool ALL=" /etc/sudoers

pgpool:
  user.present:
    - name: pgpool
    - fullname: pgpool
    - shell: /bin/bash
    - home: /home/pgpool

/etc/pgpool-II-10:
  file.directory:
    - user: pgpool
    - group: pgpool
    - dir_mode: 755
    - file_mode: 644
    - recurse:
      - user
      - group
      - mode
    - require:
      - pgpool

/etc/pgpool-II-10/credentials:
  file.managed:
    - create: true
    - user: pgpool
    - group: pgpool
    - mode: 640 
    - contents:
      - 'pgpool:e98f3c3b9c0956d643a5d03cb9afad33'
    - require:
      - pgpool

/home/pgpool/.pcppass:
  file.managed:
    - user: pgpool
    - group: pgpool
    - mode: 600
    - contents:
      - '*:*:pgpool:re6iequesieL'

/var/run/pgpool-II-10:
  file.directory:
    - user: pgpool
    - group: pgpool
    - mode: 770
    - makedirs: True

/var/lib/pgsql/bin:
  file.directory:
    - user: postgres
    - group: postgres
    - mode: 770
    - makedirs: True

/var/lib/pgsql/tmp:
  file.directory:
    - user: postgres
    - group: postgres
    - mode: 770
    - makedirs: True

sync pcp.conf:
  file.managed:
    - name: /etc/pgpool-II-10/pcp.conf
    - source: /etc/pgpool-II-10/pcp.conf.sample
    - user: pgpool
    - group: pgpool
    - mode: 640

credentials_to_pcp.conf:
  file.append:
    - name: /etc/pgpool-II-10/pcp.conf
    - text: |
        pgpool:96395970137db298245b390fb9b226e2
    - require:
      - sync pcp.conf

enable wal_log_hints:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#wal_log_hints = off"
    - repl: "wal_log_hints = on"
    - show_changes: True
    - backup: false

add_pg_ctl:
  file.append:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - text: "pgpool.pg_ctl = '/usr/pgsql-10/bin/pg_ctl'"
    - require:
      - enable wal_log_hints

postgresql.conf_master:
  file.copy:
    - name: /var/lib/pgsql/10/data/postgresql.conf_master
    - source: /var/lib/pgsql/10/data/postgresql.conf
    - user: postgres
    - group: postgres
    - mode: 600
    - force: true
    - require:
      - add_pg_ctl

adjust archive_mode:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf_master
    - pattern: "#archive_mode = off"
    - repl: "archive_mode = on"
    - show_changes: True
    - backup: false
    - require:
      - postgresql.conf_master
    
adjust wal_senders:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf_master
    - pattern: "#max_wal_senders = 0"
    - repl: "max_wal_senders = 4"
    - show_changes: True
    - backup: false
    - require:
      - postgresql.conf_master

adjust wal_segments:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf_master
    - pattern: "#wal_keep_segments = 0"
    - repl: "wal_keep_segments = 1536"
    - show_changes: True
    - backup: false
    - require:
      - postgresql.conf_master

postgresql.conf_standby:
  file.copy:
    - name: /var/lib/pgsql/10/data/postgresql.conf_standby
    - source: /var/lib/pgsql/10/data/postgresql.conf
    - user: postgres
    - group: postgres
    - mode: 600
    - require:
      - add_pg_ctl

adjust hot_standby:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf_standby
    - pattern: '#hot_standby = off'
    - repl: 'hot_standby = on'
    - show_changes: True
    - backup: false
    - require:
      - postgresql.conf_standby

adjust hot_feedback:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf_standby
    - pattern: '#hot_standby_feedback = off'
    - repl: 'hot_standby_feedback = on'
    - show_changes: True
    - backup: false
    - require:
      - adjust hot_standby

/var/lib/pgsql/postgresql.trigger.5432:
  file.absent

sync pool_hba.conf:
  file.managed:
    - name: /etc/pgpool-II-10/pool_hba.conf
    - source: /etc/pgpool-II-10/pool_hba.conf.sample
    - user: pgpool
    - group: pgpool
    - mode: 640

/etc/pgpool-II-10/pool_hba.conf:
  file.append:
    - text: |
        host    all         all         10.99.4.0/24          trust
        host    all         all         10.99.3.0/24          trust

/usr/lib64/libpcp.so.1:
  file.symlink:
    - target: /usr/pgpool-10/lib/libpcp.so.1

/home/pgpool/bin/AddNode.sh:
  file.managed:
    - user: pgpool
    - group: pgpool
    - mode: 770 
    - create: true
    - makedirs: true
    - contents: |
        #!/bin/bash
        short_date=$(/bin/date +%s)
        exec 100>>/tmp/"$short_date"_AddNode.log
        BASH_XTRACEFD=100
        StatusFile=/tmp/pgpool.node.state
        set -x
        date > $StatusFile
        NodeCount=$(pcp_node_count -h /var/run/pgpool-II-10/ -w)
        for i in $(seq 0 $((${NodeCount}-1))) ; do
            NodeState=( $(pcp_node_info -U pgpool -n ${i} -h /var/run/pgpool-II-10 -w) )
            NodeLocalIP=$(ip a s | grep "${NodeState[0]}/")
            NodeConnectState=${NodeState[2]} 
            if [ "$NodeLocalIP" != "" ] && [ "$NodeConnectState" -eq "3" ] ; then
                pcp_attach_node -U pgpool -n ${i} -h /var/run/pgpool-II-10 -w -v
            fi  
            echo ${NodeState[*]} >> $StatusFile
        done

check_config_change_master:
  grains.present:
    - name: postgres_master_config_changed
    - value: done
    - onchanges:
      - file: /var/lib/pgsql/10/data/postgresql.conf_master

check_config_change_standby:
  grains.present:
    - name: postgres_standby_config_changed
    - value: done
    - onchanges:
      - file: /var/lib/pgsql/10/data/postgresql.conf_standby
    - require:
      - adjust hot_feedback

{% if salt['grains.get']('pgpool.conf-base') != 'done' %}
sync pgpool-config:
  file.managed:
    - user: pgpool
    - group: pgpool
    - name: /etc/pgpool-II-10/pgpool.conf
    - source: /etc/pgpool-II-10/pgpool.conf.sample-stream
    - mode: 640
    - makedirs: True

pgpool.conf-base_done:
  grains.present:
    - name: pgpool.conf-base
    - value: done
{% endif %}

adjust_backend_hostname0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "backend_hostname0 = 'host1'"
    - repl: "backend_hostname0 = '10.99.4.1'"
    - show_changes: True
    - backup: false

adjust_backend_data_directory0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "backend_data_directory0 = '/data'"
    - repl: "backend_data_directory0 = '/var/lib/pgsql/10/data'"
    - show_changes: True
    - backup: false

adjust_backend_hostname1:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#backend_hostname1 = 'host2'"
    - repl: "backend_hostname1 = '10.99.4.2'"
    - show_changes: True
    - backup: false

adjust_backend_port1:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#backend_port1 = 5433"
    - repl: "backend_port1 = 5432"
    - show_changes: True
    - backup: false

adjust_backend_weight1:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#backend_weight1 = 1"
    - repl: "backend_weight1 = 1"
    - show_changes: True
    - backup: false

adjust_backend_data_directory1:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#backend_data_directory1 = '/data1'"
    - repl: "backend_data_directory1 = '/var/lib/pgsql/10/data'"
    - show_changes: True
    - backup: false

adjust_backend_flag1:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#backend_flag1 = 'ALLOW_TO_FAILOVER'"
    - repl: "backend_flag1 = 'ALLOW_TO_FAILOVER'"
    - show_changes: True
    - backup: false

adjust_listen_addresses:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "listen_addresses = 'localhost'"
    - repl: "listen_addresses = '*'"
    - show_changes: True
    - backup: false

adjust_other_pgpool_port0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "port = 9999"
    - repl: "other_pgpool_port0 = 9999"
    - show_changes: True
    - backup: false

adjust_other_wd_port0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#other_wd_port0 = 9000"
    - repl: "other_wd_port0 = 9000"
    - show_changes: True
    - backup: false

adjust_socket_dir:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "socket_dir = '/tmp'"
    - repl: "socket_dir = '/var/run/pgpool-II-10'"
    - show_changes: True
    - backup: false

adjust_pcp_socket_dir:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "pcp_socket_dir = '/tmp'"
    - repl: "pcp_socket_dir = '/var/run/pgpool-II-10'"
    - show_changes: True
    - backup: false

adjust_wd_ipc_socket_dir:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_ipc_socket_dir = '/tmp'"
    - repl: "wd_ipc_socket_dir = '/var/run/pgpool-II-10'"
    - show_changes: True
    - backup: false

adjust_enable_pool_hba:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "enable_pool_hba = off"
    - repl: "enable_pool_hba = on"
    - show_changes: True
    - backup: false

adjust_pool_passwd:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "pool_passwd = 'pool_passwd'"
    - repl: "pool_passwd = 'credentials'"
    - show_changes: True
    - backup: false

adjust_log_destination:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "log_destination = 'stderr'"
    - repl: "log_destination = 'stderr,syslog'"
    - show_changes: True
    - backup: false

adjust_pid_file_name:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "pid_file_name = '/var/run/pgpool/pgpool.pid'"
    - repl: "pid_file_name = '/var/run/pgpool-II-10/pgpool.pid'"
    - show_changes: True
    - backup: false

adjust_sr_check_period:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "sr_check_period = 10"
    - repl: "sr_check_period = 5"
    - show_changes: True
    - backup: false

adjust_sr_check_user:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "sr_check_user = 'nobody'"
    - repl: "sr_check_user = 'postgres'"
    - show_changes: True
    - backup: false

adjust_sr_check_password:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "sr_check_password = ''"
    - repl: "sr_check_password = 'Xoogh1iechoo'"
    - show_changes: True
    - backup: false

adjust_health_check_period:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "health_check_period = 0"
    - repl: "health_check_period = 5"
    - show_changes: True
    - backup: false

adjust_health_check_timeout:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "health_check_timeout = 20"
    - repl: "health_check_timeout = 5"
    - show_changes: True
    - backup: false

adjust_health_check_user:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "health_check_user = 'nobody'"
    - repl: "health_check_user = 'postgres'"
    - show_changes: True
    - backup: false

adjust_health_check_password:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "health_check_password = ''"
    - repl: "health_check_password = 'Xoogh1iechoo'"
    - show_changes: True
    - backup: false

adjust_health_check_database:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "health_check_database = ''"
    - repl: "health_check_database = 'postgres'"
    - show_changes: True
    - backup: false

adjust_health_check_max_retries:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "health_check_max_retries = 0"
    - repl: "health_check_max_retries = 3"
    - show_changes: True
    - backup: false

adjust_connect_timeout:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "connect_timeout = 10000"
    - repl: "connect_timeout = 5000"
    - show_changes: True
    - backup: false

adjust_failover_command:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "failover_command = ''"
    - repl: "failover_command = 'sudo -u postgres /var/lib/pgsql/bin/cluster_connection.sh -f failover_command -t %H'"
    - show_changes: True
    - backup: false

adjust_search_primary_node_timeout:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "search_primary_node_timeout = 300"
    - repl: "search_primary_node_timeout = 5"
    - show_changes: True
    - backup: false

adjust_recovery_user:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "recovery_user = 'nobody'"
    - repl: "recovery_user = 'repuser'"
    - show_changes: True
    - backup: false

adjust_recovery_password:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "recovery_password = ''"
    - repl: "recovery_password = 're6iequesieL'"
    - show_changes: True
    - backup: false

adjust_use_watchdog:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "use_watchdog = off"
    - repl: "use_watchdog = on"
    - show_changes: True
    - backup: false

adjust_trusted_servers:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "trusted_servers = ''"
    - repl: "trusted_servers = '10.99.1.1,10.99.1.4,10.99.3.3'"
    - show_changes: True
    - backup: false

# Ping path ist not the one of ping but from sudo...
adjust_ping_path:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "ping_path = '/bin'"
    - repl: "ping_path = '/usr/bin'"
    - show_changes: True
    - backup: false

# Arping path ist not the one of arping but from sudo...
adjust_arpping_path:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "arping_path = '/usr/sbin'"
    - repl: "arping_path = '/usr/bin'"
    - show_changes: True
    - backup: false

adjust_delegate_IP:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "delegate_IP = ''"
    - repl: "delegate_IP = '10.99.3.6'"
    - show_changes: True
    - backup: false

# Path is from sudo...
adjust_if_cmd_path:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "if_cmd_path = '/sbin'"
    - repl: "if_cmd_path = '/usr/bin'"
    - show_changes: True
    - backup: false

adjust_wd_escalation_command:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_escalation_command = ''"
    - repl: "wd_escalation_command = 'sudo -u postgres /var/lib/pgsql/bin/cluster_connection.sh -f wd_escalation ; /home/pgpool/bin/AddNode.sh'"
    - show_changes: True
    - backup: false

adjust_wd_lifecheck_method:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_lifecheck_method = 'heartbeat'"
    - repl: "wd_lifecheck_method = 'query'"
    - show_changes: True
    - backup: false

adjust_wd_interval:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_interval = 10"
    - repl: "wd_interval = 3"
    - show_changes: True
    - backup: false

adjust_wd_heartbeat_deadtime:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_heartbeat_deadtime = 30"
    - repl: "wd_heartbeat_deadtime = 5"
    - show_changes: True
    - backup: false

adjust_heartbeat_device0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "heartbeat_device0 = ''"
    - repl: "heartbeat_device0 = 'eth1'"
    - show_changes: True
    - backup: false

adjust_wd_life_point:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_life_point = 3"
    - repl: "wd_life_point = 20"
    - show_changes: True
    - backup: false

adjust_wd_lifecheck_user:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_lifecheck_user = 'nobody'"
    - repl: "wd_lifecheck_user = 'postgres'"
    - show_changes: True
    - backup: false

adjust_wd_lifecheck_password:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_lifecheck_password = ''"
    - repl: "wd_lifecheck_password = 'Xoogh1iechoo'"
    - show_changes: True
    - backup: false

copy authorized_keys:
  file.copy:
    - name: /var/lib/pgsql/.ssh/authorized_keys
    - source: /var/lib/pgsql/dumps/authorized_keys
    - dir_mode: 700
    - force: true
    - user: postgres
    - group: postgres
    - mode: 600

disable_selinux:
  cmd.run:
    - user: root
    - name: '(/usr/sbin/setenforce 0; true)' 
  
create_follow_master_command:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "follow_master_command = ''"
    - repl: "follow_master_command = '/home/pgpool/bin/AddNode.sh'"
    - show_changes: True
    - backup: false

log_connections:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "log_connections = off"
    - repl: "log_connections = on"
    - show_changes: True
    - backup: false

log_hostname:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "log_hostname = off"
    - repl: "log_hostname = on"
    - show_changes: True
    - backup: false

log_statement:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "log_statement = off"
    - repl: "log_statement = on"
    - show_changes: True
    - backup: false

log_per_node_statement:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "log_per_node_statement = off"
    - repl: "log_per_node_statement = on"
    - show_changes: True
    - backup: false

log_client_messages:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "log_client_messages = off"
    - repl: "log_client_messages = on"
    - show_changes: True
    - backup: false

log_error_verbosity:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#log_error_verbosity = default"
    - repl: "log_error_verbosity = verbose"
    - show_changes: True
    - backup: false

log_min_messages:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#log_min_messages = warning"
    - repl: "log_min_messages = log"
    - show_changes: True
    - backup: false

failover_when_quorum_exists:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "failover_require_consensus = on"
    - repl: "failover_require_consensus = off"
    - show_changes: True
    - backup: false

allow_multiple_failover_requests_from_node:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "allow_multiple_failover_requests_from_node = off"
    - repl: "allow_multiple_failover_requests_from_node = on"
    - show_changes: True
    - backup: false

enable_consensus_with_half_votes:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "enable_consensus_with_half_votes = off"
    - repl: "enable_consensus_with_half_votes = on"
    - show_changes: True
    - backup: false

