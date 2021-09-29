#!/bin/zsh
#------------------------------------------------------------------------------------
JCL_FILE_01=/tmp/jcl01.txt
JCL_FILE_02=/tmp/jcl02.txt
HERC_DNS=host.raspberrypi
HERC_READER_PORT=3505
HERC_SYSLOG_PORT=8038
#------------------------------------------------------------------------------------
ALL_LINES_01=$(cat <<'END_HEREDOC'
//HERC01G JOB CLASS=A,MSGCLASS=H,MSGLEVEL=(1,1),REGION=3M,
// NOTIFY=HERC01,USER=HERC01,PASSWORD=CUL8TR
//SCRATCH EXEC PGM=IEFBR14
//SYSUT2 DD DSN=HERC01.KICKS.V1R5M0.XMI,DISP=(MOD,DELETE),
//       UNIT=SYSDA,SPACE=(TRK,(0))
//*
//LOAD EXEC PGM=IEBGENER
//SYSPRINT DD SYSOUT=*
//SYSIN  DD DUMMY,DCB=BLKSIZE=80
//SYSUT1 DD UNIT=10C,DISP=OLD,DCB=(RECFM=FB,LRECL=80,BLKSIZE=3200)
//SYSUT2 DD DSN=HERC01.KICKS.V1R5M0.XMI,DISP=(,CATLG),
//      DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=3200),
//      UNIT=SYSDA,VOL=SER=PUB002,SPACE=(TRK,(225,15),RLSE)
END_HEREDOC
)
#------------------------------------------------------------------------------------
ALL_LINES_02=$(cat <<'END_HEREDOC'
//HERC01R  JOB CLASS=A,MSGCLASS=H,MSGLEVEL=(1,1),REGION=4096K,
// NOTIFY=HERC01,USER=HERC01,PASSWORD=CUL8TR
//RECV370 EXEC PGM=RECV370
//RECVLOG  DD SYSOUT=*
//XMITIN   DD DSN=HERC01.KICKS.V1R5M0.XMI,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSUT1   DD DSN=&&SYSUT1,
//         UNIT=SYSDA,
//         SPACE=(TRK,(300,60)),
//         DISP=(NEW,DELETE,DELETE)
//SYSUT2   DD DSN=HERC01.KICKS.V1R5M0.BIGPDS,
//         UNIT=(SYSDA,SEP=SYSUT1),
//         SPACE=(TRK,(300,60,20)),
//         DISP=(NEW,CATLG,DELETE)
//SYSIN    DD DUMMY
END_HEREDOC
)
#------------------------------------------------------------------------------------
echo "$ALL_LINES_01" > ${JCL_FILE_01}
echo "$ALL_LINES_02" > ${JCL_FILE_02}
#------------------------------------------------------------------------------------
echo "DISCLAIMER"
echo "  This script should be run immediately after tk4- was set up."
echo "  This script can only be run when Hercules/tk4- is running."
echo "  This script should be run on raspberrypi or on MacOS."
echo "Press enter to continue..."
read
#------------------------------------------------------------------------------------
echo "Sending the following command to the Hercules console first"
echo "  devinit 10c /home/pi/tk4-/kicks/kicks-tso-v1r5m0/kicks-tso-v1r5m0.xmi"
echo " "
curl -s -d "command=devinit+010c+/home/pi/tk4-/kicks/kicks-tso-v1r5m0/kicks-tso-v1r5m0.xmi" -X POST http://${HERC_DNS}:${HERC_SYSLOG_PORT}/cgi-bin/tasks/syslog -o /dev/null
#----------------------------------------------------------------------------
cat ${JCL_FILE_01} | netcat -w1 ${HERC_DNS} ${HERC_READER_PORT}
sleep 30
cat ${JCL_FILE_02} | netcat -w1 ${HERC_DNS} ${HERC_READER_PORT}
#----------------------------------------------------------------------------
echo "Sending the following commands to the Hercules console"
echo "  detach 10c"
echo "  attach 010C 3505 jcl/dummy eof ascii trunc"
curl -s -d "command=detach+010c" -X POST http://${HERC_DNS}:${HERC_SYSLOG_PORT}/cgi-bin/tasks/syslog -o /dev/null
curl -s -d "command=attach+010C+3505+jcl/dummy+eof+ascii+trunc" -X POST http://${HERC_DNS}:${HERC_SYSLOG_PORT}/cgi-bin/tasks/syslog -o /dev/null
#----------------------------------------------------------------------------
echo "Next do these steps"
echo "  edit/submit HERC01.KICKS.V1R5M0.BIGPDS(V1R5M0)"
echo "  run in TSO prompt:"
echo "    EXEC 'HERC01.KICKSSYS.V1R5M0.CLIST(KFIX)'"
echo "  edit/submit all jobs in HERC01.KICKS.V1R5M0.INSTLIB"
echo " "
echo "You can delete this shell script after KICKS was installed successfully."
#----------------------------------------------------------------------------
exit