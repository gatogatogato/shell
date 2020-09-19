#!/usr/bin/env zsh
#---------------------------------------------------------------------------------------------------
# PACKAGES="apt-transport-https ca-certificates curl debsums gnupg-agent hdparm hercules libglib2.0 mosh mutt nano net-tools nmap reboot-notifier software-properties-common tmux unzip wget"
PACKAGES_FILE="/home/pi/shell/zz-raspbian-base-packages.txt"
#---------------------------------------------------------------------------------------------------
echo "Update apt database and packages..."
sudo apt-get -qq update
sudo apt-get -qq upgrade
sudo apt-get -qq full-upgrade

# echo "Install base packages via apt..."
# for PACKAGE in ${PACKAGES}; do
# done

while read -r PACKAGE
do
	echo "##### Install ${PACKAGE}..."
	sudo apt-get --yes -q install ${PACKAGE}
done < "${PACKAGES_FILE}"