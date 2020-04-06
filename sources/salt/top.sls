base:
  '*':
    - network
    - common
    - nettools
webserver:
  '*minion':
    - apache
  '*suchen':
    - apache
postgresql:
  'Postgres_ext4_*':
    - ext4
  'Postgres_xfs_*':
    - xfs
  'Postgres_btrfs_*':
    - btrfs
  'Postgres_zfs_*':
    - zfs
  'Postgre*':
    - postgresql
    - ha
  'Postgre*1':
    - ha_master
  'Postgre*2':
    - ha_standby
  'Postgres*':
    - switchtopgpool
