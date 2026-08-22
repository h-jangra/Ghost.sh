#!/usr/bin/env bash
# Ghost completions — dynamic suggestions as you type

set +m 2>/dev/null || true
bind 'set bind-tty-special-chars off' 2>/dev/null || true
stty intr undef 2>/dev/null || true

GHOST_COLOR="${GHOST_COLOR:-38;5;244}"
_ghost_history=()
_ghost_suggestion=""
_ghost_matched_cmd=""
_ghost_last_rendered=""
_ghost_last_no_match=""
_ghost_last_histcmd=0
_NAV_MENU_ACTIVE="${_NAV_MENU_ACTIVE:-0}"

# Precompute ASCII character table to avoid subshells in insert_char
_ghost_chars=()
for ((i=32; i<=126; i++)); do
    printf -v _ghost_oct '%03o' "$i"
    printf -v "_ghost_chars[$i]" '%b' "\\$_ghost_oct"
done
unset _ghost_oct

_ghost_init() {
    _ghost_history=()
    local -a raw=()
    # Read history with empty HISTTIMEFORMAT to prevent timestamp mangling
    mapfile -t raw < <(
        HISTTIMEFORMAT= history 2>/dev/null | \
        awk '{sub(/^[[:space:]]*[0-9]+[[:space:]]*/, ""); a[NR]=$0} END{c=0; for(i=NR;i>=1;i--) if(!seen[a[i]]++ && a[i]!="") {print a[i]; if(++c>=5000) break}}'
    )
    if (( ${#raw[@]} == 0 )); then
        if [[ -n "${HISTFILE:-}" && -f "$HISTFILE" ]]; then
            mapfile -t raw < <(
                awk '{a[NR]=$0} END{c=0; for(i=NR;i>=1;i--) if(!seen[a[i]]++ && a[i]!="" && a[i]!~/^#[0-9]*$/) {print a[i]; if(++c>=5000) break}}' "$HISTFILE" 2>/dev/null
            )
        elif [[ -f "$HOME/.bash_history" ]]; then
            mapfile -t raw < <(
                awk '{a[NR]=$0} END{c=0; for(i=NR;i>=1;i--) if(!seen[a[i]]++ && a[i]!="" && a[i]!~/^#[0-9]*$/) {print a[i]; if(++c>=5000) break}}' "$HOME/.bash_history" 2>/dev/null
            )
        fi
    fi
    _ghost_history=("${raw[@]}")
    _ghost_last_histcmd="${HISTCMD:-0}"
    _ghost_suggestion=""
    _ghost_matched_cmd=""
    _ghost_last_rendered=""
    _ghost_last_no_match=""
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
    _ghost_last_no_match=""
}

_ghost_clear() {
    _ghost_hide
}

_ghost_get_suggestion() {
    local input="$1"
    _ghost_suggestion=""
    if [[ -z "$input" ]]; then
        _ghost_matched_cmd=""
        _ghost_last_no_match=""
        return
    fi

    # Fast path: if input extends a prefix known to have no matches, return immediately
    if [[ -n "$_ghost_last_no_match" && "$input" == "$_ghost_last_no_match"* ]]; then
        return
    fi

    # Fast path: check if currently matched command still matches the input prefix
    if [[ -n "$_ghost_matched_cmd" && "$_ghost_matched_cmd" == "$input"* ]]; then
        if [[ "$_ghost_matched_cmd" != "$input" ]]; then
            _ghost_suggestion="${_ghost_matched_cmd#"$input"}"
            return
        fi
    fi

    local line
    for line in "${_ghost_history[@]}"; do
        if [[ "$line" == "$input"* && "$line" != "$input" ]]; then
            _ghost_matched_cmd="$line"
            _ghost_suggestion="${line#"$input"}"
            _ghost_last_no_match=""
            return
        fi
    done

    _ghost_matched_cmd=""
    _ghost_last_no_match="$input"
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
        [[ -z "$READLINE_LINE" ]] && { _ghost_matched_cmd=""; _ghost_last_no_match=""; }
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
    stty intr undef 2>/dev/null || true
    history -a 2>/dev/null
    _ghost_hide

    local cur_hist="${HISTCMD:-0}"
    if (( ${#_ghost_history[@]} == 0 || _ghost_last_histcmd == 0 || cur_hist < _ghost_last_histcmd )); then
        _ghost_init
    else
        local diff=$(( cur_hist - _ghost_last_histcmd ))
        if (( diff == 1 )); then
            local last
            last=$(HISTTIMEFORMAT= history 1 2>/dev/null)
            if [[ "$last" =~ ^[[:space:]]*[0-9]+[[:space:]]+(.*)$ ]]; then
                local cmd="${BASH_REMATCH[1]}"
                if [[ -n "$cmd" && "${_ghost_history[0]:-}" != "$cmd" ]]; then
                    _ghost_history=("$cmd" "${_ghost_history[@]}")
                fi
            fi
            _ghost_last_histcmd="$cur_hist"
        elif (( diff > 1 && diff < 50 )); then
            local -a new_cmds=()
            mapfile -t new_cmds < <(
                HISTTIMEFORMAT= history "$diff" 2>/dev/null | \
                awk '{sub(/^[[:space:]]*[0-9]+[[:space:]]*/, ""); a[NR]=$0} END{for(i=NR;i>=1;i--) if(a[i]!="") print a[i]}'
            )
            if (( ${#new_cmds[@]} > 0 )); then
                _ghost_history=("${new_cmds[@]}" "${_ghost_history[@]}")
            fi
            _ghost_last_histcmd="$cur_hist"
        elif (( diff >= 50 )); then
            _ghost_init
        fi
        (( ${#_ghost_history[@]} > 5000 )) && _ghost_history=("${_ghost_history[@]:0:5000}")
    fi
}

_ghost_insert_char() {
    local char="${_ghost_chars[$1]:-}"
    if [[ -z "$char" ]]; then
        local _oct
        printf -v _oct '%03o' "$1"
        printf -v char '%b' "\\$_oct"
    fi
    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$char${READLINE_LINE:$READLINE_POINT}"
    READLINE_POINT=$(( READLINE_POINT + ${#char} ))
    _ghost_render
}

_ghost_accept() {
    if (( READLINE_POINT < ${#READLINE_LINE} )); then
        (( READLINE_POINT++ ))
        _ghost_render
    elif [[ -n "$_ghost_suggestion" ]]; then
        READLINE_LINE+="$_ghost_suggestion"
        READLINE_POINT=${#READLINE_LINE}
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
        READLINE_LINE+="$word"
        READLINE_POINT=${#READLINE_LINE}
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
        READLINE_LINE+="$_ghost_suggestion"
        READLINE_POINT=${#READLINE_LINE}
        _ghost_render
    fi
}

_ghost_enter_clear() {
    stty intr ^C 2>/dev/null || true
    _ghost_hide
}

_ghost_init

for ((i=32; i<=126; i++)); do
    case "$i" in
        34) bind -x '"\"": _ghost_insert_char 34' ;;
        92) bind -x '"\\": _ghost_insert_char 92' ;;
        *)  bind -x "\"${_ghost_chars[$i]}\": _ghost_insert_char $i" ;;
    esac
done

bind -x '"\e[C":    _ghost_accept'
bind -x '"\eOC":    _ghost_accept'
bind -x '"\C-i":    _ghost_accept'
bind -x '"\t":     _ghost_accept'
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
bind -x '"\C-c":    _ghost_clear_line'
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

if [[ "${PROMPT_COMMAND@a}" == *a* ]]; then
    _ghost_found=0
    for _ghost_cmd in "${PROMPT_COMMAND[@]}"; do
        [[ "$_ghost_cmd" == "_ghost_refresh" ]] && { _ghost_found=1; break; }
    done
    (( !_ghost_found )) && PROMPT_COMMAND+=(_ghost_refresh)
    unset _ghost_found _ghost_cmd
else
    [[ "${PROMPT_COMMAND:-}" != *"_ghost_refresh"* ]] && PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_ghost_refresh"
fi

[[ "${PS0:-}" != *"stty intr"* ]] && PS0="${PS0:-}\$(stty intr ^C </dev/tty 2>/dev/null)"

