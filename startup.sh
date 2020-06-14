#! /bin/bash
sudo setenforce 0
sudo yum install httpd php git -y
sudo systemctl start httpd
sudo systemctl enable httpd

