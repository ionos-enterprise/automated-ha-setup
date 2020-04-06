adjust root_bashrc:
  file.append:
    - name: /root/.bashrc
    - text: |
        alias CS='cat /var/lib/pgsql/ClusterNodeStatus'
        alias DF='df -hP /var/lib/pgsql'
        alias PP='ps ax | grep pool ; ps ax | grep post'

mount nfs volume:
  mount.mounted:
    - name: /var/lib/pgsql/dumps
    - device: management1:/srv/dumps
    - fstype: nfs
    - mkmnt: True
    - persist: False
    - mount: True
    - dump: 0
    - pass_num: 0
    - user: root

avoid_firewall:
  pkg.removed:
    - name: firewall
    - pkgs:
      - firewalld

adjust CentOS-Base.repo base:
  file.line:
    - name: /etc/yum.repos.d/CentOS-Base.repo
    - mode: replace
    - after: \[base\]
    - content: |
        exclude=postgresql*
        exclude=pgpool*
    - show_changes: True
    - backup: false

adjust CentOS-Base.repo update:
  file.line:
    - name: /etc/yum.repos.d/CentOS-Base.repo
    - mode: replace
    - after: \[updates\]
    - content: |
        exclude=postgresql*
        exclude=pgpool*
    - show_changes: True
    - backup: false

add postgres repo:
  cmd.run:
    - name: /usr/bin/yum -y install https://download.postgresql.org/pub/repos/yum/10/redhat/rhel-7-x86_64/pgdg-centos10-10-2.noarch.rpm
    - unless: test -f /etc/yum.repos.d/pgdg-redhat-all.repo
    - require: 
      - adjust CentOS-Base.repo base
      - adjust CentOS-Base.repo update

clean yum cache:
  cmd.run:
    - name: yum clean all
    - require: 
      - adjust CentOS-Base.repo base
      - adjust CentOS-Base.repo update
      - add postgres repo

install_postgresql:
  pkg.installed:
    - name: postgresql-10
    - skip_verify: true
    - pkgs:
      - postgresql10.x86_64
      - postgresql10-server.x86_64
      - postgresql10-devel.x86_64
      - postgresql10-contrib.x86_64
      - postgresql10-plperl.x86_64
      - pgpool-II-10.x86_64
      - pgpool-II-10-devel.x86_64
      - pgpool-II-10-extensions.x86_64
      - pgpool-II-10-debuginfo.x86_64
      - pgtune

create_pgsql_dir:
  file.directory:
    - name: /var/lib/pgsql
    - user: postgres
    - group: postgres
    - mode: 700
    - makedirs: True

create pgsql_profile:
  file.managed:
    - name: /var/lib/pgsql/.pgsql_profile
    - user: postgres
    - group: postgres
    - mode: 640
    - unless: test -e /var/lib/pgsql/.pgsql_profile
    - require: 
      - create_pgsql_dir

create pgpass:
  file.managed:
    - name: /var/lib/pgsql/.pgpass
    - user: postgres
    - group: postgres
    - mode: 600
    - unless: test -e /var/lib/pgsql/.pgpass
    - require: 
      - create_pgsql_dir

fill pgpass:
  file.append:
    - name: /var/lib/pgsql/.pgpass
    - text: |
        *:*:replication:repuser:'oiha3eameNoB''
        *:*:postgres:pgpool:'aeL8ieriedux''
        *:*:*:postgres:postgres:'feixaiXohM4u''

sync disable.selinux:
  file.line:
    - name: /etc/selinux/config
    - mode: replace
    - match: 'SELINUX=enforcing'
    - content: SELINUX=disabled
    - show_changes: True
    - backup: false

/var/lib/pgsql/.ssh:
  file.directory:
    - user: postgres
    - group: postgres
    - mode: 700
    - makedirs: True
    - require:
      - install_postgresql

create_ha-ssh-key-pg:
  cmd.run:
    - user: postgres
    - name: 'su -l postgres -c "if [ ! -e ~/.ssh/id_rsa ] ; then ssh-keygen -v -t rsa -f ~/.ssh/id_rsa -P \"\" ; ls -l  ~/.ssh/id_rsa ; fi"'
    - cwd: '/var/lib/pgsql'
    - require: 
      - mount nfs volume
      - create_pgsql_dir
      - /var/lib/pgsql/.ssh

get-pub-ssh-key-pg:
  cmd.run:
    - name: 'cat /var/lib/pgsql/.ssh/id_rsa.pub >> /var/lib/pgsql/dumps/authorized_keys'
    - cwd: '/var/lib/pgsql'
    - unless: grep $(cut -d " " -f2 /var/lib/pgsql/.ssh/id_rsa.pub) /var/lib/pgsql/dumps/authorized_keys
    - require:
      - create_ha-ssh-key-pg

