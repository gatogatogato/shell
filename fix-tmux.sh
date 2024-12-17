#!/usr/bin/env zsh
echo "Fix /etc/tmux.conf"
echo "New location is in /opt/homebrew/etc/tmux.conf"

outfile=/opt/homebrew/etc/tmux.conf
private_outfile=~/.tmux.conf

sudo echo "# remap prefix from 'C-b' to 'C-a'" > "${outfile}"
sudo echo "unbind C-b" >> "${outfile}"
sudo echo "set-option -g prefix C-a" >> "${outfile}"
sudo echo "bind-key C-a send-prefix" >> "${outfile}"

IFS='' read -r -d '' outcommand <<"EOF"
bind E command-prompt -p "Command:" \
       "run \"tmux list-panes -a -F '##{session_name}:##{window_index}.##{pane_index}' \
              | xargs -I PANE tmux send-keys -t PANE '%1' Enter\""
EOF

echo "# Press Ctrl-a E to send a command to all panes"  >  "${private_outfile}"
echo "${outcommand}"                                      >> "${private_outfile}"

