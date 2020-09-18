#!/usr/bin/env zsh
#---------------------------------------------------------------------------------------------------
PACKAGES="apt-transport-https ca-certificates curl debsums gnupg-agent hdparm hercules libglib2.0 mosh mutt nano net-tools nmap reboot-notifier software-properties-common tmux unzip wget"
#---------------------------------------------------------------------------------------------------
echo "Update apt database and packages..."
sudo apt -q update
sudo apt -q upgrade
sudo apt -q full-upgrade

echo "Install base packages via apt..."
for PACKAGE in ${PACKAGES}; do
	echo "Install ${PACKAGE}..."
	sudo apt-get --yes -qq install ${PACKAGE}
done