#!/bin/zsh
SECONDS=0
echo "---------------------------------------------------"
sudo apt-get --yes update
sudo apt-get --yes full-upgrade
sudo apt-get --yes autoclean
sudo apt-get --yes autoremove
echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"