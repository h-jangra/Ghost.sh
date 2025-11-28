#!/bin/bash

_ghost_bin="./target/release/ghost"

if [[ ! -x "$_ghost_bin" ]]; then
    echo "Error: Ghost binary not found at $_ghost_bin" >&2
    echo "Please build it with: cargo build --release" >&2
    return 1
fi

_ghost_accept() {
    local output
    output=$("$_ghost_bin" "accept-ghost" 2>/dev/null)
    if [[ -n "$output" ]]; then
        READLINE_LINE="$output"
        READLINE_POINT=${#READLINE_LINE}
    fi
}

_ghost_widget() {
    local line="$READLINE_LINE"
    local point="$READLINE_POINT"

    # Save cursor position
    printf '\e7'

    # Move to beginning and clear to end of screen
    printf '\r\e[0J'

    # Redraw just the input line with suggestion
    printf '$ %s' "$line"

    local suggestion
    suggestion=$("$_ghost_bin" "ghost-widget" 2>&1)

    if [[ -n "$suggestion" ]]; then
        printf '\x1b[90m%s\x1b[0m' "$suggestion"
    fi

    # Restore cursor position
    printf '\e8'
}

bind -x '"\C-g": _ghost_widget'
bind -x '"\t": _ghost_accept'

echo "Ghost suggestions enabled!"
echo "Press Ctrl+G to show suggestions, Tab to accept"
