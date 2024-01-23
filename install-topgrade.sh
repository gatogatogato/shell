#!/bin/zsh
SECONDS=0
echo "---------------------------------------------------"
echo "Install topgrade on Debian or Raspbian"
clear
XNAME=$(hostname)
RET=$?
if [[ ${RET} -eq 0 ]]; then
	if [[ "$XNAME" == *"raspberrypi"* ]]; then
		echo "Running on raspberrypi"
		FILE=topgrade-v14.0.0-aarch64-unknown-linux-musl.tar.gz
	elif [[ "$XNAME" == *"Debian"* ]]; then
		echo "DEBIAN"
		FILE=topgrade-v14.0.0-x86_64-unknown-linux-gnu.tar.gz
	else
		echo "UNKNOWN"
	fi
	wget https://github.com/topgrade-rs/topgrade/releases/download/v14.0.0/${FILE}

	if [ -d "~/topgrade" ]; then
	  echo "Topgrade directory exists. Renaming..."
	  TS=$(date +"%Y-%m-%d_%H.%M.%S")
	  mv ~/topgrade ~/topgrade-${TS}
	else
		mkdir ~/topgrade
		cd ~/topgrade
		tar xzvf ${FILE} && rm ${FILE}
	fi
	echo "Run with ~/topgrade/topgrade"
else
	echo "Could not determine OS."
fi

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"