/var/lib/pgsql/archive:
  file.directory:
    - user: postgres
    - group: postgres
    - mode: 775
    - makedirs: True

adjust pgsql_profile:
  file.append:
    - name: /var/lib/pgsql/.pgsql_profile
    - text: |
        PATH=${PATH}:/usr/pgsql-10/bin/

/var/lib/pgsql/.bash_profile:
  file.managed:
    - user: postgres
    - group: postgres
    - require:
      - adjust pgsql_profile

/var/run/postgresql:
  file.directory:
    - user: postgres
    - group: postgres
    - mode: 770
    - makedirs: True
    - require:
      - install_postgresql

copy postgresql.conf.sample:
  file.copy:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - source: /usr/pgsql-10/share/postgresql.conf.sample
    - user: postgres
    - group: postgres
    - mode: 660    
    - require:
      - /var/lib/pgsql/.ssh

{% if salt['grains.get']('postgresql-setup') != 'done' %}
remove_former_contend:
  file.directory:
    - name: /var/lib/pgsql/10/data/
    - clean: True
    - require:
      - pkg: install_postgresql

create initdb:
  file.managed:
    - name: /var/lib/pgsql/initdb.sh
    - user: postgres
    - group: postgres
    - mode: 700
    - unless: test -e /var/lib/pgsql/initdb.sh
    - require:
      - remove_former_contend

fill initdb:
  file.append:
    - name: /var/lib/pgsql/initdb.sh
    - text: |
        #!/bin/bash
        source /var/lib/pgsql/.bash_profile
        pg_ctl initdb 
    - require:
      - create initdb

postgresql-setup-initdb:
  cmd.run:
    - user: postgres
    - name: su -l postgres --group=postgres -c /var/lib/pgsql/initdb.sh 2>&1 > /dev/null &
    - require:
      - fill initdb
{% endif %}

listen_to_all_nics:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#listen_addresses = 'localhost'"
    - repl: "listen_addresses = '*'"
    - show_changes: True
    - backup: false
    - require:
      - install_postgresql

adjust wal_level:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#wal_level =.*"
    - repl: "wal_level = hot_standby"
    - show_changes: True
    - backup: false
    - require:
      - install_postgresql

enable scram-sha-256_pw-encryption:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#password_encryption = on"
    - repl: "password_encryption = scram-sha-256"
    - show_changes: True
    - backup: false

set wal_buffers:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#wal_buffers = -1"
    - repl: "wal_buffers = 16MB"
    - show_changes: True
    - backup: false

set wal_writer_delay:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#wal_writer_delay = 200ms"
    - repl: "wal_writer_delay = 1000ms"
    - show_changes: True
    - backup: false

set wal_writer_flush_after:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#wal_writer_flush_after = 1MB"
    - repl: "wal_writer_flush_after = 10MB"
    - show_changes: True
    - backup: false

switch fsync off:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#fsync = on"
    - repl: "fsync = off"
    - show_changes: True
    - backup: false

switch synchronous_commit off:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#synchronous_commit = on"
    - repl: "synchronous_commit = off"
    - show_changes: True
    - backup: false

switch full_page_writes off:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#full_page_writes = on"
    - repl: "full_page_writes = off"
    - show_changes: True
    - backup: false

increase max_wal_size:
  file.replace:
    - name: /var/lib/pgsql/10/data/postgresql.conf
    - pattern: "#max_wal_size = 1GB"
    - repl: "max_wal_size = 60GB"
    - show_changes: True
    - backup: false

create_pg_hba.conf:
  file.managed:
    - name: /var/lib/pgsql/10/data/pg_hba.conf
    - user: postgres
    - group: postgres
    - mode: 600

configure_pg_hba.conf:
  file.append:
    - name: /var/lib/pgsql/10/data/pg_hba.conf
    - text: |
        host    all             all             127.0.0.1/32            trust
        host    all             all             ::1/128                 trust
        host    all             all             10.99.3.0/24            password
        host    all             postgres        10.99.1.0/24            password
        host    all             postgres        10.99.4.0/24            trust
        host    all             postgres        localhost               trust
        host    musicbrainz_db  musicbrainz     10.99.4.0/24            trust
        host    replication     repuser         10.99.1.0/24            password
        host    replication     repuser         10.99.4.0/24            trust

{% if salt['grains.get']('postgresql-setup') != 'done' %}
postgres-setup_done:
  grains.present:
    - name: postgresql-setup
    - value: done
    - require:
      - postgresql-setup-initdb
{% endif %}

