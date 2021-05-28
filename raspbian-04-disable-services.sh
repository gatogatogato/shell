#!/usr/bin/env zsh
echo "Disable unwanted services..."
sudo systemctl disable bluetooth
sudo systemctl stop bluetooth
sudo systemctl disable avahi-daemon.service
sudo systemctl stop avahi-daemon.service
sudo systemctl disable avahi-daemon.socket
sudo systemctl stop avahi-daemon.socket
sudo systemctl disable triggerhappy.service
sudo systemctl stop triggerhappy.service
sudo systemctl disable triggerhappy.socket
sudo systemctl stop triggerhappy.socket