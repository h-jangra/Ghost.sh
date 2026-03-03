#!/bin/bash

_ghost_history_file="$HOME/.bash_history"
_ghost_max_entries=10000
_ghost_last_char=""
_ghost_cache_line=""
_ghost_cache_suggestion=""

_ghost_load_history() {
    local count=0
    _ghost_history=()
    [[ -f "$_ghost_history_file" ]] || return
    mapfile -t -n "$_ghost_max_entries" _ghost_history < <(tac "$_ghost_history_file" 2>/dev/null | grep -v '^$')
}

_ghost_find_suggestion() {
    local prefix="$1"
    [[ -z "$prefix" ]] && return
    
    [[ "$prefix" == "$_ghost_cache_line" ]] && printf '%s' "$_ghost_cache_suggestion" && return
    
    local entry len_prefix="${#prefix}"
    for entry in "${_ghost_history[@]}"; do
        if [[ "$entry" == "$prefix"* ]] && (( ${#entry} > len_prefix )); then
            _ghost_cache_line="$prefix"
            _ghost_cache_suggestion="${entry:$len_prefix}"
            printf '%s' "$_ghost_cache_suggestion"
            return
        fi
    done
    
    _ghost_cache_line="$prefix"
    _ghost_cache_suggestion=""
}

_ghost_accept() {
    local suggestion="$(_ghost_find_suggestion "$READLINE_LINE")"
    [[ -n "$suggestion" ]] && READLINE_LINE="${READLINE_LINE}${suggestion}" && READLINE_POINT="${#READLINE_LINE}" && _ghost_cache_line="" && printf '\e7\r\e[K$ %s\e[K\e8' "$READLINE_LINE"
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

for char in "-" "_" "/" "." "," "@" "=" "+"; do
    bind -x "\"$char\": _ghost_last_char='$char' _ghost_widget"
done

echo "Ghost enabled - Right Arrow accepts suggestions"
