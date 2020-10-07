#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~pi/tk4-
export PATH=${PATH}:${installdir}/herc-tools/bin
#-----------------------------------------------------------------
echo "Build langtest for performance testing..."

cd ${installdir}
rm -rf mvs38j-langtest
rm -rf herc-tools

git clone "https://github.com/wfjm/mvs38j-langtest"
cd mvs38j-langtest
git clone "https://github.com/wfjm/herc-tools"
git clone "https://github.com/wfjm/mvs38j-sios"

echo "Change job names..."
sed --in-place=.old -e 's=${JOB}=HERC01JX=g' ${installdir}/mvs38j-langtest/jcl/*.JESI
sed --in-place=.old -e 's=WFJM=GATO=g' ${installdir}/mvs38j-langtest/jcl/*.JESI
sed --in-place=.old -e 's=MSGCLASS:-A=MSGCLASS:-H=g' ${installdir}/mvs38j-langtest/jcl/*.JESI
echo "Build JCL..."
cd ${installdir}/mvs38j-langtest/jobs/
make

echo "--------------------------------------------"
echo " Run tests JCL e.g. with                    "
echo "   ${installdir}/herc-tools/bin/hercjis ${installdir}/mvs38j-langtest/jobs/*asm*.jcl  "
echo "--------------------------------------------"
