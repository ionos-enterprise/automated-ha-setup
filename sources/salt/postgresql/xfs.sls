{% if salt['grains.get']('dbpartition') != 'created' %}

create_xfs_device:
  cmd.run:
    - name: parted /dev/vdb -s -- mklabel gpt ; parted -s -a optimal /dev/vdb mkpart primary xfs 1MiB 100%

create_xfs_partition:
  cmd.run:
    - name: mkfs.xfs -f /dev/vdb1
    - require: 
      - create_xfs_device

prepare_block_device:
  mount.mounted:
    - name: /var/lib/pgsql
    - device: /dev/vdb1
    - fstype: xfs
    - mkmnt: True
    - opts: defaults
    - persist: True
    - mount: True
    - dump: 0
    - pass_num: 0
    - require: 
      - create_xfs_partition

db-partition created:
  grains.present:
    - name: dbpartition
    - value: created
    - require:
      - prepare_block_device

{% endif %}


