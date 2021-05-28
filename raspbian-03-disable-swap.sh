#!/usr/bin/env zsh
echo "Disable swapfile on raspbian..."
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo systemctl disable dphys-swapfile
