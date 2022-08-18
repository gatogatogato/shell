#!/bin/zsh
SECONDS=0
echo "---------------------------------------------------"
echo "Install topgrade on Debian or Raspbian"
clear
XNAME=$(grep "^NAME=" /etc/os-release)
RET=$?
if [[ ${RET} -eq 0 ]]; then
	if [[ "$XNAME" == *"Raspbian"* ]]; then
		echo "RASPIAN"
		FILE=topgrade-v9.0.1-armv7-unknown-linux-gnueabihf.tar.gz
	elif [[ "$XNAME" == *"Debian"* ]]; then
		echo "DEBIAN"
		FILE=topgrade-v9.0.1-x86_64-unknown-linux-gnu.tar.gz
	else
		echo "UNKNOWN"
	fi
else
	echo "Could not determine OS."
fi

mkdir ~/topgrade
cd ~/topgrade
wget https://github.com/r-darwish/topgrade/releases/download/v9.0.1/${FILE}
tar xzvf ${FILE} && rm ${FILE}
~/topgrade/topgrade

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"
