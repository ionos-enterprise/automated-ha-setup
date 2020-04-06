/var/lib/pgsql/dumps/get_musicbrainz.sh:
  file.managed:
    - name: /var/lib/pgsql/dumps/get_musicbrainz.sh
    - mode: 770

/var/lib/pgsql/dumps/content-get_musicbrainz.sh:
  file.append:
    - name: /var/lib/pgsql/dumps/get_musicbrainz.sh
    - text: |
        #!/bin/bash
        short_date=$(/bin/date +%s)
        exec 100>>/tmp/"$short_date"_get_musicbrainz.log
        BASH_XTRACEFD=100
        set -x
        WorkDir=/var/lib/pgsql/dumps
        cd ${WorkDir}
        LATEST=$(curl ftp://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/LATEST)
        wget -nv -r -nH --cut-dirs=5 -nc ftp://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${LATEST}
        if [ ! -e ${WorkDir}/check_files.log ] ; then
                (pushd ${WorkDir}/ && md5sum -c MD5SUMS && popd
                gpg --recv-keys C777580F
                gpg --verify-files ${WorkDir}/*.asc) 2>&1 > ${WorkDir}/check_files.log
        fi

Broken_dependency1:
  cmd.run:
    - name: curl -sL https://rpm.nodesource.com/setup_8.x | bash -

Broken_dependency2:
  cmd.run:
    - name: curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo

Broken_dependency3:
  cmd.run:
    - name: yum -y install nodejs

Broken_dependency4:
  cmd.run:
    - name: yum -y install yarn

install_prerequesites:
  pkg.installed:
    - name: pre-musicbrainz
    - skip_verify: true
    - pkgs:
      - memcached
      - gcc
      - gcc-c++
      - make
      - openssl-devel
      - openssl-libs
      - nodejs
      - libdb-devel 
      - libicu-devel
      - libpqxx-devel
      - libxml2-devel
      - git
      - json-devel
      - json-devel
      - perl-App-cpanminus.noarch
      - perl-XML-Parser
      - perl-CPAN
      - perl-JSON
      - perl-JSON-XS
      - perl-DBD-Pg
      - perl-Cpanel-JSON-XS
      - libxml2
      - libxslt
      - libxslt-devel
      - redis
      - perl-devel
      - libgit2
      - libgit2-devel
      - libgit2-glib
      - libgit2-glib-devel 
      - expat-devel
      - nodejs-graceful-fs.noarch
      - ustl-devel
      - icu
      - libicu
      - libicu-devel
      - perl-Plack
    - require:
      - Broken_dependency1
      - Broken_dependency2

get_perl524:
  cmd.run:
    - name: 'wget -q http://www.cpan.org/src/5.0/perl-5.24.0.tar.gz ; tar -xzf perl-5.24.0.tar.gz'
    - cwd: '/root'
    - unless: test -f /root/perl-5.24.0/config.sh

install_perl524:
  cmd.run:
    - name: '(./Configure -des -Dinstallusrbinperl -Dprefix=/usr; make ; make install) 2>&1 > /tmp/perl524-install.log'
    - unless: perl -v | grep "v5.24.0"
    - cwd: '/root/perl-5.24.0'
    - require:
      - cmd: get_perl524

create root-bashrc:
  file.managed:
    - user: root
    - group: root
    - mode: 600    
    - name: /root/.bashrc

fill root-bashrc:
  file.append:
    - name: /root/.bashrc
    - text: |
        # .bashrc
        alias rm='rm -i'
        alias cp='cp -i'
        alias mv='mv -i'
        if [ -f /etc/bashrc ]; then
        	. /etc/bashrc
        fi
        eval $( perl -Mlocal::lib )
        PATH=${PATH}:/srv/musicbrainz/node_modules/.bin:/usr/pgsql-10/bin/
        export PATH="$PATH:/opt/yarn-1.21.10/bin"

download_musicbrainz_setup:
  git.latest:
    - name: git://github.com/metabrainz/musicbrainz-server.git
    - target: /srv/musicbrainz
    - user: root
    - submodules: True
    - force_clone: True
    - force_fetch: True
    - force_checkout: True
    - force_reset: True
    - require:
      - install_prerequesites
    - require_in:
      - file: fill root-bashrc

copy DBDefs.pm:
  file.rename:
    - name: /srv/musicbrainz/lib/DBDefs.pm
    - source: /srv/musicbrainz/lib/DBDefs.pm.sample
    - unless: test -f /srv/musicbrainz/lib/DBDefs.pm
    - require:
      - git: download_musicbrainz_setup

adjust DBDefs.pm:
  file.blockreplace:
    - name: /srv/musicbrainz/lib/DBDefs.pm
    - marker_start: "# sub REPLICATION_TYPE { RT_STANDALONE }"
    - marker_end: ""
    - content: 'sub REPLICATION_TYPE { RT_STANDALONE }'
    - backup: '.bak'
    - show_changes: True
    - unless : grep -E '^sub REPLICATION_TYPE { RT_STANDALONE }' /srv/musicbrainz/lib/DBDefs.pm
    - require:
      - file: copy DBDefs.pm

enable marker_end:
  file.replace:
    - name: /srv/musicbrainz/lib/DBDefs.pm
    - pattern: ".*How to connect to a test database"
    - repl: "    # How to connect to a test database"
    - show_changes: True
    - backup: false
    - require:
      - file: copy DBDefs.pm

{% if salt['grains.get']('musicbrainz') != 'installed' %}
download_musicbrainz:
  cmd.run:
    - name: /var/lib/pgsql/dumps/get_musicbrainz.sh

install_cpanmods:
  cmd.run:
    - name: 'export POSTGRES_HOME="/usr/pgsql-10" ; cpanm --install --force local::lib warnings strict File::Slurp DBD::Pg Plack::Middleware::Debug::Base'
    - require:
      - cmd: install_perl524

install_npm:
  cmd.run:
    - name: 'npm install'
    - cwd: '/srv/musicbrainz'

install_cpanm:
  cmd.run:
    - name: 'cpanm --skip-installed --installdeps --notest .' 
    - cwd: '/srv/musicbrainz'

compile_resources.sh :
  cmd.run:
    - name: './script/compile_resources.sh'
    - cwd: '/srv/musicbrainz'
    - require:
      - cmd: install_cpanmods
      - cmd: install_npm
      - cmd: install_cpanm
      - enable marker_end

install_musicbrainz-unaccent:
  cmd.run:
    - cwd: '/srv/musicbrainz/postgresql-musicbrainz-unaccent'
    - name: 'source /root/.bashrc ; make ; make install'
    - require:
      - cmd: install_npm

install_musicbrainz-collate:
  cmd.run:
    - cwd: '/srv/musicbrainz/postgresql-musicbrainz-collate'
    - name: 'source /root/.bashrc ; make ; make install'
    - require:
      - cmd: install_musicbrainz-unaccent

{% endif %}

create import_dump script:
  file.managed:
    - user: root
    - group: root
    - name: /srv/musicbrainz/import_dump.sh
    - mode: 700    

sync import_dump script:
  file.append:
    - name: /srv/musicbrainz/import_dump.sh
    - text: |
        #!/bin/bash
        cd /srv/musicbrainz/
        if ! psql -U postgres -c '\l' | grep musicbrainz > /dev/null ;  then 
            (./admin/InitDb.pl -t /var/lib/pgsql/ --createdb --import /var/lib/pgsql/dumps/mbdump*.tar.bz2 --echo  2>&1 > /tmp/DB-import.log &)
        fi

make sure redis is running:
  service.running:
    - name: redis
    - enable: true

create plack_for_musicbrainz.sh:
  file.managed:
    - mode: 700
    - replace: True
    - name: /usr/local/bin/plack_for_musicbrainz.sh
    - contents: |
        #!/bin/bash
        Job=$1
        function stop {
            if PlackPID=$(ps -C /usr/bin/plackup -o pid=) ; then
                echo "Stopping MusicBrainz simple web interface."
                kill ${PlackPID}
            fi
        }
        function start {
            if PlackPID=$(ps -C /usr/bin/plackup -o pid=) ; then
                echo "Stopping MusicBrainz simple web interface."
                kill ${PlackPID}
            fi
            echo "Starting MusicBrainz simple web interface."
            cd /srv/musicbrainz
            (/usr/bin/plackup -Ilib -D --access-log /var/log/musicbrainz.log 2>&1 >> /var/log/musicbrainz.log &)
        }
        eval $Job

copy musicbrainz libs:
  cmd.run:
    - name: 'cp -v /srv/musicbrainz/postgresql-musicbrainz-collate/musicbrainz_collate.so /srv/musicbrainz/postgresql-musicbrainz-unaccent/musicbrainz_unaccent.so /usr/pgsql-10/lib/.'
    - require:
      - file: copy DBDefs.pm

