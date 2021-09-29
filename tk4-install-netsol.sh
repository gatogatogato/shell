#!/bin/zsh
#------------------------------------------------------------------------------------
# Where is tk4- installed?
INSTALLDIR=~/tk4-/
# Where is tk4- running?
HERC_DNS=host.raspberrypi
# Where is tk4-'s RDR port?
HERC_READER_PORT=3505
# Where is tk4-'s syslog port?
HERC_SYSLOG_PORT=8038
# How many lines do we delete from sample JCLs' top?
DEL_LINES=5
#------------------------------------------------------------------------------------
echo "Clone NETSOL JCLs from GitHub..."
cd ${INSTALLDIR}
git clone https://github.com/MVS-sysgen/NETSOL.git
cd NETSOL
#------------------------------------------------------------------------------------
JOBCARD=/tmp/jobcard.txt
echo "Fixing jobcard for remote submit..."
echo "//HERC01G JOB CLASS=A,MSGCLASS=H,MSGLEVEL=(1,1),REGION=3M," >  ${JOBCARD}
echo "// NOTIFY=HERC01,USER=HERC01,PASSWORD=CUL8TR"               >> ${JOBCARD}
for JCLFILE in *.JCL; do
  for number in {1..${DEL_LINES}}
  do
    sed '1d' ${JCLFILE} > tmpfile && mv tmpfile ${JCLFILE}
  done
  cat ${JOBCARD} >  ${JCLFILE}.new
  cat ${JCLFILE} >> ${JCLFILE}.new
  cp ${JCLFILE}.new ${JCLFILE} && rm ${JCLFILE}.new
SCRIPT_LINES=$(cat <<'END_HEREDOC'
cat ${JCLFILE} | netcat -w1 ${HERC_DNS} ${HERC_READER_PORT}
curl -s -d "command=/P+TSO" -X POST http://${HERC_DNS}:${HERC_SYSLOG_PORT}/cgi-bin/tasks/syslog -o /dev/null
curl -s -d "command=/Z+NET,QUICK" -X POST http://${HERC_DNS}:${HERC_SYSLOG_PORT}/cgi-bin/tasks/syslog -o /dev/null
curl -s -d "command=/S+NET" -X POST http://${HERC_DNS}:${HERC_SYSLOG_PORT}/cgi-bin/tasks/syslog -o /dev/null
END_HEREDOC
  echo ${SCRIPT_LINES} > install-${JCLFILE}.sh
)
done
echo "You can use the install-*.sh scripts to install any network solicitor"
rm ${JOBCARD}
#------------------------------------------------------------------------------------
exit