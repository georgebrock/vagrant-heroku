# postinstall.sh created from Mitchell's official lucid32/64 baseboxes

date > /etc/vagrant_box_build_time

# Apt-install various things necessary for Ruby, guest additions,
# etc., and remove optional things to trim down the machine.
apt-get -y update
apt-get -y upgrade
apt-get -y install linux-headers-$(uname -r) build-essential
apt-get -y install zlib1g-dev libssl-dev libreadline5-dev
apt-get -y install git-core vim
apt-get -y install libyaml-dev
apt-get -y install libffi-dev

# Setup sudo to allow no-password sudo for "admin"
cp /etc/sudoers /etc/sudoers.orig
sed -i -e '/Defaults\s\+env_reset/a Defaults\texempt_group=admin' /etc/sudoers
sed -i -e 's/%admin ALL=(ALL) ALL/%admin ALL=NOPASSWD:ALL/g' /etc/sudoers

# Install NFS client
apt-get -y install nfs-common

# Install Ruby from source in /opt so that users of Vagrant
# can install their own Rubies using packages or however.
wget http://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.1.0.tar.gz
tar xvzf ruby-2.1.0.tar.gz
cd ruby-2.1.0
./configure --prefix=/opt/ruby
make
make install
cd ..
rm -rf ruby-2.1.0*
chown -R root:admin /opt/ruby
chmod -R g+w /opt/ruby

# Install RubyGems 2.0.3
wget http://production.cf.rubygems.org/rubygems/rubygems-2.0.3.tgz
tar xzf rubygems-2.0.3.tgz
cd rubygems-2.0.3
/opt/ruby/bin/ruby setup.rb
cd ..
rm -rf rubygems-2.0.3*

# Installing chef & Puppet
/opt/ruby/bin/gem install chef --no-ri --no-rdoc
/opt/ruby/bin/gem install puppet --no-ri --no-rdoc
/opt/ruby/bin/gem install bundler --no-ri --no-rdoc

# Install PostgreSQL 9.1.5
wget http://ftp.postgresql.org/pub/source/v9.1.5/postgresql-9.1.5.tar.gz
tar xzf postgresql-9.1.5.tar.gz
cd postgresql-9.1.5
./configure --prefix=/usr
make
make install
cd ..
rm -rf postgresql-9.1.5*

# Initialize postgres DB
useradd -p postgres postgres
mkdir -p /var/pgsql/data
chown postgres /var/pgsql/data
su -c "/usr/bin/initdb -D /var/pgsql/data --locale=en_US.UTF-8 --encoding=UNICODE" postgres
mkdir /var/pgsql/data/log
chown postgres /var/pgsql/data/log

# Start postgres
su -c '/usr/bin/pg_ctl start -l /var/pgsql/data/log/logfile -D /var/pgsql/data' postgres

# Start postgres at boot
sed -i -e 's/exit 0//g' /etc/rc.local
echo "su -c '/usr/bin/pg_ctl start -l /var/pgsql/data/log/logfile -D /var/pgsql/data' postgres" >> /etc/rc.local

# Install NodeJs for a JavaScript runtime
git clone https://github.com/joyent/node.git
cd node
git checkout v0.4.7
./configure --prefix=/usr
make
make install
cd ..
rm -rf node*

# Add /opt/ruby/bin to the global path as the last resort so
# Ruby, RubyGems, and Chef/Puppet are visible
echo 'PATH=$PATH:/opt/ruby/bin/'> /etc/profile.d/vagrantruby.sh

# Installing vagrant keys
mkdir /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh
cd /home/vagrant/.ssh
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' -O authorized_keys
chmod 600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh

# Installing the virtualbox guest additions
VBOX_VERSION=$(cat /home/vagrant/.vbox_version)
cd /tmp
wget http://download.virtualbox.org/virtualbox/$VBOX_VERSION/VBoxGuestAdditions_$VBOX_VERSION.iso
mount -o loop VBoxGuestAdditions_$VBOX_VERSION.iso /mnt
sh /mnt/VBoxLinuxAdditions.run
umount /mnt

rm VBoxGuestAdditions_$VBOX_VERSION.iso

# Zero out the free space to save space in the final image:
dd if=/dev/zero of=/EMPTY bs=1M
rm -f /EMPTY

# Removing leftover leases and persistent rules
echo "cleaning up dhcp leases"
rm /var/lib/dhcp3/*

# Make sure Udev doesn't block our network
# http://6.ptmc.org/?p=164
echo "cleaning up udev rules"
rm /etc/udev/rules.d/70-persistent-net.rules
mkdir /etc/udev/rules.d/70-persistent-net.rules
rm -rf /dev/.udev/
rm /lib/udev/rules.d/75-persistent-net-generator.rules

# Install some libraries
apt-get -y install libxml2-dev libxslt-dev curl libcurl4-openssl-dev
apt-get -y install imagemagick libmagickcore-dev libmagickwand-dev
apt-get -y install screen
apt-get clean

# Set locale
echo 'LC_ALL="en_US.UTF-8"' >> /etc/default/locale

# Qt for capybara-webkit
apt-get -y install libxrender-dev
wget http://download.qt-project.org/official_releases/qt/4.8/4.8.5/qt-everywhere-opensource-src-4.8.5.tar.gz
tar zxvf qt-everywhere-opensource-src-4.8.5.tar.gz
cd qt-everywhere-opensource-src-4.8.5
./configure -nomake examples -nomake demos -nomake docs -fast -opensource -confirm-license
make
make install
echo 'PATH=$PATH:/usr/local/Trolltech/Qt-4.8.5/bin'> /etc/profile.d/qt.sh
cd ..
rm -rf qt-everywhere-opensource-src-4.8.5*

# Xvfb
apt-get -y install xvfb

export DISPLAY=:99
echo "export DISPLAY=${DISPLAY}" >> /etc/profile.d/display.sh
echo "DISPLAY=${DISPLAY} /etc/init.d/xvfb start" >> /etc/rc.local
tee /etc/init.d/xvfb <<-EOF
#!/bin/bash

XVFB=/usr/bin/Xvfb
XVFBARGS="\$DISPLAY -ac -screen 0 1024x768x16"
PIDFILE=\${HOME}/xvfb_\${DISPLAY:1}.pid
case "\$1" in
start)
  echo -n "Starting virtual X frame buffer: Xvfb"
  /sbin/start-stop-daemon --start --quiet --pidfile \$PIDFILE --make-pidfile --background --exec \$XVFB -- \$XVFBARGS
  echo "."
  ;;
stop)
  echo -n "Stopping virtual X frame buffer: Xvfb"
  /sbin/start-stop-daemon --stop --quiet --pidfile \$PIDFILE
  echo "."
  ;;
restart)
  \$0 stop
  \$0 start
  ;;
*)
  echo "Usage: /etc/init.d/xvfb {start|stop|restart}"
  exit 1
esac
exit 0
EOF

chmod +x /etc/init.d/xvfb

# Add a vagrant postgres user
createuser -d -R -S -Upostgres vagrant
psql -Uvagrant postgres -c 'ALTER ROLE vagrant SET client_min_messages TO WARNING;'

echo "Adding a 2 sec delay to the interface up, to make the dhclient happy"
echo "pre-up sleep 2" >> /etc/network/interfaces
exit
exit
