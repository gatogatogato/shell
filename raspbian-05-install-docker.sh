#!/usr/bin/env zsh
mkdir -m 750 /home/pi/dockerData
curl -fsSL https://get.docker.com -o ~/get-docker.sh 
sudo sh ~/get-docker.sh
sudo usermod -aG docker pi
rm ~/get-docker.sh

sudo systemctl enable docker
sudo systemctl start docker
