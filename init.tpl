#!/bin/bash
sudo apt update
sudo apt-get install -y nfs-common apache2 ghostscript libapache2-mod-php php php-bcmath php-curl php-imagick php-intl php-json php-mbstring php-mysql php-xml php-zip
sudo mkdir -p /var/www/html
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${efs_mount_dns}:/ /var/www/html
sudo chown www-data:www-data /var/www/html
sudo curl https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/sbin/wp
sudo chmod +x /usr/local/sbin/wp 
sudo -u www-data wp core download --path=/var/www/html || true
sudo -u www-data cp -n /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sudo -u www-data sed -i 's/database_name_here/${db_name}/' /var/www/html/wp-config.php
sudo -u www-data sed -i 's/username_here/${db_user}/' /var/www/html/wp-config.php
sudo -u www-data sed -i 's/password_here/${db_pass}/' /var/www/html/wp-config.php
sudo -u www-data sed -i 's/localhost/${db_endpoint}/' /var/www/html/wp-config.php
sudo -u www-data wp core is-installed --path=/var/www/html/ || sudo -u www-data wp core install --url=${site_url} --title="EPAM AWS Task (ZhdanovAS)" --admin_user=${admin_name} --admin_password=${admin_pass} --admin_email=${admin_email} --path='/var/www/html/' --skip-email
sudo -u www-data wp plugin --path=/var/www/html install server-ip-memory-usage --activate
