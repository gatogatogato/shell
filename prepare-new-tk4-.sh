#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~/tk4-$(date +%Y-%m-%d_%H.%M)

export download_server_tk4="http://wotho.ethz.ch/tk4-/"
export zip_file_tk4="tk4-_v1.00_current.zip"

export download_server_kicks="https://github.com/moshix/kicks/raw/master/"
export zip_file_kicks="kicks-tso-v1r5m0.zip"

export download_server_brexx="https://github.com/mvslovers/brexx370/releases/download/V2R2M1/"
export zip_file_brexx="BREXX370_V2R2M1.zip"
#-----------------------------------------------------------------
echo "Create new TK4- instance in ${installdir}..."
mkdir -p ${installdir}
cd ${installdir}

echo "Download ${download_server_tk4}${zip_file_tk4}..."
wget -q ${download_server_tk4}${zip_file_tk4}

echo "Unzip ${zip_file_tk4}..."
unzip -q ${zip_file_tk4} && rm ${zip_file_tk4}

echo "Delete Windows installation files to save some space..."
rm -rf ${installdir}/hercules/windows/
echo "Delete Windows batch files..."
find . -name "*.bat" -type f -delete
echo "Delete OSX installation files to save some space..."
rm -rf ${installdir}/hercules/darwin/

echo "Set default run mode to CONSOLE..."
echo "CONSOLE" > ${installdir}/unattended/mode
# otherwise DAEMON

echo "Change execution shell to ZSH..."
sed --in-place=.old -e 's=/bin/bash=/bin/zsh=g' ${installdir}/mvs

echo "Change FTP Server on MVS to start automatically..."
echo "/S FTPD,SRVPORT=21021" >> ${installdir}/local_scripts/10

echo "Change FTP Server on MVS to stop automatically..."
echo "/P FTPD" >> ${installdir}/scripts/shutdown


cd ${installdir}
mkdir kicks
echo "Download ${download_server_kicks}${zip_file_kicks}..."
cd kicks
wget -q ${download_server_kicks}${zip_file_kicks}
echo "Unzip ${zip_file_kicks}..."
unzip -q ${zip_file_kicks}
rm ${zip_file_kicks}

cd ${installdir}
mkdir brexx
echo "Download ${download_server_brexx}${zip_file_brexx}..."
cd brexx
wget -q ${download_server_brexx}${zip_file_brexx}
echo "Unzip ${zip_file_brexx}..."
unzip -q ${zip_file_brexx}
rm ${zip_file_brexx}

echo "Finished."