#!/usr/bin/env bash

#---------------------------------------------------------------------------------------------------
# Install XCode command line utilities
echo "Install XCode command line utilities first..."
xcode-select --install

#---------------------------------------------------------------------------------------------------
# Install Homebrew
echo "Install Homebrew first..."
echo "( if this fails please check https://docs.brew.sh/Installation )"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew update

#---------------------------------------------------------------------------------------------------
echo "Press enter to continue or CTRL+C to cancel..."
read

#---------------------------------------------------------------------------------------------------
# Install basic stuff from brew 
brew install imagemagick
brew install youtube-dl
brew install exiftool
brew install nmap

#---------------------------------------------------------------------------------------------------
# Install desktop apps from brew
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