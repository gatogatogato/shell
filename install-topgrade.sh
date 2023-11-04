#!/bin/zsh
SECONDS=0
echo "---------------------------------------------------"
echo "Install topgrade on Debian or Raspbian"
clear
XNAME=$(grep "^NAME=" /etc/os-release)
ARCHNAME=$(uname -a)
RET=$?
if [[ ${RET} -eq 0 ]]; then
	mkdir ~/topgrade
	cd ~/topgrade
	if [[ "$ARCHNAME" == *"aarch64"* ]]; then
		echo "RASPIAN ARM"
		FILE=topgrade-v13.0.0-aarch64-unknown-linux-gnu.tar.gz
	elif [[ "$XNAME" == *"Debian"* ]]; then
		echo "DEBIAN"
		FILE=topgrade-v13.0.0-x86_64-unknown-linux-gnu.tar.gz
	else
		echo "UNKNOWN"
	fi
	wget https://github.com/topgrade-rs/topgrade/releases/download/v13.0.0/${FILE}
	tar xzvf ${FILE} && rm ${FILE}
	echo "Run with ~/topgrade/topgrade"
else
	echo "Could not determine OS."
fi

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"


