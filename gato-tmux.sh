#!/bin/zsh

tmux -2 attach-session -t gato
if [[ $? -eq 1 ]]; then
        # tmux session is not active - we'll create one
        tmux new-session -s gato   -n "UPLOADER" -d 'cd  ~/Dropbox/UPLOADS/ && ./uploader-headless.rb; bash -i'
        tmux new-window -t gato:1 -n "MUTT" 'mutt; bash -i'
        tmux rename-window -t gato:1 "MUTT"
        #tmux new-window -t gato:3 -n LOGS 'cd ~ && tail -f commenter-logfile.txt'
        #tmux split-window -t gato:3 'sudo tail -f /var/log/fail2ban.log'
        #tmux split-window -t gato:3 'sudo tail -f /var/log/exim4/rejectlog'
        #tmux select-layout -t gato:3 even-vertical
        #tmux rename-window -t gato:3 "LOGS"
        tmux select-window -t gato:0
        tmux -2 attach-session -t gato
fi

