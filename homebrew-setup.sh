#!/usr/bin/env bash

#---------------------------------------------------------------------------------------------------
echo "Install XCode command line utilities first..."
xcode-select --install

#---------------------------------------------------------------------------------------------------
echo "Install Homebrew core..."
echo "( if this fails please check https://docs.brew.sh/Installation )"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew update

#---------------------------------------------------------------------------------------------------
echo "Press enter to continue or CTRL+C to cancel..."
read

#---------------------------------------------------------------------------------------------------
echo "Install basic stuff from brew ..."
brew install imagemagick
brew install youtube-dl
brew install exiftool
brew install nmap
brew install ffmpeg
brew install mosh
brew install topgrade

#---------------------------------------------------------------------------------------------------
echo "Install desktop apps from brew ..."
brew install tor-browser
brew install mactracker
brew install --cask catch
brew install --cask github
brew install --cask the-unarchiver
brew install --cask appcleaner
brew install --cask signal
brew install --cask handbrake
brew install --cask vlc
brew install --cask transmission

#---------------------------------------------------------------------------------------------------
echo "End of script."
exit