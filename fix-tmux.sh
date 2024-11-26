#!/usr/bin/env zsh
echo "Fix /etc/tmux.conf"
echo "New location is in /opt/homebrew/etc/tmux.conf"

outfile=/opt/homebrew/etc/tmux.conf
private_outfile=~/.tmux.conf

sudo echo "# remap prefix from 'C-b' to 'C-a'" > ${outfile}
sudo echo "unbind C-b" >> ${outfile}
sudo echo "set-option -g prefix C-a" >> ${outfile}
sudo echo "bind-key C-a send-prefix" >> ${outfile}

echo "# Press Ctrl-a Ctrl-x to send a command to all panes"  >  ${private_outfile}
echo "# Press Ctrl-a Mac-x to disable this mode"             >> ${private_outfile}
echo "bind -n C-x setw synchronize-panes on"                 >> ${private_outfile}
echo "bind -n M-x setw synchronize-panes off"                >> ${private_outfile}
