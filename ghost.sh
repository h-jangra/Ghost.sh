#!/usr/bin/env bash
# Ghost completions — dynamic suggestions as you type

set +m 2>/dev/null || true
bind 'set bind-tty-special-chars off' 2>/dev/null || true

GHOST_COLOR="${GHOST_COLOR:-38;5;244}"
_ghost_history=()
_ghost_suggestion=""
_ghost_matched_cmd=""
_ghost_last_rendered=""
_ghost_last_len=0
_NAV_MENU_ACTIVE="${_NAV_MENU_ACTIVE:-0}"

_ghost_init() {
    _ghost_history=()
    local -a raw=()
    # Read history with empty HISTTIMEFORMAT to prevent timestamp mangling
    mapfile -t raw < <(
        HISTTIMEFORMAT= history 2>/dev/null | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' | \
        awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) if(!seen[a[i]]++ && a[i]!="") print a[i]}'
    )
    if (( ${#raw[@]} == 0 )); then
        if [[ -n "${HISTFILE:-}" && -f "$HISTFILE" ]]; then
            mapfile -t raw < <(
                awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) if(!seen[a[i]]++ && a[i]!="" && a[i]!~/^#/) print a[i]}' "$HISTFILE" 2>/dev/null
            )
        elif [[ -f "$HOME/.bash_history" ]]; then
            mapfile -t raw < <(
                awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) if(!seen[a[i]]++ && a[i]!="" && a[i]!~/^#/) print a[i]}' "$HOME/.bash_history" 2>/dev/null
            )
        fi
    fi
    _ghost_history=("${raw[@]}")
}

_ghost_erase() {
    if [[ -n "$_ghost_last_rendered" ]]; then
        local p="${PS1@P}"
        p="${p##*$'\n'}"
        p="${p//$'\001'/}"
        p="${p//$'\002'/}"
        printf '%s%s\e[K\r' "$p" "$READLINE_LINE" >&2
        _ghost_last_rendered=""
    fi
}

_ghost_hide() {
    _ghost_erase
    _ghost_suggestion=""
    _ghost_matched_cmd=""
    _ghost_last_rendered=""
    _ghost_last_len=0
}

_ghost_clear() {
    _ghost_hide
}

_ghost_get_suggestion() {
    local input="$1"
    _ghost_suggestion=""
    [[ -z "$input" ]] && { _ghost_matched_cmd=""; return; }

    # Fast path: check if currently matched command still matches the input prefix
    if [[ -n "$_ghost_matched_cmd" && "$_ghost_matched_cmd" == "$input"* && "$_ghost_matched_cmd" != "$input" ]]; then
        _ghost_suggestion="${_ghost_matched_cmd#"$input"}"
        return
    fi

    local line
    for line in "${_ghost_history[@]}"; do
        if [[ "$line" == "$input"* && "$line" != "$input" ]]; then
            _ghost_matched_cmd="$line"
            _ghost_suggestion="${line#"$input"}"
            return
        fi
    done
    _ghost_matched_cmd=""
}

_ghost_render() {
    if (( ${_NAV_MENU_ACTIVE:-0} )); then
        _ghost_erase
        return
    fi

    if (( READLINE_POINT == ${#READLINE_LINE} )) && [[ -n "$READLINE_LINE" ]]; then
        _ghost_get_suggestion "$READLINE_LINE"
    else
        _ghost_suggestion=""
    fi

    if [[ "$_ghost_suggestion" == "$_ghost_last_rendered" ]]; then
        return
    fi

    local p="${PS1@P}"
    p="${p##*$'\n'}"
    p="${p//$'\001'/}"
    p="${p//$'\002'/}"

    if [[ -n "$_ghost_suggestion" ]]; then
        _ghost_last_rendered="$_ghost_suggestion"
        printf '%s%s\e[%sm%s\e[0m\e[K\r' "$p" "$READLINE_LINE" "$GHOST_COLOR" "$_ghost_suggestion" >&2
    else
        _ghost_last_rendered=""
        printf '%s%s\e[K\r' "$p" "$READLINE_LINE" >&2
    fi
}

_ghost_refresh() {
    history -a 2>/dev/null
    _ghost_init
    _ghost_hide
}

_ghost_insert_char() {
    local char
    printf -v char '%b' "$(printf '\\%03o' "$1")"
    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$char${READLINE_LINE:$READLINE_POINT}"
    READLINE_POINT=$(( READLINE_POINT + ${#char} ))
    _ghost_render
}

_ghost_accept() {
    if (( READLINE_POINT < ${#READLINE_LINE} )); then
        (( READLINE_POINT++ ))
        _ghost_render
    elif [[ -n "$_ghost_suggestion" ]]; then
        local sug="$_ghost_suggestion"
        _ghost_last_rendered=""
        READLINE_LINE+="$sug"
        READLINE_POINT=${#READLINE_LINE}
        _ghost_suggestion=""
        _ghost_matched_cmd=""
        _ghost_render
    fi
}

_ghost_accept_word() {
    if (( READLINE_POINT < ${#READLINE_LINE} )); then
        local rest="${READLINE_LINE:$READLINE_POINT}"
        [[ "$rest" =~ ^([[:alnum:]_]+|[^[:alnum:]_[:space:]]+|[[:space:]]+) ]] && (( READLINE_POINT += ${#BASH_REMATCH[0]} ))
        _ghost_render
    elif [[ -n "$_ghost_suggestion" ]]; then
        local word="${_ghost_suggestion%% *}"
        [[ "$_ghost_suggestion" == *' '* ]] && word+=' '
        _ghost_last_rendered=""
        READLINE_LINE+="$word"
        READLINE_POINT=${#READLINE_LINE}
        _ghost_suggestion="${_ghost_suggestion#"$word"}"
        _ghost_render
    fi
}

_ghost_backspace() {
    if (( READLINE_POINT > 0 )); then
        READLINE_LINE="${READLINE_LINE:0:$((READLINE_POINT - 1))}${READLINE_LINE:$READLINE_POINT}"
        (( READLINE_POINT-- ))
    fi
    _ghost_render
}

_ghost_delete() {
    if (( READLINE_POINT < ${#READLINE_LINE} )); then
        READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${READLINE_LINE:$((READLINE_POINT + 1))}"
    fi
    _ghost_render
}

_ghost_backward_kill_word() {
    if (( READLINE_POINT > 0 )); then
        local pre="${READLINE_LINE:0:$READLINE_POINT}"
        local post="${READLINE_LINE:$READLINE_POINT}"
        local stripped="${pre%"${pre##*[![:space:]]}"}"
        stripped="${stripped%"${stripped##*[^[:alnum:]_]}"}"
        [[ "$stripped" == "$pre" ]] && stripped="${pre%[[:space:]]*}"
        READLINE_LINE="${stripped}${post}"
        READLINE_POINT=${#stripped}
    fi
    _ghost_render
}

_ghost_kill_line() {
    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}"
    _ghost_render
}

_ghost_clear_line() {
    READLINE_LINE=""
    READLINE_POINT=0
    _ghost_render
}

_ghost_cursor_left() {
    (( READLINE_POINT > 0 )) && (( READLINE_POINT-- ))
    _ghost_render
}

_ghost_cursor_home() {
    READLINE_POINT=0
    _ghost_render
}

_ghost_cursor_end() {
    if (( READLINE_POINT < ${#READLINE_LINE} )); then
        READLINE_POINT=${#READLINE_LINE}
        _ghost_render
    elif [[ -n "$_ghost_suggestion" ]]; then
        local sug="$_ghost_suggestion"
        _ghost_last_rendered=""
        READLINE_LINE+="$sug"
        READLINE_POINT=${#READLINE_LINE}
        _ghost_suggestion=""
        _ghost_matched_cmd=""
        _ghost_render
    fi
}

_ghost_enter_clear() {
    _ghost_hide
}

_ghost_init

for ((i=32; i<=126; i++)); do
    case "$i" in
        34) bind -x '"\"": _ghost_insert_char 34' ;;
        92) bind -x '"\\": _ghost_insert_char 92' ;;
        *)
            printf -v c '%b' "$(printf '\\%03o' "$i")"
            bind -x "\"$c\": _ghost_insert_char $i"
            ;;
    esac
done

bind -x '"\e[C":    _ghost_accept'
bind -x '"\eOC":    _ghost_accept'
bind -x '"\e[D":    _ghost_cursor_left'
bind -x '"\eOD":    _ghost_cursor_left'
bind -x '"\ef":     _ghost_accept_word'
bind -x '"\C-f":    _ghost_accept_word'
bind -x '"\e[1;3C": _ghost_accept_word'
bind -x '"\e\e[C":  _ghost_accept_word'
bind -x '"\C-?":    _ghost_backspace'
bind -x '"\C-h":    _ghost_backspace'
bind -x '"\e[3~":   _ghost_delete'
bind -x '"\C-w":    _ghost_backward_kill_word'
bind -x '"\C-u":    _ghost_clear_line'
bind -x '"\C-k":    _ghost_kill_line'
bind -x '"\C-a":    _ghost_cursor_home'
bind -x '"\e[H":    _ghost_cursor_home'
bind -x '"\eOH":    _ghost_cursor_home'
bind -x '"\e[1~":   _ghost_cursor_home'
bind -x '"\C-e":    _ghost_cursor_end'
bind -x '"\e[F":    _ghost_cursor_end'
bind -x '"\eOF":    _ghost_cursor_end'
bind -x '"\e[4~":   _ghost_cursor_end'

bind -x '"\e_ghost_enter": _ghost_enter_clear'
bind '"\C-m": "\e_ghost_enter\C-j"'
bind '"\C-j": accept-line'

if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" =~ "declare -a" ]]; then
    _ghost_found=0
    for _ghost_cmd in "${PROMPT_COMMAND[@]}"; do
        [[ "$_ghost_cmd" == "_ghost_refresh" ]] && { _ghost_found=1; break; }
    done
    (( !_ghost_found )) && PROMPT_COMMAND+=(_ghost_refresh)
    unset _ghost_found _ghost_cmd
else
    [[ "${PROMPT_COMMAND:-}" != *"_ghost_refresh"* ]] && PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_ghost_refresh"
fi
