#!/usr/bin/env bash

# Install Required Packages

echo 'Installing required packages...'
sudo yum install selinux-policy-devel gcc make imake binutils cpp \
		postgresql-devel mysql-libs mysql-devel openssl openssl-devel \
		pkgconfig gd gd-devel gd-progs libpng libpng-devel libjpeg \
		libjpeg-devel perl perl-devel net-snmp net-snmp-devel \
		net-snmp-perl net-snmp-utils httpd php git m4 gettext automake \
		autoconf -y  > /dev/null 2>&1

# Clone Repositories from GitHub

echo 'Cloning source repos...'
sudo mkdir -p /usr/src/nagios/
cd /usr/src/nagios/
sudo git clone https://github.com/NagiosEnterprises/nagioscore.git \
		> /dev/null 2>&1
sudo git clone https://github.com/nagios-plugins/nagios-plugins.git \
		> /dev/null 2>&1
# Configure Groups and Users

echo 'Configuring groups and users...'
sudo groupadd nagios
sudo groupadd nagcmd
sudo useradd -g nagios -G nagcmd -d /opt/nagios nagios
sudo usermod -G nagcmd apache
# Configure Directories

echo 'Configuring destination directories...'
sudo mkdir -p /opt/nagios /etc/nagios /var/nagios
sudo chown nagios:nagios /opt/nagios/ /etc/nagios/ /var/nagios/
# Build and Install Nagios

echo 'Building and installing Nagios...'
cd /usr/src/nagios/nagioscore
sudo git checkout nagios-4.0.8 > /dev/null 2>&1
sudo ./configure --with-command-group=nagcmd \
		--prefix=/opt/nagios \
		--sysconfdir=/etc/nagios \
		--localstatedir=/var/nagios \
		--libexecdir=/opt/nagios/plugins > /dev/null 2>&1
sudo make all > /dev/null 2>&1
sudo make install > /dev/null 2>&1
sudo make install-commandmode > /dev/null 2>&1
sudo make install-init > /dev/null 2>&1
sudo make install-config > /dev/null 2>&1
sudo make install-webconf > /dev/null 2>&1

# Build and Install Plugins

echo 'Building and installing Nagios Plugins...'
cd /usr/src/nagios/nagios-plugins
sudo git checkout release-2.0.3 > /dev/null 2>&1
sudo ./tools/setup > /dev/null 2>&1
sudo ./configure --with-nagios-user=nagios \
		--with-nagios-group=nagios \
		--with-openssl \
		--prefix=/opt/nagios \
		--sysconfdir=/etc/nagios \
		--localstatedir=/var/nagios \
		--libexecdir=/opt/nagios/plugins > /dev/null 2>&1
sudo make all > /dev/null 2>&1
sudo make install > /dev/null 2>&1
# Repair File and Folder Permissions

echo 'Repairing file and folder permissions...'
# Fix root Nagios directory permissions so Apache can read the share directory
sudo chmod 755 /opt/nagios/

# Fix SeLinux labels on files inside the etc and var Nagios directories
sudo chcon -R -t usr_t /etc/nagios/
sudo chcon -R -t usr_t /var/nagios/
sudo chcon -R -t httpd_sys_script_rw_t /var/nagios/rw/

# Build and Implement SELinux Policies

echo 'Building and implementing SELinux policies...'
# Generate a policy to allow Nagios' web UI to make changes
cd /tmp/
cat >> nagios_write_file.te << EOF
module nagios_write_file 1.0;
require {
	type httpd_t;
	type httpd_sys_rw_content_t;
	class fifo_file { getattr write open };
}
#============= httpd_t ==============
allow httpd_t httpd_sys_rw_content_t:fifo_file { getattr write open };
EOF

checkmodule -M -m -o nagios_write_file.mod nagios_write_file.te > /dev/null 2>&1
semodule_package -o nagios_write_file.pp -m nagios_write_file.mod \
		> /dev/null 2>&1
semodule -i ./nagios_write_file.pp > /dev/null 2>&1

rm -f ./NagiosCmdRule*

# Configure Nagiosadmin Account

echo 'Configuring nagiosadmin account...'
sudo htpasswd -b -c /etc/nagios/htpasswd.users nagiosadmin nagiosadmin \
		> /dev/null 2>&1
# Enable and Start Services

echo 'Enabling and starting services...'
sudo systemctl enable nagios > /dev/null 2>&1
sudo systemctl start nagios > /dev/null 2>&1

sudo firewall-cmd --permanent --zone=public --add-port=80/tcp > /dev/null 2>&1
sudo firewall-cmd --reload > /dev/null 2>&1

sudo systemctl enable httpd > /dev/null 2>&1
sudo systemctl start httpd > /dev/null 2>&1
