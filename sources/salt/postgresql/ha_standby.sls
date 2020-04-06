{% if salt['grains.get']('ha_standby-setup') != 'done' %}
create_recovery.conf_onstandby:
  file.managed:
    - name: /var/lib/pgsql/10/data/recovery.conf
    - user: postgres
    - group: postgres
    - mode: 600

recovery.conf_standby:
  file.append:
    - name: /var/lib/pgsql/10/data/recovery.conf
    - text: |
        archive_cleanup_command = '/usr/pgsql-10/bin/pg_archivecleanup /var/lib/pgsql/archive %r'
        restore_command = 'test -f /var/lib/pgsql/archive/%f && cp /var/lib/pgsql/archive/%f %p'
        standby_mode = on
        primary_conninfo = 'host=10.99.4.1 user=repuser password=wuR8caifueto'
        trigger_file = '/var/lib/pgsql/postgresql.trigger.5432'
    - require: 
      - create_recovery.conf_onstandby

postgresql.recovery.conf:
  file.copy:
    - name: /var/lib/pgsql/10/data/recovery.conf.deactivated
    - source: /var/lib/pgsql/10/data/recovery.conf
    - user: postgres
    - group: postgres
    - mode: 600
    - force: true
    - require:
      - recovery.conf_standby

adjust archive_command_onstandby:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf_master
    - pattern: "#archive_command = ''"
    - repl: "archive_command = '/usr/bin/scp -i /var/lib/pgsql/.ssh/id_rsa -o StrictHostKeyChecking=no %p postgres@10.99.4.1:/var/lib/pgsql/archive/%f'"
    - show_changes: true
    - backup: false

activate_conf_standby:
  file.copy:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - source: /var/lib/pgsql/10/data/postgresql.conf_standby
    - user: postgres
    - group: postgres
    - mode: 600
    - force: true
    - unless: diff /var/lib/pgsql/10/data/postgresql.conf /var/lib/pgsql/10/data/postgresql.conf_standby

stop_db_as_postgres:
  cmd.run:
    - user: postgres
    - name: 'if diff /var/lib/pgsql/10/data/postgresql.conf /var/lib/pgsql/10/data/postgresql.conf_standby ; then su -l postgres -c "source /var/lib/pgsql/.bash_profile; (pg_ctl stop 2>&1 > /dev/null &)" ; fi' 
    - require: 
      - activate_conf_standby

come_after_master:
  cmd.run:
    - name: sleep 90
    - require: 
      - stop_db_as_postgres

{% if salt['grains.get']('pg_basebackup') != 'imported' %}

save_pg_configs:
  cmd.run:
    - cwd: '/var/lib/pgsql/tmp'
    - runas: postgres
    - names:
      - cp -av /var/lib/pgsql/10/data/*conf* .
    - require: 
      - recovery.conf_standby
      - activate_conf_standby

clean_pg_datadir:
  cmd.run:
    - names:
      - rm -rf /var/lib/pgsql/10/data/*
    - require: 
      - save_pg_configs

sync databases:
  cmd.run:
    - names:
      - XX=0 ; while [[ ! -e /var/lib/pgsql/10/data/postgresql.conf ]] && [[ $XX -lt 30 ]] ; do XX=$((${XX}+1)) ; pg_basebackup -D /var/lib/pgsql/10/data/ -h 10.99.4.1 -U repuser -c fast -v --wal-method=stream ; echo Tried basebackup for $XX times ; sleep 5 ; done
    - runas: postgres
    - require: 
      - stop_db_as_postgres
      - clean_pg_datadir

restore pg_configs:
  cmd.run:
    - names:
      - cp -av /var/lib/pgsql/tmp/*conf* /var/lib/pgsql/10/data/. 
    - runas: postgres
    - require: 
      - sync databases

postgres-setup-done-grain:
  grains.present: 
    - name: postgresql-setup
    - value: done
    - require: 
      - sync databases

sync database done:
  grains.present: 
    - name: pg_basebackup
    - value: imported 
    - require: 
      - sync databases

{% endif %}

restart_new_db_as_postgres:
  cmd.run:
    - user: postgres
    - name: 'su -l postgres -c "source /var/lib/pgsql/.bash_profile ; (pg_ctl start 2>&1 > /dev/null &)"'
    - unless: ps cax | grep postgres
    - require:
      - stop_db_as_postgres

config_change_standby_done:
  grains.present:
    - name: postgres_standby_config_changed
    - value: none

standby_wd_hostname:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_hostname = ''"
    - repl: "wd_hostname = '10.99.4.2'"
    - show_changes: True
    - backup: false

standby_wd_priority:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_priority = 1"
    - repl: "wd_priority = 5"
    - show_changes: True
    - backup: false

standby_heartbeat_destination0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "heartbeat_destination0 = 'host0_ip1'"
    - repl: "heartbeat_destination0 = '10.99.4.1'"
    - show_changes: True
    - backup: false

standby_adjust_other_pgpool_hostname0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#other_pgpool_hostname0 = 'host0'"
    - repl: "other_pgpool_hostname0 = '10.99.4.1'"
    - show_changes: True
    - backup: false

adjust_heartbeat_device0_master:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "heartbeat_device0 = ''"
    - repl: "heartbeat_device0 = 'eth1'"
    - show_changes: True
    - backup: false

adjust_if_up_cmd_standby:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "if_up_cmd = .*"
    - repl: "if_up_cmd = 'sudo /usr/sbin/ip addr add $_IP_$/24 dev eth2 label eth2:0'"
    - show_changes: True
    - backup: false

adjust_if_down_cmd_standby:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "if_down_cmd = .*"
    - repl: "if_down_cmd = 'sudo /usr/sbin/ip addr del $_IP_$/24 dev eth2'"
    - show_changes: True
    - backup: false

adjust_arping_cmd_standby:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "arping_cmd = '/usr/bin/sudo /usr/sbin/arping -U .*'"
    - repl: "arping_cmd = 'sudo /usr/sbin/arping -U $_IP_$ -I eth2 -w 1'"
    - show_changes: True
    - backup: false

ha_standby-setup:
  grains.present:
    - name: ha_standby-setup
    - value: done
{% endif %}

