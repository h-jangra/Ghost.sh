#!/usr/bin/env bash

_ghost_history_file="$HOME/.bash_history"
_ghost_max_entries=10000
_ghost_last_render=""
_ghost_suggestion=""

declare -A _ghost_index

_ghost_load_history() {
    local line count=0
    declare -A seen

    mapfile -t lines < <(tail -n "$_ghost_max_entries" "$_ghost_history_file" 2>/dev/null)

    for ((i=${#lines[@]}-1; i>=0; i--)); do
        line="${lines[i]}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || -n "${seen[$line]+_}" ]] && continue
        seen["$line"]=1
        _ghost_index["${line:0:1}"]+="${line}"$'\n'
        (( ++count >= _ghost_max_entries )) && break
    done
}

_ghost_find() {
    local prefix="$1"
    
    _ghost_suggestion=""

    [[ -z "$prefix" ]] && return
    
    local bucket=${prefix:0:1}
    local len=${#prefix}
    
    local entry
    while IFS= read -r entry; do
        [[ "$entry" == "$prefix"* && ${#entry} -gt len ]] && {
            _ghost_suggestion="${entry:$len}"
            break
        }
    done <<< "${_ghost_index[$bucket]}"
}

_ghost_render() {
    [[ $READLINE_POINT -ne ${#READLINE_LINE} ]] && return

    local prefix="${READLINE_LINE:0:$READLINE_POINT}"
    _ghost_find "$prefix"

    local state="$READLINE_LINE|$_ghost_suggestion"

    if [[ "${_ghost_last_render%%|*}" != "$READLINE_LINE" ]]; then
        _ghost_last_render=""
    fi

    [[ "$state" == "$_ghost_last_render" ]] && return
    _ghost_last_render="$state"

    local p="${PS1@P}"
    p="${p##*$'\n'}"

    printf '\e[s\r\e[K%s%s' "$p" "$READLINE_LINE"

    if [[ -n "$_ghost_suggestion" ]]; then
        local first="${_ghost_suggestion:0:1}"
        local rest="${_ghost_suggestion:1}"
        printf '\e[1;38;5;250m%s\e[0m\e[38;5;245m%s\e[0m' "$first" "$rest"
    fi

    printf '\e[u'
}

_ghost_insert() {
    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${_ghost_key}${READLINE_LINE:$READLINE_POINT}"
    ((READLINE_POINT++))
    _ghost_last_render=""
    _ghost_render
}

_ghost_accept() {
    [[ -z "$_ghost_suggestion" ]] && return

    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${_ghost_suggestion}${READLINE_LINE:$READLINE_POINT}"
    ((READLINE_POINT+=${#_ghost_suggestion}))

    _ghost_last_render=""
    _ghost_render
}

_ghost_backspace() {
    (( READLINE_POINT == 0 )) && return
    READLINE_LINE="${READLINE_LINE:0:$((READLINE_POINT-1))}${READLINE_LINE:$READLINE_POINT}"
    ((READLINE_POINT--))
    _ghost_last_render=""
    _ghost_render
}

_ghost_bind_char() {
    local key="$1"
    bind -x "\"$key\": _ghost_key=$(printf '%q' "$key"); _ghost_insert"
}

_ghost_load_history

bind -x '"\e[C": _ghost_accept'
bind -x '"\C-h": _ghost_backspace'
bind -x '"\C-?": _ghost_backspace'

for c in {a..z} {A..Z} {0..9} \
         ' ' '-' '_' '/' '.' ',' '@' '=' '+' \
         '>' '<' '|' '&' ':' ';' '*' '?' '!' '%' \
         '#' '~' '^' '(' ')' '[' ']' '{' '}'; do
    _ghost_bind_char "$c"
done

echo "Ghost enabled - Right Arrow accepts suggestions"
