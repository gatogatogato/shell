#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~pi/tk4-
#-----------------------------------------------------------------
echo "Build langtest for performance testing..."
cd ${installdir}

git clone "https://github.com/wfjm/mvs38j-langtest"
git clone "https://github.com/wfjm/herc-tools"

export PATH=${PATH}:${installdir}/herc-tools/bin


clear
echo "--------------------------------------------"
echo " Next adapt the JCL defaults manually first "
echo "--------------------------------------------"
echo ""
echo "Press enter to continue..."
read
cd ${installdir}/mvs38jlang/jcl
nano job_asm_clg.JESI
cd ${installdir}/mvs38jlang/jobs
make


clear
echo "--------------------------------------------"
echo " Submit JCL with                            "
echo "   hercjis *asm*.jcl                        "
echo "--------------------------------------------"
echo ""
echo "Press enter to continue..."
read
