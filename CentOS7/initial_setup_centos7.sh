#!/bin/bash
# Created by DATAenligne Inc.

# temp
/usr/sbin/ip addr add 192.168.0.40/24 dev eth1

/usr/local/bin/count_yum_updates.sh > /tmp/yum_updates.txt

clear

T="$(date +%s)"

# Arguments validation
if [ "$1" == "" ]
then
        echo "Usage: $0 <hostname> [domain] [cpanel]"
        echo "eg: $0 del-client-0001-01.dataenligne.com domain cpanel"
        echo "domain: if specified, will join the VM to the DATAenligne's domain"
        echo "cpanel: if specified, will install cpanel"
        exit 1
fi

echo "export TERM=xterm" >> /root/.bashrc

HOSTNAME=$1
IP=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
LOCAL_IP=$(/sbin/ip -o -4 addr list eth1 | awk '{print $4}' | cut -d/ -f1)
SHORT_HOSTNAME=$(/usr/bin/awk -F "." '{print $1}' <<< "$HOSTNAME")

echo "HOSTNAME: $HOSTNAME"
echo "SHORT HOSTNAME: $SHORT_HOSTNAME"
echo "PUBLIC IP: $IP"
echo "LOCAL IP: $LOCAL_IP"
sleep 5

if [ "$2" == "domain" ]
then
	echo "JOIN DOMAIN ?: YES"
else echo "JOIN DOMAIN ?: NO"
fi

if [ "$2" == "cpanel" ]
then
	echo "INSTALL CPANEL ?: YES"
fi

if [ "$3" == "cpanel" ]
then
	echo "INSTALL CPANEL ?: YES"
fi

echo "Configuring the hostname..."
sed -i 's/centos.dataenligne.com/'"$HOSTNAME"'/g' /etc/hostname
hostname $HOSTNAME

echo "Updating packages..."
yum -y update
yum -y upgrade

echo "Configuring SELinux for HyperV VSS..."
semanage permissive -a hypervvssd_t

if [ "$2" == "domain" ]
then
        echo "Configuring the hostfile..."
	echo "192.168.0.3 DC2.dc.dataenligne.com" >> /etc/hosts
	echo "192.168.0.4 DC1.dc.dataenligne.com" >> /etc/hosts

	echo "Installing the required packages (PBIS) to join the domain..."
	wget -O /etc/yum.repos.d/pbiso.repo http://repo.pbis.beyondtrust.com/yum/pbiso.repo
	yum clean all
	yum update -y
	yum -y install pbis-open
	
	### If ever the PBIS's repo gets screwed.... we're installing PBIS manually - make sure to update the URLs
	#cd /usr/src
	#/usr/bin/wget http://repo.pbis.beyondtrust.com/yum/pbiso/x86_64/Packages/pbis-open-8.5.0-153.x86_64.rpm
	#/usr/bin/wget http://repo.pbis.beyondtrust.com/yum/pbiso/x86_64/Packages/pbis-open-upgrade-8.5.0-153.x86_64.rpm
	#/usr/bin/wget http://repo.pbis.beyondtrust.com/yum/pbiso/x86_64/Packages/pbis-open-legacy-8.5.0-153.x86_64.rpm
	#/usr/bin/rpm -Uvh pbis*.rpm


	echo "Joining the dc.dataenligne.com domain..."
	/opt/pbis/bin/domainjoin-cli join dc.dataenligne.com post-config

	echo "Updating DNS / Hostname..."
	hostname $HOSTNAME
	echo $HOSTNAME > /etc/hostname
	/opt/pbis/bin/update-dns
	hostname $HOSTNAME
	echo $HOSTNAME > /etc/hostname

	echo "Configuring variable environment for PBIS..."
	/opt/pbis/bin/regshell set_value '[HKEY_THIS_MACHINE\Services\lsass\Parameters\Providers\ActiveDirectory]' LoginShellTemplate /bin/bash
	/opt/pbis/bin/regshell set_value '[HKEY_THIS_MACHINE\Services\lsass\Parameters\Providers\Local]' LoginShellTemplate /bin/bash
	/opt/pbis/bin/lwsm refresh lsass
	/opt/pbis/bin/ad-cache --delete-all

	echo "Configuring sudoers..."
	echo "%DC\\\\linux^adm ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/Linux_Admins
