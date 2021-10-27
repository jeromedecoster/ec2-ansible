#!/bin/bash
yum update -y
yum install -y httpd
systemctl enable httpd
systemctl start httpd
echo '<h3>Installed by user-data script</h3>' > /var/www/html/index.html