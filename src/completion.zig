const std = @import("std");

const BASH_COMPLETION_SCRIPT =
    \\fuzzy_expand_path() {
    \\    local raw_path="$1"
    \\    local dirs_only="${2:-1}"
    \\    local home="${HOME:-}"
    \\
    \\    local path_to_expand="$raw_path"
    \\    local expanded_prefix=""
    \\    local root_dir="."
    \\
    \\    if [[ "$path_to_expand" == "~/"* ]]; then
    \\        expanded_prefix="~/"
    \\        path_to_expand="${path_to_expand:2}"
    \\        root_dir="$home"
    \\    elif [[ "$path_to_expand" == "~" ]]; then
    \\        printf "%s\n" "~/"
    \\        return
    \\    elif [[ "$path_to_expand" == "/"* ]]; then
    \\        expanded_prefix="/"
    \\        path_to_expand="${path_to_expand:1}"
    \\        root_dir="/"
    \\    fi
    \\
    \\    while true; do
    \\        if [[ "$path_to_expand" == "../"* ]]; then
    \\            expanded_prefix="${expanded_prefix}../"
    \\            path_to_expand="${path_to_expand:3}"
    \\            root_dir="$root_dir/.."
    \\        elif [[ "$path_to_expand" == ".." ]]; then
    \\            printf "%s\n" "${expanded_prefix}../"
    \\            return
    \\        elif [[ "$path_to_expand" == "./"* ]]; then
    \\            expanded_prefix="${expanded_prefix}./"
    \\            path_to_expand="${path_to_expand:2}"
    \\            root_dir="$root_dir/."
    \\        elif [[ "$path_to_expand" == "." ]]; then
    \\            printf "%s\n" "${expanded_prefix}./"
    \\            return
    \\        else
    \\            break
    \\        fi
    \\    done
    \\
    \\    local -a segments=()
    \\    if [[ -z "$path_to_expand" ]]; then
    \\        segments=("")
    \\    else
    \\        local IFS="/"
    \\        read -ra segments <<< "$path_to_expand"
    \\        unset IFS
    \\        [[ "$raw_path" =~ /$ ]] && segments+=("")
    \\    fi
    \\
    \\    local -a current_paths=("$root_dir|$expanded_prefix|0")
    \\
    \\    for (( seg_i=0; seg_i<${#segments[@]}; seg_i++ )); do
    \\        local seg="${segments[seg_i]}"
    \\        local is_last=$(( seg_i == ${#segments[@]} - 1 ))
    \\        local -a next_paths=()
    \\
    \\        local seg_lower="${seg,,}"
    \\
    \\        for item in "${current_paths[@]}"; do
    \\            IFS="|" read -r disk_path disp_prefix cur_score <<< "$item"
    \\            [[ ! -d "$disk_path" ]] && continue
    \\
    \\            shopt -s dotglob nullglob
    \\            for entry_full in "$disk_path"/*; do
    \\                local entry="${entry_full##*/}"
    \\                [[ "$entry" == "." || "$entry" == ".." ]] && continue
    \\                if [[ "$entry" == .* && "$seg" != .* ]]; then
    \\                    continue
    \\                fi
    \\
    \\                local is_dir=0
    \\                [[ -d "$entry_full" ]] && is_dir=1
    \\
    \\                if (( dirs_only )) && (( !is_dir )); then
    \\                    continue
    \\                fi
    \\
    \\                local entry_lower="${entry,,}"
    \\                local match_score=""
    \\
    \\                if [[ -z "$seg" ]]; then
    \\                    match_score=0
    \\                elif [[ "$entry" == "$seg" ]]; then
    \\                    match_score=0
    \\                elif [[ "$entry_lower" == "$seg_lower"* ]]; then
    \\                    match_score=1
    \\                elif [[ "$entry_lower" == *"$seg_lower"* ]]; then
    \\                    match_score=2
    \\                else
    \\                    local p_idx=0
    \\                    local matched=1
    \\                    for (( ci=0; ci<${#seg_lower}; ci++ )); do
    \\                        local ch="${seg_lower:ci:1}"
    \\                        local rest="${entry_lower:p_idx}"
    \\                        if [[ "$rest" == *"$ch"* ]]; then
    \\                            local before="${rest%%"$ch"*}"
    \\                            p_idx=$(( p_idx + ${#before} + 1 ))
    \\                        else
    \\                            matched=0
    \\                            break
    \\                        fi
    \\                    done
    \\                    if (( matched )); then
    \\                        match_score=3
    \\                    fi
    \\                fi
    \\
    \\                if [[ -n "$match_score" ]]; then
    \\                    local total_score=$(( cur_score * 10 + match_score ))
    \\                    local next_disp="${disp_prefix}${entry}"
    \\                    (( is_dir )) && next_disp="${next_disp}/"
    \\                    next_paths+=("$entry_full|$next_disp|$total_score")
    \\                fi
    \\            done
    \\            shopt -u dotglob nullglob
    \\        done
    \\
    \\        current_paths=("${next_paths[@]}")
    \\        (( ${#current_paths[@]} == 0 )) && break
    \\    done
    \\
    \\    if (( ${#current_paths[@]} > 0 )); then
    \\        printf "%s\n" "${current_paths[@]}" | sort -t"|" -k3,3n -k2,2 | while IFS="|" read -r d p s; do
    \\            printf "%s\n" "$p"
    \\        done
    \\    fi
    \\}
    \\
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
    \\if [[ "$cmd" =~ ^(cd|pushd|rmdir|z|builtin[[:space:]]+cd)$ ]]; then
    \\    is_file=0
    \\    unesc="${cur//\\/}"
    \\    mapfile -t raw < <(fuzzy_expand_path "$unesc" 1)
    \\elif [[ "$comp_spec" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
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
    \\            is_file=1; mapfile -t raw < <(fuzzy_expand_path "$unesc" 0)
    \\        else
    \\            mapfile -t raw < <(compgen -c -a -b -k -- "$cur")
    \\        fi
    \\    elif [[ "$cur" == \$* ]]; then
    \\        is_file=0; mapfile -t vraw < <(compgen -v -- "${cur#\$}"); for v in "${vraw[@]}"; do raw+=("\$$v"); done
    \\    elif [[ "$cmd" =~ ^(cd|pushd|rmdir|z)$ ]]; then
    \\        is_file=0; mapfile -t raw < <(fuzzy_expand_path "$unesc" 1)
    \\    else
    \\        mapfile -t raw < <(fuzzy_expand_path "$unesc" 0)
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
        if (ch == ' ' or ch == '\t') {
            var bs_count: usize = 0;
            var b: usize = start - 1;
            while (b > 0 and line[b - 1] == '\\') : (b -= 1) {
                bs_count += 1;
            }
            if (bs_count % 2 == 0) {
                break;
            }
        } else if (ch == '|' or ch == '&' or ch == ';' or ch == '(' or ch == ')' or ch == '<' or ch == '>') {
            break;
        }
        start -= 1;
    }
    return start;
}

fn addCandidate(allocator: std.mem.Allocator, candidates: *std.array_list.AlignedManaged([]const u8, null), cand: []const u8) void {
    for (candidates.items) |c| {
        if (std.mem.eql(u8, c, cand)) return;
    }
    if (candidates.items.len >= 200) return;
    const dup = allocator.dupe(u8, cand) catch return;
    candidates.append(dup) catch {
        allocator.free(dup);
    };
}

pub fn collectCompletions(allocator: std.mem.Allocator, io: std.Io, candidates: *std.array_list.AlignedManaged([]const u8, null), line: []const u8, pt: usize) void {
    var pt_buf: [32]u8 = undefined;
    const pt_str = std.fmt.bufPrint(&pt_buf, "{d}", .{pt}) catch return;

    const res = std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "bash",
            "--norc",
            "-c",
            BASH_COMPLETION_SCRIPT,
            "_",
            line,
            pt_str,
        },
        .stdout_limit = std.Io.Limit.limited(128 * 1024),
    }) catch return;
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);

    if (res.term != .exited or res.term.exited != 0) return;

    var it = std.mem.splitScalar(u8, res.stdout, '\n');
    while (it.next()) |raw_line| {
        const cand = std.mem.trimEnd(u8, raw_line, "\r");
        if (cand.len > 0) {
            addCandidate(allocator, candidates, cand);
        }
    }
}

test "findCompletionStart" {
    try std.testing.expectEqual(@as(usize, 3), findCompletionStart("cd own", 6));
    try std.testing.expectEqual(@as(usize, 3), findCompletionStart("cd ~/own", 8));
    try std.testing.expectEqual(@as(usize, 3), findCompletionStart("cd My\\ Folder/own", 16));
}

test "collectCompletions fuzzy and case-insensitive navigation" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    {
        var candidates = std.array_list.AlignedManaged([]const u8, null).init(allocator);
        defer {
            for (candidates.items) |c| allocator.free(c);
            candidates.deinit();
        }
        collectCompletions(allocator, io, &candidates, "cd ~/own", 8);
        var found = false;
        for (candidates.items) |c| {
            if (std.mem.indexOf(u8, c, "Downloads/") != null) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }

    {
        var candidates = std.array_list.AlignedManaged([]const u8, null).init(allocator);
        defer {
            for (candidates.items) |c| allocator.free(c);
            candidates.deinit();
        }
        collectCompletions(allocator, io, &candidates, "cd ~/dow", 8);
        var found = false;
        for (candidates.items) |c| {
            if (std.mem.indexOf(u8, c, "Downloads/") != null) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }

    {
        var candidates = std.array_list.AlignedManaged([]const u8, null).init(allocator);
        defer {
            for (candidates.items) |c| allocator.free(c);
            candidates.deinit();
        }
        collectCompletions(allocator, io, &candidates, "cat src/com", 11);
        var found = false;
        for (candidates.items) |c| {
            if (std.mem.eql(u8, c, "src/completion.zig")) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}
