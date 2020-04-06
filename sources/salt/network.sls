{% if salt['grains.get']('lsb_distrib_id') == 'CentOS' %}
restart_network:
  cmd.run:
    - name : systemctl restart network
{% endif %}

adjust sshd_config:
  file.line:
    - name: /etc/ssh/sshd_config
    - content: 'PasswordAuthentication no'
    - match: '# PasswordAuthentication yes'
    - mode: replace
    - show_changes: True

timeout_sshd:
  file.append:
    - name: /etc/ssh/ssh_config
    - text: 'ServerAliveInterval 60'

{% if salt['grains.get']('lsb_distrib_id') == 'CentOS' %}
sshd:
  service.running:
    - watch:
      - file: /etc/ssh/sshd_config
{% endif %}
