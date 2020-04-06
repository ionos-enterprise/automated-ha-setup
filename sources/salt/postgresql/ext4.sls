{% if salt['grains.get']('dbpartition') != 'created' %}

create_ext4_device:
  cmd.run:
    - name: parted /dev/vdb -s -- mklabel gpt ; parted -s -a optimal /dev/vdb mkpart primary ext4 1MiB 100%

create_ext4_partition:
  cmd.run:
    - name: mkfs.ext4 /dev/vdb1
    - require: 
      - create_ext4_device

prepare_block_device:
  mount.mounted:
    - name: /var/lib/pgsql
    - device: /dev/vdb1
    - fstype: ext4
    - mkmnt: True
    - opts: defaults
    - persist: True
    - mount: True
    - dump: 0
    - pass_num: 0
    - require: 
      - create_ext4_partition

db-partition created:
  grains.present:
    - name: dbpartition
    - value: created
    - require:
      - prepare_block_device

{% endif %}


