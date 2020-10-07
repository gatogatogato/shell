#!/bin/zsh
#-----------------------------------------------------------------
export installdir=~/
export PATH=${PATH}:${installdir}/mvs38j-langtest/herc-tools/bin
#-----------------------------------------------------------------
echo "Build langtest for performance testing..."

cd ${installdir}

git clone "https://github.com/wfjm/mvs38j-langtest"
cd ${installdir}/mvs38j-langtest
git clone "https://github.com/wfjm/herc-tools"
git clone "https://github.com/wfjm/mvs38j-sios"
rm -rf sios
mv mvs38j-sios sios

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
