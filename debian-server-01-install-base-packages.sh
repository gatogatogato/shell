#!/usr/bin/env zsh
#---------------------------------------------------------------------------------------------------
PACKAGES_FILE="/home/gato/shell/zz-debian-server-base-packages.txt"
#---------------------------------------------------------------------------------------------------
echo "Update apt database and packages..."
sudo apt-get -qq update
sudo apt-get -qq upgrade
sudo apt-get -qq full-upgrade

while read -r PACKAGE
do
	echo "##### Install ${PACKAGE}..."
	sudo apt-get --yes -q install ${PACKAGE}
done < "${PACKAGES_FILE}"