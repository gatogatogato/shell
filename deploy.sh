#!/usr/bin/env zsh
# Use 
#   git clone https://github.com/gatogatogato/shell ~/shell
# before runnnig this script 
export DIVIDER="---------------------------------------------------------"
SECONDS=0
TARGET_DIR=~/shell
#
echo ${DIVIDER}
cd ${TARGET_DIR}
echo "Update from GitHub..."
git pull origin master
echo ${DIVIDER}
cp ${TARGET_DIR}/dot-zshrc.txt ~/.zshrc
echo ${DIVIDER}
echo "Took ${SECONDS} seconds to deploy."
echo "End of script."
echo ${DIVIDER}