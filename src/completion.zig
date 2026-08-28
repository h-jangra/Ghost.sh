const std = @import("std");

const BASH_COMPLETION_SCRIPT =
    \\if [[ -n "${BASH_COMPLETION:-}" && -r "$BASH_COMPLETION" ]]; then
    \\    . "$BASH_COMPLETION" 2>/dev/null
    \\else
    \\    for f in "${BASH_COMPLETION_USER_DIR:-$HOME/.local/share/bash-completion}/bash_completion" \
    \\             /usr/share/bash-completion/bash_completion \
    \\             /etc/bash_completion; do
    \\        [[ -r "$f" ]] && . "$f" 2>/dev/null && break
    \\    done
    \\fi
    \\
    \\line="$1" point="${2:-${#line}}"
    \\pre="${line:0:point}"
    \\cmd_pre="$pre"
    \\for ((i=${#pre}-1; i>=0; i--)); do
    \\    ch="${pre:i:1}"
    \\    if [[ "$ch" == '|' || "$ch" == ';' || "$ch" == '&' || "$ch" == '(' || "$ch" == ')' || "$ch" == '`' ]]; then
    \\        cmd_pre="${pre:i+1}"
    \\        break
    \\    fi
    \\done
    \\cmd_pre="${cmd_pre#"${cmd_pre%%[![:space:]]*}"}"
    \\
    \\read -ra words <<< "$cmd_pre"
    \\[[ "$cmd_pre" =~ [[:space:]]$ ]] && words+=("")
    \\cword=$(( ${#words[@]} - 1 ))
    \\cur="${words[cword]:-}"
    \\cmd="${words[0]:-}"
    \\prev=""
    \\(( cword > 0 )) && prev="${words[cword-1]}"
    \\
    \\comp_spec=""
    \\if (( cword > 0 )) && [[ -n "$cmd" ]]; then
    \\    comp_spec=$(complete -p "$cmd" 2>/dev/null || complete -p "${cmd##*/}" 2>/dev/null)
    \\    if [[ -z "$comp_spec" ]]; then
    \\        if [[ "$(complete -p -D 2>/dev/null)" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
    \\            "${BASH_REMATCH[1]}" "$cmd" 2>/dev/null || "${BASH_REMATCH[1]}" "${cmd##*/}" 2>/dev/null
    \\        elif declare -F _completion_loader >/dev/null; then
    \\            _completion_loader "$cmd" 2>/dev/null || _completion_loader "${cmd##*/}" 2>/dev/null
    \\        elif declare -F _comp_load >/dev/null; then
    \\            _comp_load "$cmd" 2>/dev/null || _comp_load "${cmd##*/}" 2>/dev/null
    \\        fi
    \\        comp_spec=$(complete -p "$cmd" 2>/dev/null || complete -p "${cmd##*/}" 2>/dev/null)
    \\    fi
    \\fi
    \\
    \\raw=()
    \\if [[ "$comp_spec" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
    \\    func="${BASH_REMATCH[1]}"
    \\    if declare -F "$func" >/dev/null; then
    \\        COMP_LINE="$cmd_pre" COMP_POINT=${#cmd_pre} COMP_WORDS=("${words[@]}") COMP_CWORD=$cword COMP_KEY=9 COMP_TYPE=9 COMPREPLY=()
    \\        "$func" "$cmd" "$cur" "$prev" 2>/dev/null
    \\        raw=("${COMPREPLY[@]}")
    \\    fi
    \\elif [[ "$comp_spec" =~ -C[[:space:]]+(\'([^\']*)\'|\"([^\"]*)\"|([^[:space:]]+)) ]]; then
    \\    ccmd="${BASH_REMATCH[2]:-${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}}"
    \\    COMP_LINE="$cmd_pre" COMP_POINT=${#cmd_pre} COMP_WORDS=("${words[@]}") COMP_CWORD=$cword COMP_KEY=9 COMP_TYPE=9
    \\    mapfile -t raw < <(eval "$ccmd" "\"$cmd\"" "\"$cur\"" "\"$prev\"" 2>/dev/null)
    \\elif [[ "$comp_spec" =~ -W[[:space:]]+(\'([^\']*)\'|\"([^\"]*)\"|([^[:space:]]+)) ]]; then
    \\    mapfile -t raw < <(compgen -W "${BASH_REMATCH[2]:-${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}}" -- "$cur")
    \\elif [[ "$comp_spec" =~ -A[[:space:]]+([^[:space:]]+) ]]; then
    \\    mapfile -t raw < <(compgen -A "${BASH_REMATCH[1]}" -- "$cur")
    \\fi
    \\
    \\is_file=1
    \\if (( ${#raw[@]} == 0 )); then
    \\    unesc="${cur//\\/}"
    \\    if (( cword <= 0 )) || [[ -z "$cmd" ]]; then
    \\        is_file=0
    \\        if [[ "$cur" == ./* || "$cur" == ../* || "$cur" == /* || "$cur" == ~* ]]; then
    \\            is_file=1; mapfile -t raw < <(compgen -f -- "$unesc")
    \\        else
    \\            mapfile -t raw < <(compgen -c -a -b -k -- "$cur")
    \\        fi
    \\    elif [[ "$cur" == \$* ]]; then
    \\        is_file=0; mapfile -t vraw < <(compgen -v -- "${cur#\$}"); for v in "${vraw[@]}"; do raw+=("\$$v"); done
    \\    elif [[ "$cmd" =~ ^(cd|pushd|rmdir)$ ]]; then
    \\        is_file=0; mapfile -t raw < <(compgen -d -S / -- "$unesc")
    \\    else
    \\        mapfile -t raw < <(compgen -f -- "$unesc")
    \\    fi
    \\fi
    \\
    \\declare -A seen=()
    \\for m in "${raw[@]}"; do
    \\    [[ -z "$m" ]] && continue
    \\    (( is_file )) && [[ "$m" != */ && -d "$m" ]] && m+="/"
    \\    if [[ -z "${seen["$m"]:-}" ]]; then
    \\        seen["$m"]=1
    \\        printf "%s\n" "$m"
    \\    fi
    \\done
;

pub fn findCompletionStart(line: []const u8, pt: usize) usize {
    var start: usize = pt;
    while (start > 0) {
        const ch = line[start - 1];
        if (ch == ' ' or ch == '\t' or ch == '|' or ch == '&' or ch == ';' or ch == '(' or ch == ')' or ch == '<' or ch == '>') {
            break;
        }
        start -= 1;
    }
    return start;
}

fn addCandidate(allocator: std.mem.Allocator, candidates: *std.ArrayList([]const u8), cand: []const u8) void {
    for (candidates.items) |c| {
        if (std.mem.eql(u8, c, cand)) return;
    }
    if (candidates.items.len >= 200) return;
    const dup = allocator.dupe(u8, cand) catch return;
    candidates.append(dup) catch {
        allocator.free(dup);
    };
}

pub fn collectCompletions(allocator: std.mem.Allocator, candidates: *std.ArrayList([]const u8), line: []const u8, pt: usize) void {
    var pt_buf: [32]u8 = undefined;
    const pt_str = std.fmt.bufPrint(&pt_buf, "{d}", .{pt}) catch return;

    const res = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "bash",
            "--norc",
            "-c",
            BASH_COMPLETION_SCRIPT,
            "_",
            line,
            pt_str,
        },
        .max_output_bytes = 128 * 1024,
    }) catch return;
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);

    if (res.term != .Exited or res.term.Exited != 0) return;

    var it = std.mem.splitScalar(u8, res.stdout, '\n');
    while (it.next()) |raw_line| {
        const cand = std.mem.trimRight(u8, raw_line, "\r");
        if (cand.len > 0) {
            addCandidate(allocator, candidates, cand);
        }
    }
}
