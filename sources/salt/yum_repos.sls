base:
  pkgrepo.managed:
    - humanname: PostgreSQL 9.5 $releasever - $basearch
    - mirrorlist: http://yum.postgresql.org/9.5/redhat/rhel-$releasever-$basearch
    - comments:
        - '#mirrorlist: http://yum.postgresql.org/9.5/redhat/rhel-$releasever-$basearch'
    - gpgcheck: 1
    - gpgkey: file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6


