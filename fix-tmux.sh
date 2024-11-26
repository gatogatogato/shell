#!/usr/bin/env zsh
echo "Fix /etc/tmux.conf"
echo "New location is in /opt/homebrew/etc/tmux.conf"

outfile=/opt/homebrew/etc/tmux.conf

sudo echo "# remap prefix from 'C-b' to 'C-a'" > ${outfile}
sudo echo "unbind C-b" >> ${outfile}
sudo echo "set-option -g prefix C-a" >> ${outfile}
sudo echo "bind-key C-a send-prefix" >> ${outfile}

