#!/usr/bin/env bash
# Interactive completion menu navigation for Bash

NAV_MAX_ROWS="${NAV_MAX_ROWS:-5}"
_NAV_MENU_ACTIVE=0
_nav_candidates=()
_nav_rendered_rows=0
_nav_prefix=""
_nav_cur=""
_nav_suffix=""
_NAV_KEY=""

_nav_collect() {
    local line="$1" point="$2"
    _nav_candidates=()

    local i=$(( point - 1 ))
    while (( i >= 0 )); do
        [[ "${line:i:1}" =~ [[:space:]\|\&\;\(\)\<\>] ]] && break
        (( i-- ))
    done
    local start=$(( i + 1 ))
    _nav_prefix="${line:0:start}"
    _nav_cur="${line:start:point-start}"
    _nav_suffix="${line:point}"

    local pre="${line:0:point}"
    local cmd_pre="$pre"
    local last_sep=-1
    for ((i=${#pre}-1; i>=0; i--)); do
        if [[ "${pre:i:1}" =~ [\|\;\&\(\`] ]]; then
            last_sep=$i
            break
        fi
    done
    if (( last_sep >= 0 )); then
        cmd_pre="${pre:last_sep+1}"
        cmd_pre="${cmd_pre#"${cmd_pre%%[![:space:]]*}"}"
    fi

    local -a words=()
    read -ra words <<< "$cmd_pre"
    [[ "$cmd_pre" =~ [[:space:]]$ ]] && words+=("")
    local cword=$(( ${#words[@]} - 1 ))
    local cmd="${words[0]:-}"
    local prev=""
    (( cword > 0 )) && prev="${words[cword-1]}"

    local comp_spec=""
    if (( cword > 0 )) && [[ -n "$cmd" ]]; then
        comp_spec=$(complete -p "$cmd" 2>/dev/null || complete -p "${cmd##*/}" 2>/dev/null)
        if [[ -z "$comp_spec" ]]; then
            if [[ "$(complete -p -D 2>/dev/null)" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
                "${BASH_REMATCH[1]}" "$cmd" 2>/dev/null || "${BASH_REMATCH[1]}" "${cmd##*/}" 2>/dev/null
            elif declare -F _completion_loader >/dev/null; then
                _completion_loader "$cmd" 2>/dev/null || _completion_loader "${cmd##*/}" 2>/dev/null
            elif declare -F _comp_load >/dev/null; then
                _comp_load "$cmd" 2>/dev/null || _comp_load "${cmd##*/}" 2>/dev/null
            fi
            comp_spec=$(complete -p "$cmd" 2>/dev/null || complete -p "${cmd##*/}" 2>/dev/null)
        fi
    fi

    local -a raw=()
    if [[ "$comp_spec" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        local func="${BASH_REMATCH[1]}"
        if declare -F "$func" >/dev/null; then
            COMP_LINE="$cmd_pre" COMP_POINT=${#cmd_pre} COMP_WORDS=("${words[@]}") COMP_CWORD=$cword COMP_KEY=9 COMP_TYPE=9 COMPREPLY=()
            "$func" "$cmd" "$_nav_cur" "$prev" 2>/dev/null
            raw=("${COMPREPLY[@]}")
        fi
    elif [[ "$comp_spec" =~ -C[[:space:]]+(\'([^\']*)\'|\"([^\"]*)\"|([^[:space:]]+)) ]]; then
        local ccmd="${BASH_REMATCH[2]:-${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}}"
        COMP_LINE="$cmd_pre" COMP_POINT=${#cmd_pre} COMP_WORDS=("${words[@]}") COMP_CWORD=$cword COMP_KEY=9 COMP_TYPE=9
        mapfile -t raw < <(eval "$ccmd" "\"$cmd\"" "\"$_nav_cur\"" "\"$prev\"" 2>/dev/null)
    elif [[ "$comp_spec" =~ -W[[:space:]]+(\'([^\']*)\'|\"([^\"]*)\"|([^[:space:]]+)) ]]; then
        local wlist="${BASH_REMATCH[2]:-${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}}"
        mapfile -t raw < <(compgen -W "$wlist" -- "$_nav_cur")
    elif [[ "$comp_spec" =~ -A[[:space:]]+([^[:space:]]+) ]]; then
        mapfile -t raw < <(compgen -A "${BASH_REMATCH[1]}" -- "$_nav_cur")
    fi

    local is_file=1
    if (( ${#raw[@]} == 0 )); then
        local unesc="${_nav_cur//\\/}"
        if (( cword <= 0 )) || [[ -z "$cmd" ]]; then
            is_file=0
            if [[ "$_nav_cur" == ./* || "$_nav_cur" == ../* || "$_nav_cur" == /* || "$_nav_cur" == ~* ]]; then
                is_file=1
                mapfile -t raw < <(compgen -f -- "$unesc")
            else
                mapfile -t raw < <(compgen -c -a -b -k -- "$_nav_cur")
            fi
        elif [[ "$_nav_cur" == \$* ]]; then
            is_file=0
            local -a vraw=()
            mapfile -t vraw < <(compgen -v -- "${_nav_cur#\$}")
            local v
            for v in "${vraw[@]}"; do
                raw+=("\$$v")
            done
        elif [[ "$cmd" =~ ^(cd|pushd|rmdir)$ ]]; then
            is_file=0
            mapfile -t raw < <(compgen -d -S / -- "$unesc")
        else
            mapfile -t raw < <(compgen -f -- "$unesc")
        fi
    fi

    local -A seen=()
    local m
    for m in "${raw[@]}"; do
        [[ -z "$m" ]] && continue
        (( is_file )) && [[ "$m" != */ && -d "$m" ]] && m+="/"
        if [[ -z "${seen["$m"]:-}" ]]; then
            seen["$m"]=1
            _nav_candidates+=("$m")
        fi
    done
}

_nav_read_key() {
    local k rest c
    IFS= read -rsn1 k || return 1
    if [[ "$k" == $'\x1b' ]]; then
        if IFS= read -rsn1 -t 0.05 rest; then
            k+="$rest"
            if [[ "$rest" == "[" ]]; then
                while IFS= read -rsn1 -t 0.05 c; do
                    k+="$c"
                    [[ "$c" =~ [a-zA-Z~@] ]] && break
                done
            elif [[ "$rest" == "O" ]]; then
                IFS= read -rsn1 -t 0.05 c && k+="$c"
            fi
        fi
    fi
    case "$k" in
        $'\x1b[A'|$'\x1bOA')                   _NAV_KEY="UP" ;;
        $'\x1b[B'|$'\x1bOB')                   _NAV_KEY="DOWN" ;;
        $'\x1b[C'|$'\x1bOC'|$'\t'|$'\x0e')     _NAV_KEY="RIGHT" ;;
        $'\x1b[D'|$'\x1bOD'|$'\x1b[Z'|$'\x10') _NAV_KEY="LEFT" ;;
        ""|$'\n'|$'\r')                        _NAV_KEY="ENTER" ;;
        " ")                                   _NAV_KEY="SPACE" ;;
        $'\x1b'|$'\x03'|$'\x07')               _NAV_KEY="ESC" ;;
        $'\x7f'|$'\x08')                       _NAV_KEY="BACKSPACE" ;;
        *)                                     _NAV_KEY="CHAR:$k" ;;
    esac
}

_nav_cleanup() {
    if (( _nav_rendered_rows > 0 )); then
        local i clr=""
        for ((i=1; i<=_nav_rendered_rows; i++)); do clr+=$'\n\r\e[K'; done
        printf '\e7%b\e8\e[?25h' "$clr" >&2
    else
        printf '\e[?25h' >&2
    fi
    _nav_rendered_rows=0
    _NAV_MENU_ACTIVE=0
}

_nav_complete() {
    local orig_line="$READLINE_LINE" orig_point=$READLINE_POINT
    _nav_collect "$orig_line" "$orig_point"
    local total=${#_nav_candidates[@]}
    if (( total == 0 )); then
        if declare -F _ghost_render >/dev/null; then
            _ghost_render
        fi
        return 0
    fi

    if (( total == 1 )); then
        local match="${_nav_candidates[0]}" suffix=""
        [[ "$match" != */ && "$match" != *' ' && "$match" != *= ]] && suffix=" "
        READLINE_LINE="${_nav_prefix}${match}${suffix}${_nav_suffix}"
        READLINE_POINT=$(( ${#_nav_prefix} + ${#match} + ${#suffix} ))
        if declare -F _ghost_render >/dev/null; then
            _ghost_render
        fi
        return 0
    fi

    _NAV_MENU_ACTIVE=1
    if declare -F _ghost_hide >/dev/null; then
        _ghost_hide
    fi

    local term_cols="${COLUMNS:-80}"
    (( term_cols < 20 )) && term_cols=80
    local max_len=0 item
    for item in "${_nav_candidates[@]}"; do
        (( ${#item} > max_len )) && max_len=${#item}
    done

    local col_w=$(( max_len + 2 ))
    (( col_w < 12 )) && col_w=12
    (( col_w > term_cols - 2 )) && col_w=$(( term_cols - 2 ))
    local cols=$(( (term_cols - 2) / col_w ))
    (( cols < 1 )) && cols=1
    local total_rows=$(( (total + cols - 1) / cols ))
    local max_rows="${NAV_MAX_ROWS:-5}"
    local vis_rows=$(( total_rows < max_rows ? total_rows : max_rows ))

    local nl="" i
    for ((i=0; i<vis_rows; i++)); do nl+=$'\n'; done
    printf '\e[?25l%s\e[%dA\e7' "$nl" "$vis_rows" >&2
    _nav_rendered_rows=$vis_rows

    local selected=0 start_row=0
    local field_w=$(( col_w - 1 ))
    local trunc_w=$(( col_w - 2 ))
    while true; do
        local cur_row=$(( selected / cols ))
        if (( cur_row < start_row )); then
            start_row=$cur_row
        elif (( cur_row >= start_row + vis_rows )); then
            start_row=$(( cur_row - vis_rows + 1 ))
        fi

        local frame="" line_idx=1 r c idx cell
        for ((r=start_row; r<start_row+vis_rows && r<total_rows; r++)); do
            local row_str=""
            for ((c=0; c<cols; c++)); do
                idx=$(( r * cols + c ))
                if (( idx < total )); then
                    local item="${_nav_candidates[$idx]}"
                    local text="$item"
                    (( ${#text} > field_w )) && text="${text:0:trunc_w}…"
                    if (( idx == selected )); then
                        printf -v cell "\e[7m%-*s\e[0m " "$field_w" "$text"
                    elif [[ "$item" == */ ]]; then
                        printf -v cell "\e[1;34m%-*s\e[0m " "$field_w" "$text"
                    else
                        printf -v cell "\e[0m%-*s " "$field_w" "$text"
                    fi
                    row_str+="$cell"
                fi
            done
            frame+=$'\n\r'"$row_str"$'\e[K'
            (( line_idx++ ))
        done
        for (( ; line_idx <= vis_rows; line_idx++ )); do frame+=$'\n\r\e[K'; done

        printf '\e7%b\e8' "$frame" >&2
        _nav_read_key || break

        case "$_NAV_KEY" in
            RIGHT) selected=$(( (selected + 1) % total )) ;;
            LEFT)  selected=$(( (selected - 1 + total) % total )) ;;
            DOWN)
                if (( total_rows == 1 )); then
                    selected=$(( (selected + 1) % total ))
                else
                    selected=$(( selected + cols ))
                    if (( selected >= total )); then
                        if (( (selected - cols) / cols < total_rows - 1 )); then
                            selected=$(( total - 1 ))
                        else
                            selected=$(( selected % cols ))
                        fi
                    fi
                fi
                ;;
            UP)
                if (( total_rows == 1 )); then
                    selected=$(( (selected - 1 + total) % total ))
                else
                    selected=$(( selected - cols ))
                    if (( selected < 0 )); then
                        local col_idx=$(( (selected + cols) % cols ))
                        selected=$(( (total_rows - 1) * cols + col_idx ))
                        (( selected >= total )) && selected=$(( total - 1 ))
                    fi
                fi
                ;;
            ENTER)
                local match="${_nav_candidates[$selected]}" suffix=""
                [[ "$match" != */ && "$match" != *' ' && "$match" != *= ]] && suffix=" "
                READLINE_LINE="${_nav_prefix}${match}${suffix}${_nav_suffix}"
                READLINE_POINT=$(( ${#_nav_prefix} + ${#match} + ${#suffix} ))
                break
                ;;
            SPACE)
                local match="${_nav_candidates[$selected]}" suffix=" "
                [[ "$match" == *' ' ]] && suffix=""
                READLINE_LINE="${_nav_prefix}${match}${suffix}${_nav_suffix}"
                READLINE_POINT=$(( ${#_nav_prefix} + ${#match} + ${#suffix} ))
                break
                ;;
            ESC)
                READLINE_LINE="$orig_line"
                READLINE_POINT=$orig_point
                break
                ;;
            BACKSPACE)
                if (( orig_point > 0 )); then
                    READLINE_LINE="${orig_line:0:$((orig_point - 1))}${orig_line:$orig_point}"
                    READLINE_POINT=$(( orig_point - 1 ))
                else
                    READLINE_LINE="$orig_line"
                    READLINE_POINT=$orig_point
                fi
                break
                ;;
            CHAR:*)
                local ch="${_NAV_KEY#CHAR:}"
                local match="${_nav_candidates[$selected]}"
                READLINE_LINE="${_nav_prefix}${match}${ch}${_nav_suffix}"
                READLINE_POINT=$(( ${#_nav_prefix} + ${#match} + ${#ch} ))
                break
                ;;
        esac
    done

    _nav_cleanup
    if declare -F _ghost_render >/dev/null; then
        _ghost_render
    fi
}

bind -x '"\C-i": _nav_complete'
bind -x '"\t":   _nav_complete'
