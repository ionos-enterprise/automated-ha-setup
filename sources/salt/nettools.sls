install_network_packages:
  pkg.installed:
    - pkgs:
      - rsync
      - lftp
      - curl
      - tcpdump
      - nfs-utils
      - nmap-ncat
      - openssh-clients
