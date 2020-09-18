#!/usr/bin/env zsh
echo "Install base packages via apt..."
#---------------------------------------------------------------------------------------------------
PACKAGES="apt-transport-https ca-certificates curl debsums gnupg-agent hdparm hercules libglib2.0 mosh mutt nano net-tools nmap reboot-notifier software-properties-common tmux unzip wget"
#---------------------------------------------------------------------------------------------------
sudo apt update
sudo apt upgrade
sudo apt full-upgrade
for PACKAGE in ${PACKAGES}; do
	echo "Install ${PACKAGE}..."
	sudo apt-get --yes -qq install ${PACKAGE}
done