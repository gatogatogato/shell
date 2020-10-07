#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~pi/tk4-
export PATH=${PATH}:${installdir}/herc-tools/bin
#-----------------------------------------------------------------
echo "Build langtest for performance testing..."

cd ${installdir}
git clone "https://github.com/wfjm/mvs38j-langtest"
git clone "https://github.com/wfjm/herc-tools"

echo "Change job names..."
sed --in-place=.old -e 's=${JOB}=HERC01JX=g' ${installdir}/mvs38j-langtest/jcl/*.JESI
sed --in-place=.old -e 's=WFJM=GATO=g' ${installdir}/mvs38j-langtest/jcl/*.JESI
sed --in-place=.old -e 's=MSGCLASS:-A=MSGCLASS:-H=g' ${installdir}/mvs38j-langtest/jcl/*.JESI
echo "Build JCL..."
cd ${installdir}/mvs38j-langtest/jobs/
make



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
