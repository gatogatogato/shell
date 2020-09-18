#!/usr/bin/env zsh
# Use 
#   cd && rm -rf ~/shell && git clone https://github.com/gatogatogato/shell ~/shell
# before runnnig this script 
export DIVIDER="---------------------------------------------------------"
SECONDS=0
TARGET_DIR=~/shell
#
echo ${DIVIDER}
cd ${TARGET_DIR}

echo "Update from GitHub..."
git pull origin master -q
echo ${DIVIDER}

echo "Make shell files executable..."
chmod +x ${TARGET_DIR}/*.sh
echo ${DIVIDER}

echo "Copy files..."
cp ${TARGET_DIR}/dot-zshrc.txt ~/.zshrc

if [[ "$SHELL" = "/bin/zsh" ]]; then
	echo "We are in ZSH. Activate new ~/.zshrc..."
	source ~/.zshrc
fi

echo "Took ${SECONDS} seconds to deploy."
echo "End of script."
echo ${DIVIDER}