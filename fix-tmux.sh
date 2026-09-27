#!/usr/bin/env bash
# Configure tmux on macOS (Homebrew):
#   - global config: prefix C-a instead of C-b
#   - ~/.tmux.conf:  Ctrl-a E sends a command to all panes
# Existing content of ~/.tmux.conf is kept; only the block between the
# markers below is replaced, so the script can be run repeatedly.
set -euo pipefail  # Enable strict error handling

readonly BEGIN_MARKER="# >>> fix-tmux.sh >>>"
readonly END_MARKER="# <<< fix-tmux.sh <<<"
readonly PRIVATE_CONF="${HOME}/.tmux.conf"

if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is not installed." >&2
    exit 1
fi
if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is not installed. Install it with 'brew install tmux'." >&2
    exit 1
fi

# /opt/homebrew on Apple Silicon, /usr/local on Intel
GLOBAL_CONF="$(brew --prefix)/etc/tmux.conf"
readonly GLOBAL_CONF

# Replace (or append) our marked block in a config file, keeping everything else
write_block() {
    local file="$1" block="$2" tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    chmod 644 "${tmp}"
    if [[ -f "${file}" ]]; then
        cp -p "${file}" "${file}.bak"
        awk -v b="${BEGIN_MARKER}" -v e="${END_MARKER}" '
            $0 == b { skip = 1; next }
            $0 == e { skip = 0; next }
            !skip
        ' "${file}" > "${tmp}"
    fi
    printf '%s\n%s\n%s\n' "${BEGIN_MARKER}" "${block}" "${END_MARKER}" >> "${tmp}"
    mv "${tmp}" "${file}"
}

echo "Writing global tmux config to ${GLOBAL_CONF}..."
mkdir -p "$(dirname "${GLOBAL_CONF}")"
write_block "${GLOBAL_CONF}" "$(cat <<'EOF'
# Remap prefix from 'C-b' to 'C-a'
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix
EOF
)"

echo "Writing private tmux config to ${PRIVATE_CONF}..."
write_block "${PRIVATE_CONF}" "$(cat <<'EOF'
# Press Ctrl-a E to send a command to all panes
bind E command-prompt -p "Command:" \
       "run \"tmux list-panes -a -F '##{session_name}:##{window_index}.##{pane_index}' \
              | xargs -I PANE tmux send-keys -t PANE '%1' Enter\""
EOF
)"

# Apply to a running tmux server right away
if tmux info &> /dev/null; then
    echo "Reloading running tmux server..."
    tmux source-file "${GLOBAL_CONF}"
    tmux source-file "${PRIVATE_CONF}"
fi

echo "Done. Backups (if any) are stored as *.bak next to the config files."
