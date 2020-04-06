{% if salt['grains.get']('dbpartition') != 'created' %}

get_zfs_repo:
  cmd.run:
    - name: if [ "$(rpm -qa | grep zfs-release)" == "" ] ; then yum -y install http://download.zfsonlinux.org/epel/zfs-release.el7_5.noarch.rpm ; fi 

adjust_zfs_repo:
  file.blockreplace:
    - name: /etc/yum.repos.d/zfs.repo
    - marker_start: "[zfs]"
    - marker_end: "metadata_expire=7d"
    - content: |
        name=ZFS on Linux for EL7 - dkms
        baseurl=http://download.zfsonlinux.org/epel/7.5/$basearch/
        enabled=0        
    - show_changes: True
    - backup: false
    - require: 
      - get_zfs_repo

zfs_kernel_module:
  file.blockreplace:
    - name: /etc/yum.repos.d/zfs.repo
    - marker_start: "[zfs-kmod]"
    - marker_end: "metadata_expire=7d"
    - content: |
        name=ZFS on Linux for EL7 - kmod
        baseurl=http://download.zfsonlinux.org/epel/7.5/kmod/$basearch/
        enabled=1        
    - show_changes: True
    - backup: false
    - require: 
      - get_zfs_repo

install_zfs_prep:
  pkg.installed:
    - name: zfs_kompile
    - skip_verify: true
    - pkgs:
      - kernel-devel
      - gcc

zfs-repo-bug1:
  cmd.run:
    - name: yum -y update ; yum -y install kernel kernel-debug ; yum remove -y zfs zfs-kmod spl spl-kmod libzfs2 libnvpair1 libuutil1 libzpool2 zfs-release
    - require: 
      - install_zfs_prep

zfs-repo-bug2:
  cmd.run:
    - name: yum install -y http://download.zfsonlinux.org/epel/zfs-release.el7_5.noarch.rpm ; yum -y autoremove ; yum clean metadata ; yum -y install zfs
    - require: 
      - zfs-repo-bug1

{% if salt['grains.get']('zfs_initial_reboot') != 'done' %}
zfs_initial_reboot:
  grains.present:
    - name: zfs_initial_reboot
    - value: done
    - require: 
      - zfs-repo-bug2

check_zfs_module:
  cmd.run:
    - name: if ! /usr/sbin/modprobe zfs ; then shutdown -r now ; fi
    - require: 
      - zfs_initial_reboot
{% endif %}

prepare_block_device:
  cmd.run: 
    - name: if ! zpool list | grep zfsvolume ; then /usr/sbin/modprobe zfs ; zpool create -f -m /var/lib/pgsql zfsvolume /dev/vdb ; fi
    - require:
      - zfs-repo-bug2

db-partition created:
  grains.present:
    - name: dbpartition
    - value: created
    - require:
      - prepare_block_device

{% endif %}


