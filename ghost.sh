#!/usr/bin/env bash
# Ghost + Navigation replacement with compiled Zig binary frontend

_GHOST_BIN="${_GHOST_BIN:-ghost}"
if ! command -v "$_GHOST_BIN" >/dev/null 2>&1; then
    if [[ -x "$(dirname "${BASH_SOURCE[0]}")/ghost" ]]; then
        _GHOST_BIN="$(dirname "${BASH_SOURCE[0]}")/ghost"
    fi
fi

_ghost_readline_hook() {
    # If binary is not available or terminal not interactive, fall back to standard readline
    if ! command -v "$_GHOST_BIN" >/dev/null 2>&1 || [[ ! -t 0 || ! -t 1 || ! -r /dev/tty ]]; then
        return
    fi

    # Flush current session history to disk so Zig can access the latest commands
    history -a 2>/dev/null

    local prompt_expanded
    prompt_expanded="${PS1@P}"

    local hist_file="${HISTFILE:-$HOME/.bash_history}"
    local tmp_out
    tmp_out=$(mktemp /tmp/ghost_out.XXXXXX 2>/dev/null || echo "/tmp/ghost_out_$$")

    # Run Zig frontend with full TTY ownership
    "$_GHOST_BIN" --prompt "$prompt_expanded" --histfile "$hist_file" --output "$tmp_out" </dev/tty >/dev/tty 2>/dev/null
    local status=$?

    if (( status == 0 )) && [[ -f "$tmp_out" ]]; then
        local cmd
        cmd=$(<"$tmp_out")
        rm -f "$tmp_out" 2>/dev/null
        # Immediately write command into history and execute it in Bash
        if [[ -n "$cmd" ]]; then
            history -s "$cmd" 2>/dev/null
            eval "$cmd"
        fi
    elif (( status == 130 )); then
        rm -f "$tmp_out" 2>/dev/null
    else
        rm -f "$tmp_out" 2>/dev/null
    fi
}

if [[ "${PROMPT_COMMAND@a}" == *a* ]]; then
    _ghost_found=0
    for _ghost_cmd in "${PROMPT_COMMAND[@]}"; do
        [[ "$_ghost_cmd" == "_ghost_readline_hook" ]] && { _ghost_found=1; break; }
    done
    (( !_ghost_found )) && PROMPT_COMMAND+=(_ghost_readline_hook)
    unset _ghost_found _ghost_cmd
else
    [[ "${PROMPT_COMMAND:-}" != *"_ghost_readline_hook"* ]] && PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_ghost_readline_hook"
fi
