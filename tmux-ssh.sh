#!/bin/bash
serverNames="proxmox-n01 proxmox-n02 proxmox-backup-server debian-websrv debian-flickr debian-homer debian-ansible debian-uptimekuma debian-pihole debian-test debian-test1"
counter=0
serverCount=$(echo "${serverNames}" | wc -w | xargs)

# echo "serverCount is ${serverCount}"

tmux -2 attach-session -t gato
if [[ $? -eq 1 ]]; then
        # tmux session is not active - we'll create one 
        for server in ${serverNames}
        do
                counter=$((counter + 1))
                # echo "Counter is ${counter}, server is ${server}"

                if [[ ${counter} -eq 1 ]]; then      
                        tmux new-session -s gato -n "${server}" -d "mosh gato@${server}.local"
                        tmux rename-window -t gato:1 "${server}"
                else
                        tmux new-window -t gato:${counter} -n "${server}" "mosh gato@${server}.local"
                        tmux rename-window -t gato:${counter} "${server}"
                fi
        done
fi
tmux select-window -t gato:0
tmux -2 attach-session -t gato
