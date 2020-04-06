sync pgpool-failover:
  file.managed:
    - name: /var/lib/pgsql/bin/cluster_connection.sh
    - source: salt://cluster_connection.sh
    - show_changes: True
    - user: postgres
    - group: postgres
    - mode: 770

before_restart_pgpool_0:
  cmd.run:
    - user: pgpool
    - cwd: /var/run/pgpool-II-10/
    - name: 'if test -e /tmp/.s.PGSQL.5432.lock ; then rm -v /tmp/.s.PGSQL.5432.lock ; fi'
    - require:
        - sync pgpool-failover

restart_installed_db:
  cmd.run:
    - user: postgres
    - name: 'su -l postgres -c "source /var/lib/pgsql/.bash_profile ; /var/lib/pgsql/bin/cluster_connection.sh -f recovery"'
    - require:
        - before_restart_pgpool_0

before_restart_pgpool_A:
  cmd.run:
    - user: pgpool
    - cwd: /var/run/pgpool-II-10/
    - name: 'if ! ps cax | grep pgpool ; then rm -fv /tmp/pgpool_status ; fi'
    - require:
        - restart_installed_db

before_restart_pgpool_B:
  cmd.run:
    - user: pgpool
    - cwd: /var/run/pgpool-II-10/
    - name: 'if ! ps cax | grep pgpool ; then rm -fv /var/run/pgpool-II-10/.s.PGPOOLWD_CMD.9000 /var/run/pgpool-II-10/.s.PGSQL.9898 ; fi'
    - require:
        - restart_installed_db

restart_pgpool:
  cmd.run:
    - user: pgpool
    - cwd: /var/run/pgpool-II-10/
    - name: 'if ! ps cax | grep pgpool ; then su -l pgpool -c "/bin/pgpool -f /etc/pgpool-II-10/pgpool.conf -F /etc/pgpool-II-10/pcp.conf" ; fi'
    - require:
        - before_restart_pgpool_A
        - before_restart_pgpool_B
        - restart_installed_db

attach_standby:
  cmd.run:
    - user: pgpool
    - name: su -l pgpool -c "ps cax | grep pgpool ; sleep 10 ; /home/pgpool/bin/AddNode.sh"
    - require:
        - restart_pgpool
