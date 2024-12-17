#!/bin/zsh
tmux -2 attach-session -t gato
if [[ "${?}" -eq 1 ]]; then
        # tmux session is not active - we'll create one
        tmux new-session -s gato -n "HERCULES" -d 'cd ~/tk4-/ ; ./mvs '
        tmux rename-window -t gato:1 "HERCULES"
        tmux new-window -t gato:1 -n "HTOP" 'sudo htop'
        tmux rename-window -t gato:1 "HTOP"
        tmux new-window -t gato:2 -n "TEMP" 'watch --interval 20 "/opt/vc/bin/vcgencmd measure_temp"'
        tmux rename-window -t gato:2 "TEMP"
        tmux select-window -t gato:0
        tmux -2 attach-session -t gato
fi