{% if salt['grains.get']('musicbrainz') != 'installed' %}
install_musicbrainz-import:
  cmd.run:
    - cwd: '/srv/musicbrainz/'
    - name: 'source /root/.bashrc ; bash import_dump.sh 2>&1 > /dev/null &'
  grains.present:
    - name: musicbrainz
    - value: installed
{% endif %}
