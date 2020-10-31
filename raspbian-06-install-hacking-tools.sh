#!/bin/zsh
echo "Install hacking tools"
mkdir -m 700 ~/hAxx0r

sudo apt-get install python3 python3-pip libxml2-dev libxslt-dev build-essential libssl-dev libffi-dev python-dev

# Install sherlock
cd ~/hAxx0r
rm -rf sherlock
git clone https://github.com/sherlock-project/sherlock.git
cd sherlock
python3 -m pip install -r requirements.txt
python3 sherlock gato-gato-gato
