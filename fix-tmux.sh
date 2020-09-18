#!/usr/bin/env zsh
echo "Fix /etc/tmux.conf"
sudo echo "# remap prefix from 'C-b' to 'C-a'" > /etc/tmux.conf
sudo echo "unbind C-b" >> /etc/tmux.conf
sudo echo "set-option -g prefix C-a" >> /etc/tmux.conf
sudo echo "bind-key C-a send-prefix" >> /etc/tmux.conf
