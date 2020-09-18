#!/bin/zsh
SECONDS=0
echo "---------------------------------------------------"
sudo apt --yes update
sudo apt --yes full-upgrade
sudo apt --yes autoclean
sudo apt --yes autoremove
echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"