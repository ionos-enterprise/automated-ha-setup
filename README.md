Readme:

HA-GateAndDatabase.sh gives you the oportunity to setup either

A) a simple high availability setup consisting of two virtual machines (VM) as gateways with an additional VM behind it or

B) such setup with another setup of a high avalability PostgreSQL cluster.

C) Additionally is is possible to import the MusicBrainz database into the cluster.


DEPENDENCIES

Before you start you need to install
-> pwgen <-      for the creation of passwords used for the installation and let the
-> ssh-agent <-  run to make sure that the script can copy lots of files and change configurations without password dialog.

Curl and tee are also needed intensively but I never experienced that this programms had not been installed already on the widely used Linux distributions.

After all you need to have your
-> limits <-     on the IONOS platform high enough.

- For the installation option A) you will need

    -- 3 customer reserved IP addresses (CRIP, the script will reserve them automatically),

    -- 3 cores,

    -- 3 GB of RAM and

    -- 37 GB HDD space.

- For the variant B) you need all the aforementioned AND

    -- 2 cores

    -- 2 GB RAM

    -- at least 40 GB HDD or SSD (as you chose with '-s') or more, depending on what you give on the command line via the option '-S number'

- For the variant C) you need all the aforementioned AND

    -- at least 600 GB HDD or SSD or more, depending on what you give on the command line via the option '-S number'

Also Important is that you have a

-> stable internect connection <-

Even a short break would make it necessary to stop the whole process, delete an already created VDC by that script and start the whole process again.

INSTALLATION

- Create the file ${HOME}/ionos/.config with user and password in the form: 'user@domain.tld:password' (without apostrophes).
- Download https://github.com/profitbricks/automated-ha-setup/blob/master/HA-GateAndDatabase.tar.gz
- Unpack the file
- Change into the created sub directory automated-ha-setup/
- Execute ./HA-GateAndDatabase.sh and a short help will show up

FURTHER INFORMATION

More details and the intention of the programm you will find at
https://github.com/profitbricks/automated-ha-setup/blob/master/Automated-HA-Setup.pdf

