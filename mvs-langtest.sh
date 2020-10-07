#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~pi/tk4-
export PATH=${PATH}:${installdir}/herc-tools/bin
#-----------------------------------------------------------------
echo "Build langtest for performance testing..."

cd ${installdir}
git clone "https://github.com/wfjm/mvs38j-langtest"
git clone "https://github.com/wfjm/herc-tools"

clear
echo "--------------------------------------------"
echo " Next adapt the JCL defaults manually first "
echo "--------------------------------------------"
echo ""
echo "Press enter to continue..."
read
cd ${installdir}/mvs38j-langtest/jcl

echo "Change job names..."
sed --in-place=.old -e 's=${JOB}=HERC01JX=g' ${installdir}/*.JESI
echo "Build JCL..."
make

clear
echo "--------------------------------------------"
echo " Remember to export PATH to                 "
echo " export PATH=${PATH}:${installdir}/herc-tools/bin"
echo "--------------------------------------------"
echo " Submit JCL with                            "
echo "   hercjis *asm*.jcl                        "
echo "--------------------------------------------"
echo ""
echo "Press enter to continue..."
read
