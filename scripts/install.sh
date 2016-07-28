#!/bin/bash
set -o errexit

MYSQL_ROOT_PASSWORD=r00t
PHP_DATETIMEZONE=${PHP_DATETIMEZONE:-Europe/London}

apt-get update
debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"

apt-get -y install git
apt-get -y install apache2 mysql-server php-mysql php libapache2-mod-php php-mcrypt php-json php-xml php-dom
apt-get clean

echo "date.timezone=\"$PHP_DATETIMEZONE\"" >> /etc/php/7.0/cli/php.ini

#R
echo "deb http://cran.rstudio.com/bin/linux/ubuntu trusty/" >> /etc/apt/sources.list
gpg --keyserver keyserver.ubuntu.com --recv-key E084DAB9
gpg -a --export E084DAB9 | apt-key add -
apt-get update
apt-get -y --allow-unauthenticated install r-base
apt-get clean
R -e 'install.packages("session", repos="http://cran.rstudio.com/")'
R -e 'install.packages("rjson", repos="http://cran.rstudio.com/")'


mkdir /var/www/vhosts/

cd /var/www/vhosts/
git clone https://github.com/campsych/concerto-platform.git
mv concerto-platform/ /var/www/vhosts/concerto
chown -R www-data /var/www


# /etc/apache2/sites-enabled/000-default.conf: DocumentRoot /var/www/html -> DocumentRoot /var/www/vhosts/concerto/web
sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www\/vhosts\/concerto\/web/g' /etc/apache2/sites-enabled/000-default.conf

# /etc/apache2/apache2.conf
#<Directory /var/www/>
#        Options Indexes FollowSymLinks
#        AllowOverride None
#        Require all granted
#</Directory>
# ->
#<Directory /var/www/>
#        Options Indexes FollowSymLinks
#        AllowOverride All
#        Require all granted
#</Directory>
cat /etc/apache2/apache2.conf | awk '/<Directory \/var\/www\/>/,/AllowOverride None/{sub("None", "All",$0)}{print}' > /etc/apache2/apache2.conf.tmp && mv /etc/apache2/apache2.conf.tmp /etc/apache2/apache2.conf

cp /var/www/vhosts/concerto/app/config/parameters.yml.dist /var/www/vhosts/concerto/app/config/parameters.yml
cp /var/www/vhosts/concerto/app/config/parameters_nodes.yml.dist /var/www/vhosts/concerto/app/config/parameters_nodes.yml
cp /var/www/vhosts/concerto/app/config/parameters_test_runner.yml.dist /var/www/vhosts/concerto/app/config/parameters_test_runner.yml
cp /var/www/vhosts/concerto/app/config/parameters_uio.yml.dist /var/www/vhosts/concerto/app/config/parameters_uio.yml

# /var/www/vhosts/concerto/app/config/parameters.yml
# database_name: concerto
# database_user: root
# database_password: $MYSQL_ROOT_PASSWORD
sed -i 's/database_name: .*$/database_name: concerto/g' /var/www/vhosts/concerto/app/config/parameters.yml
sed -i 's/database_user: .*$/database_user: root/g' /var/www/vhosts/concerto/app/config/parameters.yml
sed -i "s/database_password: .*$/database_password: $MYSQL_ROOT_PASSWORD/g" /var/www/vhosts/concerto/app/config/parameters.yml



cd /var/www/vhosts/concerto/
curl -s http://getcomposer.org/installer | php
php -dmemory_limit=1G composer.phar install --prefer-source --no-interaction

chown -R www-data /var/www

apt-get -y install npm
apt-get clean
npm install -g bower
ln -s /usr/bin/nodejs /usr/bin/node
cd /var/www/vhosts/concerto/src/Concerto/PanelBundle/Resources/public/angularjs
su www-data -s /bin/bash -c "bower install"
cd /var/www/vhosts/concerto/src/Concerto/TestBundle/Resources/public/angularjs
su www-data -s /bin/bash -c "bower install"

chown -R www-data /var/www

cd /var/www/vhosts/concerto/src/Concerto/TestBundle/Resources/R
R CMD INSTALL concerto5

su www-data -s /bin/bash -c "php /var/www/vhosts/concerto/app/check.php"

#service mysql start
#service apache2 start

service mysql start
mysql -u root -p$MYSQL_ROOT_PASSWORD -e 'CREATE DATABASE concerto;'
 
chown -R www-data /var/www

cd /var/www/vhosts/concerto
su www-data -s /bin/bash -c "php app/console concerto:setup"
su www-data -s /bin/bash -c "php app/console concerto:r:cache"
su www-data -s /bin/bash -c "php app/console concerto:content:import"

chown -R www-data /var/www

service mysql stop
apt-get clean
echo "----------end------------"
