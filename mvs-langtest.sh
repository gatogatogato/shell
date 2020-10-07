#!/bin/zsh
#-----------------------------------------------------------------
export installdir="~/tk4-"
#-----------------------------------------------------------------
echo "Build langtest for performance testing..."
cd ${installdir}
git clone "https://github.com/wfjm/mvs38j-langtest"
mv mvs38j-langtest mvs38jlang