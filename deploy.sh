#!/usr/bin/env zsh
# Use 
#   cd && rm -rf ~/shell && git clone https://github.com/gatogatogato/shell ~/shell && zsh ~/shell/deploy.sh
# before runnnig this script 

export DIVIDER="---------------------------------------------------------"
. /etc/os-release 2> /dev/null
SECONDS=0
TARGET_DIR=~/shell
OS=$(uname -a)
#
echo ${DIVIDER}
cd ${TARGET_DIR}

echo "Update from GitHub..."
git pull -q origin master
echo ${DIVIDER}
echo "Make shell files executable..."
chmod +x ${TARGET_DIR}/*.sh

echo ${DIVIDER}

echo "Copy generic stuff for all platforms..." 
cp ${TARGET_DIR}/dot-zshrc.txt ~/.zshrc

case "${OS}" in
  *Linux*)
	echo "Copy generic stuff for all Linux platforms..." 
	cp ${TARGET_DIR}/update-debian.sh ~/
	cp ${TARGET_DIR}/README.txt ~/shell-clone-command.txt
	if [[ ${OS} =~ "raspberrypi" ]]; 	then
		echo "Copy specific stuff for raspberrypi platform..." 
		cp ${TARGET_DIR}/update-pihole-blocklists.sh ~/
		cp ${TARGET_DIR}/prepare-new-tk4-.sh ~/
		cp ${TARGET_DIR}/prepare-new-tk5.sh ~/		
		cp ${TARGET_DIR}/mvs-tmux.sh ~/
		cp ${TARGET_DIR}/mvs-langtest.sh ~/
		cp ${TARGET_DIR}/tk4-install-brexx.sh ~/
		cp ${TARGET_DIR}/tk4-install-kicks.sh ~/
		cp ${TARGET_DIR}/tk4-install-netsol.sh ~/
		cp ${TARGET_DIR}/install-topgrade.sh ~/
	fi
	if [[ ${PRETTY_NAME} =~ "Debian" ]]; 	then
    	echo "Copy specific stuff for Debian platform..." 
		cp ${TARGET_DIR}/gato-tmux.sh ~/
		cp ${TARGET_DIR}/install-topgrade.sh ~/		
	fi
	;;
  *Darwin*) 
	echo "Copy specific stuff for MacOS platform..."
	cp ${TARGET_DIR}/homebrew-setup.sh ~/
	;;
esac

echo ${DIVIDER}
echo "Took ${SECONDS} seconds to deploy."
echo "End of script."
echo ${DIVIDER}