#!/usr/bin/env zsh
# Use 
#   cd && rm -rf ~/shell && git clone https://github.com/gatogatogato/shell ~/shell
# before runnnig this script 
export DIVIDER="---------------------------------------------------------"
SECONDS=0
TARGET_DIR=~/shell
OS=$(uname -a)
#
echo ${DIVIDER}
cd ${TARGET_DIR}

echo "Update from GitHub..."
git pull origin master -q
echo ${DIVIDER}

echo "Make shell files executable..."
chmod +x ${TARGET_DIR}/*.sh
echo ${DIVIDER}

case "${OS}" in
  *Linux*) 
	echo "Copy specific stuff for Linux platform..." 
	cp ${TARGET_DIR}/update-debian.sh ~/update-debian.sh
	;;
  *Darwin*) 
	echo "Copy specific stuff for MacOS platform..." 
	;;
esac
echo "Copy generic stuff for all platforms..." 
cp ${TARGET_DIR}/dot-zshrc.txt ~/.zshrc

if [ "$SHELL" = "/bin/zsh" ]; then
	echo "Use 'source ~/.zshrc' or log on to new shell instance to activate changes."
fi

echo ${DIVIDER}
echo "Took ${SECONDS} seconds to deploy."
echo "End of script."
echo ${DIVIDER}