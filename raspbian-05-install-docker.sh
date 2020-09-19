#!/usr/bin/env zsh
curl -fsSL https://get.docker.com -o ~/get-docker.sh 
sudo sh ~/get-docker.sh
sudo usermod -aG docker pi
rm ~/get-docker.sh