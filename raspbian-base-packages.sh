#!/usr/bin/env zsh
echo "Install base packages via apt..."
#---------------------------------------------------------------------------------------------------
PACKAGES="apt-transport-https ca-certificates curl debsums gnupg-agent hdparm hercules libglib2.0 mosh mutt nano net-tools nmap reboot-notifier software-properties-common tmux unzip wget"
#---------------------------------------------------------------------------------------------------
sudo apt update
sudo apt upgrade
sudo apt full-upgrade
sudo apt-get --yes install apt-transport-https ca-certificates gnupg-agent software-properties-common
sudo apt-get --yes install net-tools libglib2.0 nano mutt hdparm
sudo apt-get --yes install curl wget mosh tmux nmap hercules unzip
sudo apt-get --yes install debsums reboot-notifier
for PACKAGE in ${PACKAGES}; do
	echo "Install ${PACKAGE}..."
	sudo apt-get --yes install ${PACKAGE}
done