#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~/tk5-$(date +%Y-%m-%d_%H.%M)

export download_server_tk5="https://www.prince-webdesign.nl/images/downloads/"
export zip_file_tk5="mvs-tk5.zip"

#-----------------------------------------------------------------
echo "Create new TK5 instance in ${installdir}..."
mkdir -p "${installdir}"
cd "${installdir}"

echo "Download ${download_server_tk5}${zip_file_tk5}..."
echo "(this may take a while)"
wget -q "${download_server_tk5}${zip_file_tk5}"

echo "Unzip ${zip_file_tk5}..."
unzip -q "${zip_file_tk5}" && rm "${zip_file_tk5}"
# tar xzf ${zip_file_tk5} 2> /dev/null # && rm ${zip_file_tk5}
mv mvs-tk5/* . && rm -rf mvs-tk5

echo "Delete misc. files to save some space..."
find . -name "*.bat" -type f -delete
rm -rf "${installdir}/hercules/windows/"
rm -rf "${installdir}/hercules/darwin/"
rm -rf "${installdir}/hercules/source/"

echo "Set default run mode to CONSOLE..."
echo "CONSOLE" > "${installdir}/unattended/mode"
# otherwise DAEMON

echo "Change execution shell to ZSH..."
sed --in-place=.old -e 's=/bin/bash=/bin/zsh=g' "${installdir}/mvs"

cd "${installdir}"
echo "Download NETSOL stuff for Network Solicitor graphics..."
git clone https://github.com/MVS-sysgen/NETSOL.git
cd NETSOL

echo "Finished."