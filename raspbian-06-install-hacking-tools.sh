#!/bin/zsh
echo "Install hacking tools"

sudo apt-get install python3

mkdir -m 700 ~/hAxx0r

# Install sherlock
cd ~/hAxx0r
git clone https://github.com/sherlock-project/sherlock.git
cd sherlock
python3 -m pip install -r requirements.txt

# Install phoneinfoga
cd ~/hAxx0r
mkdir -m 700 phoneinfoga
cd phoneinfoga && \
curl -sSL https://raw.githubusercontent.com/sundowndev/PhoneInfoga/master/support/scripts/install | bash
./phoneinfoga version
