{% if salt['grains.get']('ha_master-setup') != 'done' %}
create_recovery.conf_onmaster:
  file.managed:
    - name: /var/lib/pgsql/10/data/recovery.conf.deactivated
    - user: postgres
    - group: postgres
    - mode: 600

recovery.conf_former_master:
  file.append:
    - name: /var/lib/pgsql/10/data/recovery.conf.deactivated
    - text: |
        archive_cleanup_command = '/usr/pgsql-10/bin/pg_archivecleanup /var/lib/pgsql/archive %r'
        restore_command = 'test -f /var/lib/pgsql/archive/%f && cp /var/lib/pgsql/archive/%f %p'
        standby_mode = on
        primary_conninfo = 'host=10.99.4.2 user=repuser password=wuR8caifueto'
        trigger_file = '/var/lib/pgsql/postgresql.trigger.5432'
    - require:
      - create_recovery.conf_onmaster

adjust archive_command_onmaster:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf_master
    - pattern: "#archive_command = ''"
    - repl: "archive_command = '/usr/bin/scp -i /var/lib/pgsql/.ssh/id_rsa -o StrictHostKeyChecking=no %p postgres@10.99.4.2:/var/lib/pgsql/archive/%f'"
    - show_changes: true
    - backup: false

activate_conf_master:
  file.copy:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - source: /var/lib/pgsql/10/data/postgresql.conf_master
    - user: postgres
    - group: postgres
    - mode: 600
    - force: true
    - onchanges:
      - file: /var/lib/pgsql/10/data/postgresql.conf_master
    - require:
      - adjust archive_command_onmaster

start_new_db_as_postgres:
  cmd.run:
    - user: postgres
    - name: 'su -l postgres -c "source /var/lib/pgsql/.bash_profile ; (pg_ctl start 2>&1 > /dev/null &)"'
    - require:
      - activate_conf_master

config_change_master_done:
  grains.present:
    - name: postgres_master_config_changed
    - value: none
    - require:
      - activate_conf_master

postgres_user_pw:
  cmd.run:
    - user: root
    - name: /usr/bin/psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'Vuuji7ohbieC'"
    - require:
      - start_new_db_as_postgres

replication_pw:
  postgres_user.present:
    - name: repuser
    - password: FirstAttemptBeforeChangeWithNewSHA
    - encrypted: true
    - replication: true
    - require:
      - start_new_db_as_postgres

replication_change_pw:
  cmd.run:
    - user: root
    - name: /usr/bin/psql -U postgres -c "ALTER USER repuser WITH PASSWORD 'wuR8caifueto'"
    - require:
      - replication_pw

DB_pgpool-recovery:
  cmd.run:
    - name: 'su -l postgres -c "/usr/bin/psql -f /usr/pgsql-10/share/extension/pgpool-recovery.sql template1"'
    - user: postgres

master_wd_hostname:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_hostname = ''"
    - repl: "wd_hostname = '10.99.4.1'"
    - show_changes: True
    - backup: false

master_wd_priority:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "wd_priority = 1"
    - repl: "wd_priority = 10"
    - show_changes: True
    - backup: false

master_heartbeat_destination0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "heartbeat_destination0 = 'host0_ip1'"
    - repl: "heartbeat_destination0 = '10.99.4.2'"
    - show_changes: True
    - backup: false

master_adjust_other_pgpool_hostname0:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "#other_pgpool_hostname0 = 'host0'"
    - repl: "other_pgpool_hostname0 = '10.99.4.2'"
    - show_changes: True
    - backup: false

adjust_heartbeat_device0_master:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "heartbeat_device0 = ''"
    - repl: "heartbeat_device0 = 'eth1'"
    - show_changes: True
    - backup: false

adjust_if_up_cmd_master:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "if_up_cmd = .*"
    - repl: "if_up_cmd = 'sudo /usr/sbin/ip addr add $_IP_$/24 dev eth2 label eth2:0'"
    - show_changes: True
    - backup: false

adjust_if_down_cmd_master:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "if_down_cmd = .*"
    - repl: "if_down_cmd = 'sudo /usr/sbin/ip addr del $_IP_$/24 dev eth2'"
    - show_changes: True
    - backup: false

adjust_arping_cmd_master:
  file.replace:
    - name: /etc/pgpool-II-10/pgpool.conf
    - pattern: "arping_cmd = '/usr/bin/sudo /usr/sbin/arping -U .*'"
    - repl: "arping_cmd = 'sudo /usr/sbin/arping -U $_IP_$ -I eth2 -w 1'"
    - show_changes: True
    - backup: false

ha_master-setup_done:
  grains.present:
    - name: ha_master-setup
    - value: done
{% endif %}

