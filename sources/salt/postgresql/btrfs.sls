{% if salt['grains.get']('dbpartition') != 'created' %}

install_btrfs:
  pkg.installed:
    - name: btrfs-progs
    - skip_verify: true

create_btrfs_device:
  cmd.run:
    - name: parted /dev/vdb -s -- mklabel gpt ; parted -s -a optimal /dev/vdb mkpart primary ext4 1MiB 100%

create_btrfs_partition:
  cmd.run:
    - name: modprobe btrfs ; partprobe -s ; mkfs.btrfs -f /dev/vdb1
    - require: 
      - create_btrfs_device
      - install_btrfs

prepare_block_device:
  mount.mounted:
    - name: /var/lib/pgsql
    - device: /dev/vdb1
    - fstype: btrfs
    - mkmnt: True
    - opts: defaults
    - persist: True
    - mount: True
    - dump: 0
    - pass_num: 0
    - require: 
      - create_btrfs_partition

db-partition created:
  grains.present:
    - name: dbpartition
    - value: created
    - require:
      - prepare_block_device

{% endif %}


