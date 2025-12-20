#!/bin/bash

_ghost_history_file="$HOME/.bash_history"
_ghost_max_entries=10000
_ghost_last_char=""

_ghost_load_history() {
    local count=0
    _ghost_history=()
    [[ -f "$_ghost_history_file" ]] || return
    while IFS= read -r line && (( count < _ghost_max_entries )); do
        line="${line%%$'\n'*}"
        [[ -n "$line" ]] && _ghost_history["$count"]="$line" && ((count++))
    done < <(tac "$_ghost_history_file" 2>/dev/null)
}

_ghost_find_suggestion() {
    [[ -z "$1" ]] && return
    local entry
    for entry in "${_ghost_history[@]}"; do
        [[ "$entry" == "$1"* && "${#entry}" -gt "${#1}" ]] && printf '%s' "${entry:${#1}}" && return
    done
}

_ghost_accept() {
    local suggestion="$(_ghost_find_suggestion "$READLINE_LINE")"
    [[ -n "$suggestion" ]] && READLINE_LINE="${READLINE_LINE}${suggestion}" && READLINE_POINT="${#READLINE_LINE}"
}

_ghost_widget() {
    [[ -n "$_ghost_last_char" ]] && READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${_ghost_last_char}${READLINE_LINE:$READLINE_POINT}" && ((READLINE_POINT++)) && _ghost_last_char=""
    local suggestion="$(_ghost_find_suggestion "$READLINE_LINE")"
    printf '\e7\r\e[K$ %s' "$READLINE_LINE"
    [[ -n "$suggestion" ]] && printf '\e[90m%s\e[0m' "$suggestion"
    printf '\e8'
}

_ghost_backspace() {
    (( READLINE_POINT > 0 )) && READLINE_LINE="${READLINE_LINE:0:$((READLINE_POINT-1))}${READLINE_LINE:$READLINE_POINT}" && ((READLINE_POINT--))
    local suggestion="$(_ghost_find_suggestion "$READLINE_LINE")"
    printf '\e7\r\e[K$ %s' "$READLINE_LINE"
    [[ -n "$suggestion" ]] && printf '\e[90m%s\e[0m' "$suggestion"
    printf '\e8'
}

_ghost_load_history

bind -x '"\e[C": _ghost_accept'
bind -x '"\C-h": _ghost_backspace'
bind -x '"\C-?": _ghost_backspace'

for char in {a..z} {A..Z} {0..9}; do
    bind -x "\"$char\": _ghost_last_char='$char' _ghost_widget"
done

for char in " " "-" "_" "/" "." "," "@" "=" "+"; do
    bind -x "\"$char\": _ghost_last_char='$char' _ghost_widget"
done

echo "Ghost enabled - Right Arrow accepts suggestions"
