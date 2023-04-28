#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~/tk4-$(date +%Y-%m-%d_%H.%M)

export download_server_tk4="https://archive.org/download/tk4_ispf.tar/"
export zip_file_tk4="tk4_ispf.tar.gz"
# export download_server_tk4="http://wotho.ethz.ch/tk4-/"
# export zip_file_tk4="tk4-_v1.00_current.zip"

export download_server_kicks="https://github.com/moshix/kicks/raw/master/"
export zip_file_kicks="kicks-tso-v1r5m0.zip"

export download_server_brexx="https://github.com/mvslovers/brexx370/releases/download/V2R2M1/"
export zip_file_brexx="BREXX370_V2R2M1.zip"
#-----------------------------------------------------------------
echo "Create new TK4- instance in ${installdir}..."
mkdir -p ${installdir}
cd ${installdir}

echo "Download ${download_server_tk4}${zip_file_tk4}..."
echo "(this may take a while)"
wget -q ${download_server_tk4}${zip_file_tk4}

echo "Unzip ${zip_file_tk4}..."
# unzip -q ${zip_file_tk4} && rm ${zip_file_tk4}
tar xzf ${zip_file_tk4} 2> /dev/null # && rm ${zip_file_tk4}
mv archive.org/* . && rm -rf archive.org

echo "Delete misc. files to save some space..."
find . -name "*.bat" -type f -delete
rm -rf ${installdir}/hercules/windows/
rm -rf ${installdir}/hercules/darwin/
rm -rf ${installdir}/hercules/source/

echo "Set default run mode to CONSOLE..."
echo "CONSOLE" > ${installdir}/unattended/mode
# otherwise DAEMON

echo "Change execution shell to ZSH..."
sed --in-place=.old -e 's=/bin/bash=/bin/zsh=g' ${installdir}/mvs

# echo "Change FTP Server on MVS to start automatically..."
# echo "/START FTPD,SRVPORT=21021" >> ${installdir}/local_scripts/10

# echo "Change FTP Server on MVS to stop automatically..."
# echo "/STOP FTPD" >> ${installdir}/scripts/shutdown

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

cd ${installdir}
echo "Download NETSOL stuff for Network Solicitor graphics..."
git clone https://github.com/MVS-sysgen/NETSOL.git
cd NETSOL

echo "Finished."