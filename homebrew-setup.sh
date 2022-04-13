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
brew install "bash-completion"
brew install "exiftool"
brew install "ffmpeg"
brew install "htop"
brew install "imagemagick"
brew install "micro"
brew install "mosh"
brew install "netcat"
brew install "nmap"
brew install "qemu"
brew install "topgrade"
brew install "watch"
brew install "wget"
brew install "yt-dlp"
brew install "zsh-completions"

#---------------------------------------------------------------------------------------------------
echo "Install desktop apps from brew ..."
brew install tor-browser
brew install mactracker
brew install --cask "1Password"
brew install --cask "appcleaner"
brew install --cask "arq"
brew install --cask "catch"
brew install --cask "coconutbattery"
brew install --cask "dropbox"
brew install --cask "Firefox"
brew install --cask "github"
brew install --cask "handbrake"
brew install --cask "signal"
brew install --cask "sublime-text"
brew install --cask "the-unarchiver"
brew install --cask "transmission"
brew install --cask "vlc"

#---------------------------------------------------------------------------------------------------
echo "End of script."
exit