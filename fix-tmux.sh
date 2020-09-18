#!/usr/bin/env zsh
export DIVIDER="---------------------------------------------------------"
SECONDS=0
echo "Fix /etc/tmux.conf"
sudo cat "# remap prefix from 'C-b' to 'C-a'" > /etc/tmux.conf
sudo cat "unbind C-b" >> /etc/tmux.conf
sudo cat "set-option -g prefix C-a" >> /etc/tmux.conf
sudo cat "bind-key C-a send-prefix" >> /etc/tmux.conf
echo ${DIVIDER}
echo "Took ${SECONDS} seconds to fix tmux.conf"
echo "End of script."
echo ${DIVIDER}