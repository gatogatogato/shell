#!/bin/bash
set -euo pipefail  # Enable strict error handling

# Configuration
readonly SESSION_NAME="gato"
readonly PING_TIMEOUT="0.1"
readonly SERVERS=(
    proxmox-n01
    proxmox-n02
    proxmox-n03
    proxmox-backup-server
    debian-websrv
    debian-flickr
    debian-homer
    debian-hercules
    debian-ansible
    debian-changedetection
    debian-uptimekuma
    debian-pihole
    debian-test1
    debian-test2
)

# Check if mosh is installed
if ! command -v mosh &> /dev/null; then
    echo "Error: mosh is not installed. Please install it first."
    exit 1
fi

# Function to check if server is reachable
check_server() {
    local server="${1}"
    ping -c 1 -W "${PING_TIMEOUT}" "${server}.local" &> /dev/null
}

# Try to attach to existing session first
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    exec tmux -2 attach-session -t "${SESSION_NAME}"
fi

# Create new session
echo "Creating new tmux session with connections to servers..."

# Initialize first window
if check_server "${SERVERS[0]}"; then
    tmux new-session -s "${SESSION_NAME}" -n "${SERVERS[0]}" -d "mosh gato@${SERVERS[0]}.local || bash"
else
    echo "Warning: ${SERVERS[0]}.local is not reachable"
    tmux new-session -s "${SESSION_NAME}" -n "${SERVERS[0]}" -d "echo 'Server ${SERVERS[0]} is not reachable'; sleep 10; tmux kill-window"
fi

# Create remaining windows
for server in "${SERVERS[@]:1}"; do
    window_number=$(($(tmux list-windows -t "${SESSION_NAME}" | wc -l) + 1))
    
    if check_server "${server}"; then
        tmux new-window -t "${SESSION_NAME}:${window_number}" -n "${server}" "mosh gato@${server}.local || bash"
    else
        echo "Warning: ${server}.local is not reachable"
        tmux new-window -t "${SESSION_NAME}:${window_number}" -n "${server}" "echo 'Server ${server} is not reachable'; sleep 10"
    fi
done

# Select first window and attach to session
tmux select-window -t "${SESSION_NAME}:0"
exec tmux -2 attach-session -t "${SESSION_NAME}"
