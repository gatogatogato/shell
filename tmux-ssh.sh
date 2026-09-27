#!/usr/bin/env bash
set -euo pipefail  # Enable strict error handling

# Configuration
readonly SESSION_NAME="gato"
readonly SSH_USER="gato"
readonly DOMAIN="lan"
readonly CONNECT_TIMEOUT=3
readonly SERVERS=(
    proxmox-n01
    proxmox-n02
    proxmox-n03
    debian-websrv
    debian-flickr
    debian-hercules
    debian-ansible
    debian-changedetection
    debian-glance
    debian-cloudflared
    debian-npm
    debian-uptimekuma
    debian-pihole
    debian-camsnaps
)

if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is not installed. Please install it first." >&2
    exit 1
fi

# Attach to the session, or switch to it when already running inside tmux
attach() {
    if [[ -n "${TMUX:-}" ]]; then
        exec tmux switch-client -t "${SESSION_NAME}"
    else
        exec tmux -2 attach-session -t "${SESSION_NAME}"
    fi
}

# Command run in each window: connect; a normal logout (Ctrl-D, exit) closes
# the window, only a connection error (ssh exit code 255) offers a reconnect
server_cmd() {
    local host
    host=$(printf '%q' "${SSH_USER}@${1}.${DOMAIN}")
    printf 'while :; do ssh -o ConnectTimeout=%s %s; [ $? -eq 255 ] || break; printf "\\nConnection to %s lost. Press Enter to reconnect, Ctrl-C to close. "; read -r _ || break; done' \
        "${CONNECT_TIMEOUT}" "${host}" "${host}"
}

# Try to attach to existing session first
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    attach
fi

echo "Creating new tmux session with connections to servers..."

for server in "${SERVERS[@]}"; do
    if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
        # A trailing colon appends the window at the next free index
        tmux new-window -d -t "${SESSION_NAME}:" -n "${server}" "$(server_cmd "${server}")"
    else
        tmux new-session -d -s "${SESSION_NAME}" -n "${server}" "$(server_cmd "${server}")"
    fi
done

# Select first window (works with any base-index) and attach to session
tmux select-window -t "${SESSION_NAME}:^"
attach
