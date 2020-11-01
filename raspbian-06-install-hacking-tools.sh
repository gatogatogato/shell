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
echo "Run with 'python3 sherlock gato-gato-gato'"

#Install Harvester
cd ~/hAxx0r
rm -rf theHarvester
git clone https://github.com/laramies/theHarvester 
cd theHarvester
python3 -m pip install -r requirements/base.txt
python3 theHarvester.py -h
echo "Run with 'python3 theHarvester.py -h'"