fi


if [ "$2" == "cpanel" ] || [ "$3" == "cpanel" ]
then
        echo "We will now install cPanel..."
		#echo "Pre-configuring cpanel so that it uses EA3 instead of EA4..."
		#touch /etc/install_legacy_ea3_instead_of_ea4

		echo "Downloading cpanel installation file..."
		cd /home ; wget -N http://httpupdate.cpanel.net/latest

		echo "Activating local FastUpdate cPanel repo..."
		echo "HTTPUPDATE=del-cpanel-mirror01.dc.dataenligne.com" >> /etc/cpsources.conf

	        echo "Configuring basic cPanel configuration file /etc/wwwacct.conf..."
        	        echo "HOST $HOSTNAME" > /etc/wwwacct.conf
	                echo "HOMEDIR /home" >> /etc/wwwacct.conf
	                echo "ETHDEV eth0" >> /etc/wwwacct.conf
	                echo "NS ns1.dataenligne.com" >> /etc/wwwacct.conf
	                echo "NS2 ns2.dataenligne.com" >> /etc/wwwacct.conf
	                echo "HOMEMATCH home" >> /etc/wwwacct.conf
	                echo "NSTTL 86400" >> /etc/wwwacct.conf
	                echo "NS4" >> /etc/wwwacct.conf
	                echo "TTL 14400" >> /etc/wwwacct.conf
	                echo "ADDR $IP" >> /etc/wwwacct.conf
	                echo "DEFMOD paper_lantern" >> /etc/wwwacct.conf
	                echo "SCRIPTALIAS y" >> /etc/wwwacct.conf
	                echo "CONTACTPAGER" >> /etc/wwwacct.conf
	                echo "NS3" >> /etc/wwwacct.conf
	                echo "CONTACTEMAIL admin@dataenligne.com" >> /etc/wwwacct.conf
	                echo "LOGSTYLE combined" >> /etc/wwwacct.conf
	                echo "DEFWEBMAILTHEME paper_lantern" >> /etc/wwwacct.conf

		echo "Preparing backup directory..."
		mkdir /home/backup

		echo "Installing cPanel... This could take awhile, please be patient!"
		sh latest

		echo "Making sure we are excluding kernel* updates..."
		/usr/bin/sed -i "s/exclude=/exclude=kernel* /g" /etc/yum.conf

		echo "Doing initial cPanel/WHM configuration..."
		touch /etc/.whostmgrft
	 	/scripts/setupmailserver dovecot
		/scripts/setupnameserver bind
		/scripts/setupftpserver pure-ftpd

                echo "Installing ClamAV plugin..."
                /scripts/update_local_rpm_versions --edit target_settings.clamav installed
		/scripts/check_cpanel_rpms --fix --targets=clamav

		echo "Installing Cloud Flare cPanel plugin..."
		bash <(curl -s https://raw.githubusercontent.com/cloudflare/CloudFlare-CPanel/master/cloudflare.install.sh) -k 35636ae36c413904d60a502a9970e42e -n 'DATAenligne Inc.'
		
		echo "Downloading DATAenligne EA4 profile..."
		mkdir -p /etc/cpanel/ea4/profiles/custom/
		wget -O /etc/cpanel/ea4/profiles/custom/DATAenligne_EA4_Profile_Apache24_PHP56_and_7_rev31-jan-2017.json https://raw.githubusercontent.com/dataenligne/initial_setup/master/cPanel/EA4/DATAenligne_EA4_Profile_Apache24_PHP56_and_7_rev31-jan-2017.json

		echo "Activating and installing DATAenligne EA4 profile..."
		/usr/local/bin/ea_install_profile --install /etc/cpanel/ea4/profiles/custom/DATAenligne_EA4_Profile_Apache24_PHP56_and_7_rev31-jan-2017.json

		echo "Installing mod_cloudflare for EA4..."
		wget -O /etc/yum.repos.d/EA4-Mod-Cloudflare.repo http://download.opensuse.org/repositories/home:/Jperkster:/EA4_Mod_Cloudflare/CentOS-7/home:Jperkster:EA4_Mod_Cloudflare.repo
		yum -y install ea-apache24-mod_cloudflare

		echo "Installing ModSecurity Control cPanel Plugin..."
		cd /usr/src
		wget https://download.configserver.com/cmc.tgz
		tar -zxvf cmc.tgz ; rm -f cmc.tgz
		cd cmc ; ./install.sh
		cd .. ; rm -rf cmc

		echo "Installing CSF cPanel Pluging..."
		cd /usr/src ; wget https://download.configserver.com/csf.tgz
		tar xvf csf.tgz ; cd csf* ; ./install.sh
		cd ; rm -rf /usr/src/csf*
		 
		cd /etc/csf/
		wget -O csf.conf --user="download" --password="LAdfoladfoASDF23414134rFVD" http://del-internal-001.dataenligne.com/csf/csf.conf
		wget -O csf.deny --user="download" --password="LAdfoladfoASDF23414134rFVD" http://del-internal-001.dataenligne.com/csf/csf.deny
		wget -O csf.allow --user="download" --password="LAdfoladfoASDF23414134rFVD" http://del-internal-001.dataenligne.com/csf/csf.allow
		wget -O csf.pignore --user="download" --password="LAdfoladfoASDF23414134rFVD" http://del-internal-001.dataenligne.com/csf/csf.pignore
		wget -O csf.blocklists --user="download" --password="LAdfoladfoASDF23414134rFVD" http://del-internal-001.dataenligne.com/csf/csf.blocklists 
		csf -uf
		csf -ra

		echo "Configuring CSF clustering..."
		ssh -t -p22332 root@web.dataenligne.com "/root/lfd_add_node.sh $IP" 2>&1 > /dev/null

		echo "Installing WHMCS server status pluging and HTTP-Content / mysql connection validation page..."
		mkdir /usr/local/apache/htdocs/status
		cd /usr/local/apache/htdocs/status/ ; wget -O index.php --user="download" --password="LAdfoladfoASDF23414134rFVD" http://del-internal-001.dataenligne.com/whmcs/index.php.txt
		cd /usr/local/apache/htdocs/ ; wget -O site24x7.php --user="download" --password="LAdfoladfoASDF23414134rFVD" http://del-internal-001.dataenligne.com/site24x7/site24x7.php.txt
		chown -R nobody:nobody /usr/local/apache/htdocs/

		echo "Installing NFS-Utils for offsite backups..."
		yum -y install nfs-utils
		mkdir /home/nfsbackup

		echo "Installing Softaculous plugins..."
		wget -N http://files.softaculous.com/install.sh
		chmod 755 install.sh
		./install.sh
		sleep 3
		/bin/rm -f install.sh

		echo "Installing, activating and enabling auto-updates for the Comodo WAF (mod_security module)..."
		/usr/local/cpanel/scripts/modsec_vendor add https://waf.comodo.com/doc/meta_comodo_apache.yaml
		/usr/local/cpanel/scripts/modsec_vendor enable comodo_apache
		/usr/local/cpanel/scripts/modsec_vendor enable-updates comodo_apache
		/usr/local/cpanel/scripts/modsec_vendor enable-configs comodo_apache
		/usr/local/cpanel/scripts/modsec_vendor update comodo_apache

		echo "Configuring mail system preferences to forward all root emails to admin@dataenligne.com..."
		echo "admin@dataenligne.com" > /root/.forward
		echo "root" > /var/cpanel/userhomes/cpanel/.forward ; chmod 600 /var/cpanel/userhomes/cpanel/.forward ; chown cpanel:cpanel /var/cpanel/userhomes/cpanel/.forward

		echo "Configuring the MySQL monitoring user..."
		mysql -u root -e "CREATE USER 'monitoring'@'localhost' IDENTIFIED BY 'SDTghe54416DfRrf13@';flush privileges;"
		mkdir -p /root/cpanel3-skel/public_html/

		echo "Restarting Apache..."
		service httpd restart

		echo "Configuration default cPanel features..."
		echo "serverstatus=0" > /var/cpanel/features/default
		echo "autossl=0" >> /var/cpanel/features/default
		echo "bbs=0" >> /var/cpanel/features/default
		echo "chat=0" >> /var/cpanel/features/default
		echo "cpanelpro_support=0" >> /var/cpanel/features/default
		echo "fantastico=0" >> /var/cpanel/features/default
		echo "searchsubmit=0" >> /var/cpanel/features/default

		echo "Configuring cPanel's backup..."
		/usr/sbin/whmapi1 backup_config_set backupenable=1 backuptype=compressed backup_daily_enable=1 backupdays=0,1,2,3,4,5,6 backup_daily_retention=1 backup_monthly_enable=1 backupaccts=1 backuplogs=1 backupbwdata=1 localzonesonly=0 backupfiles=1 mysqlbackup=accounts backupdir=%2Fhome%2Fbackup keeplocal=1 backupmount=0 psqlbackup=0
		/usr/sbin/whmapi1 backup_destination_add name=OVH-NFS-HYPER02 type=Local path=%2Fhome%2Fnfsbackup%2F$SHORT_HOSTNAME upload_system_backup=on

		echo "Configuring fstab for remote offsite OVH backup..."
		echo "ftpback-bhs1-67.ip-198-100-151.net:/export/ftpbackup/ns526694.ip-149-56-17.net  /home/nfsbackup   nfs      auto,noatime,nolock,bg,nfsvers=3,intr,tcp,actimeo=1800 0 0" >> /etc/fstab
		/usr/bin/mount -a

		echo "Configuring DATAenligne cPanel theme..."
		mkdir -p /var/cpanel/customizations/brand/
		wget -O /var/cpanel/customizations/brand/favicon.ico https://raw.githubusercontent.com/dataenligne/initial_setup/master/cPanel/Theme/favicon2.ico
		wget -O /var/cpanel/customizations/brand/logo.png https://raw.githubusercontent.com/dataenligne/initial_setup/master/cPanel/Theme/logo.png
		wget -O /var/cpanel/customizations/brand/reseller_info.json https://raw.githubusercontent.com/dataenligne/initial_setup/master/cPanel/Theme/reseller_info.json
		cd /root/ ; curl -LOk  https://github.com/dataenligne/initial_setup/raw/master/cPanel/Theme/deltheme.zip
		unzip deltheme.zip
		mkdir -p /var/cpanel/customizations/includes/ ; /bin/cp -rpf includes/* /var/cpanel/customizations/includes/
		mkdir -p /var/cpanel/customizations/styled/ ; /bin/cp -rpf styled/* /var/cpanel/customizations/styled/
		/bin/rm -rf includes/ styled/ deltheme.zip
fi

mv /etc/rc.d/rc.local.good /etc/rc.d/rc.local
/bin/rm -f /root/cpanel_profile/cpanel.config

echo "Updating Rundeck resources.xml file..."
ssh -t -p22332 root@del-internal-001.dataenligne.com << EOF
 ex -sc '22i|	<node name="$SHORT_HOSTNAME" description="cPanel Dedicated Server" tags="cpanel,dedicated,hyperv-centos7" hostname="$HOSTNAME:22332" osArch="amd64" osFamily="unix" osName="CentOS7" username="root" ssh-authentication="privateKey"/>|' -cx /var/rundeck/projects/DEL-VMS/etc/resources.xml
EOF

echo "Adding hostname to dataenligne.com's DNS zone file at CloudFlare..."
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/166c3971b0a77f70c1459b4dbe60aa09/dns_records" -H "X-Auth-Email: cloudflare@dataenligne.com" -H "X-Auth-Key: 41687f8481287c052e90670f7ce044a9f040a" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"$SHORT_HOSTNAME\",\"content\":\"$IP\"}"

sleep 35

history -c ; yum -y autoremove ; yum -y clean all

T="$(($(date +%s)-T))"
echo "Installation and configuration took ${T} seconds!"

echo "If you have selected cPanel to be installed, you now have to configure it through WHM!"
echo "Do not forget to create the mysql user for the HTTP-Content check!"

echo "Initial Setup completed on $HOSTNAME." | mail -s "Initial Setup completed on $HOSTNAME." admin@dataenligne.com
 

rm -rf /tmp/* ; echo -n > /var/log/wtmp ; echo -n > /var/log/btmp ; rm -rf /root/initial_setup/
cat /dev/null > ~/.bash_history && history -c && rm -rf $0 && exit
