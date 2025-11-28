#!/bin/bash

_ghost_history_file="$HOME/.bash_history"
_ghost_max_entries=10000
_ghost_last_char=""

_ghost_load_history() {
    local count=0
    _ghost_history=()
    if [[ -f "$_ghost_history_file" ]]; then
        while IFS= read -r line && (( count < _ghost_max_entries )); do
            line="${line%%$'\n'*}"
            if [[ -n "$line" ]]; then
                _ghost_history["$count"]="$line"
                ((count++))
            fi
        done < <(tac "$_ghost_history_file" 2>/dev/null)
    fi
}

_ghost_find_suggestion() {
    local prefix="$1"
    if [[ -z "$prefix" ]]; then
        return
    fi
    local entry
    for entry in "${_ghost_history[@]}"; do
        if [[ "$entry" == "$prefix"* && "${#entry}" -gt "${#prefix}" ]]; then
            printf '%s' "${entry:${#prefix}}"
            return
        fi
    done
}

_ghost_accept() {
    local line="$READLINE_LINE"
    local suggestion="$(_ghost_find_suggestion "$line")"
    if [[ -n "$suggestion" ]]; then
        READLINE_LINE="${line}${suggestion}"
        READLINE_POINT="${#READLINE_LINE}"
    fi
}

_ghost_widget() {
    # Insert the character first if we have one
    if [[ -n "$_ghost_last_char" ]]; then
        READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${_ghost_last_char}${READLINE_LINE:$READLINE_POINT}"
        ((READLINE_POINT++))
        _ghost_last_char=""
    fi

    local line="$READLINE_LINE"
    local suggestion="$(_ghost_find_suggestion "$line")"

    # Save cursor position
    printf '\e7'
    # Move to beginning and clear to end of screen
    printf '\r\e[0J'
    # Redraw just the input line with suggestion
    printf '$ %s' "$line"
    if [[ -n "$suggestion" ]]; then
        printf '\e[90m%s\e[0m' "$suggestion"
    fi
    # Restore cursor position
    printf '\e8'
}

_ghost_handle_backspace() {
    if (( READLINE_POINT > 0 )); then
        READLINE_LINE="${READLINE_LINE:0:$((READLINE_POINT-1))}${READLINE_LINE:$READLINE_POINT}"
        ((READLINE_POINT--))
    fi

    # Redraw with updated suggestion
    local line="$READLINE_LINE"
    local suggestion="$(_ghost_find_suggestion "$line")"

    printf '\e7'
    printf '\r\e[0J'
    printf '$ %s' "$line"
    if [[ -n "$suggestion" ]]; then
        printf '\e[90m%s\e[0m' "$suggestion"
    fi
    printf '\e8'
}

_ghost_load_history

# Bind Tab to accept suggestion
bind -x '"\t": _ghost_accept'

# Bind backspace
bind -x '"\C-h": _ghost_handle_backspace'
bind -x '"\C-?": _ghost_handle_backspace'

# Bind letters
for char in {a..z} {A..Z}; do
    bind -x "\"$char\": _ghost_last_char='$char' _ghost_widget"
done

# Bind numbers
for num in {0..9}; do
    bind -x "\"$num\": _ghost_last_char='$num' _ghost_widget"
done

# Bind space
bind -x '" ": _ghost_last_char=" " _ghost_widget'

# Bind common special characters
bind -x '"-": _ghost_last_char="-" _ghost_widget'
bind -x '"_": _ghost_last_char="_" _ghost_widget'
bind -x '"/": _ghost_last_char="/" _ghost_widget'
bind -x '".": _ghost_last_char="." _ghost_widget'
bind -x '",": _ghost_last_char="," _ghost_widget'
bind -x '"@": _ghost_last_char="@" _ghost_widget'
bind -x '"=": _ghost_last_char="=" _ghost_widget'
bind -x '"+": _ghost_last_char="+" _ghost_widget'

echo "Ghost suggestions enabled!"
echo "Suggestions appear automatically as you type"
echo "Press Tab to accept the suggestion"
