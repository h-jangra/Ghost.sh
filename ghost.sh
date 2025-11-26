# ghostsh.sh

# Path to your Rust binary
GHOSTSH_BIN="${GHOSTSH_BIN:-ghostsh}"

# Show ghost hint after current line
_ghostsh_show_hint() {
    local line="$READLINE_LINE"
    local hint
    hint="$("$GHOSTSH_BIN" --hint "$line" 2>/dev/null)" || hint=""

    # Save cursor position relative to line end
    local cols=${#READLINE_LINE}
    local pos="$READLINE_POINT"

    # Carriage return, reprint prompt+line, then grey hint, then restore cursor
    # NOTE: This is *approximate*; proper PS1 width handling is what makes ble.sh huge.
    local esc_reset=$'\e[0m'
    local esc_grey=$'\e[90m'

    # Repaint line + hint
    echo -ne "\r"
    # Let readline redraw the prompt + line
    # Trick: force a redisplay
    bind '"\er": redraw-current-line'
    # Now print hint after line
    echo -ne "$esc_grey$hint$esc_reset"

    # Move cursor back to original logical position
    local move_back=$(( cols + ${#hint} - pos ))
    if (( move_back > 0 )); then
        printf '\e[%dD' "$move_back"
    fi
}

# Accept the current hint by actually completing READLINE_LINE
_ghostsh_accept_hint() {
    local line="$READLINE_LINE"
    local hint
    hint="$("$GHOSTSH_BIN" --hint "$line" 2>/dev/null)" || hint=""

    if [[ -n "$hint" ]]; then
        READLINE_LINE+="$hint"
        READLINE_POINT=${#READLINE_LINE}
    fi
}

# Hook: after each keypress, update the hint display
_ghostsh_post_key() {
    # Just refresh hint
    _ghostsh_show_hint
}

# Initialization: bind keys
ghostsh_ble_init() {
    # Bind Right Arrow to accept the ghost hint
    bind -x '"\e[C": _ghostsh_accept_hint'

    # Bind a key to manually refresh the hint (e.g. Ctrl-Space)
    bind -x '"\C-@": _ghostsh_post_key'

    # OPTIONAL: you *could* remap printable keys to call _ghostsh_post_key
    # after self-insert, but that’s where it starts to become a mini-ble.sh.
}

ghostsh_ble_init

