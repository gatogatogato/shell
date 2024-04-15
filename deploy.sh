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

echo "Appending our zsh stuff to the already existing one..." 
cat ${TARGET_DIR}/dot-zshrc.txt >> ~/.zshrc

case "${OS}" in
  *Linux*)
	echo "Copy generic stuff for all Linux platforms..." 
	cp ${TARGET_DIR}/update-debian.sh ~/
	cp ${TARGET_DIR}/README.txt ~/shell-clone-command.txt
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