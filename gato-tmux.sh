#!/bin/zsh

tmux -2 attach-session -t gato
if [[ "${?}" -eq 1 ]]; then
        # tmux session is not active - we'll create one
        tmux new-session -s gato   -n "UPLOADER" -d 'cd  ~/Dropbox/UPLOADS/ && ./uploader-headless.rb; bash -i'
        tmux select-window -t gato:0
        tmux -2 attach-session -t gato
fi

