#!/usr/bin/env zsh
echo "Fix /etc/tmux.conf"
sudo cat "# remap prefix from 'C-b' to 'C-a'" > /etc/tmux.conf
sudo cat "unbind C-b" >> /etc/tmux.conf
sudo cat "set-option -g prefix C-a" >> /etc/tmux.conf
sudo cat "bind-key C-a send-prefix" >> /etc/tmux.conf
