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
const posix = std.posix;

pub const BUILTINS_AND_KEYWORDS = [_][]const u8{
    "alias", "bg", "bind", "break", "builtin", "caller", "case", "cd",
    "command", "compgen", "complete", "compopt", "continue", "coproc",
    "declare", "dirs", "disown", "do", "done", "echo", "elif", "else",
    "enable", "esac", "eval", "exec", "exit", "export", "false", "fc",
    "fg", "fi", "for", "function", "getopts", "hash", "help", "history",
    "if", "in", "jobs", "kill", "let", "local", "logout", "mapfile",
    "popd", "printf", "pushd", "pwd", "read", "readarray", "readonly",
    "return", "select", "set", "shift", "shopt", "source", "suspend",
    "test", "then", "time", "times", "trap", "true", "type", "typeset",
    "ulimit", "umask", "unalias", "unset", "until", "wait", "while",
};

pub const COMMON_COMMANDS = [_][]const u8{
    "awk",        "bash",       "cat",        "cargo",      "cd",
    "chmod",      "chown",      "clear",      "cp",         "curl",
    "df",         "diff",       "docker",     "du",         "echo",
    "export",     "find",       "git",        "grep",       "gzip",
    "head",       "history",    "htop",       "kill",       "less",
    "ls",         "make",       "mkdir",      "more",       "mv",
    "nano",       "node",       "npm",        "ps",         "python",
    "python3",    "rm",         "rsync",      "scp",        "sed",
    "sh",         "source",     "ssh",        "sudo",       "systemctl",
    "tail",       "tar",        "tee",        "touch",      "tree",
    "vi",         "vim",        "wc",         "which",      "zig",
};

pub const CommandCache = struct {
    allocator: std.mem.Allocator,
    commands: std.array_list.AlignedManaged([]const u8, null),
    loaded: bool = false,

    pub fn init(allocator: std.mem.Allocator) CommandCache {
        return .{
            .allocator = allocator,
            .commands = std.array_list.AlignedManaged([]const u8, null).init(allocator),
            .loaded = false,
        };
    }

    pub fn deinit(self: *CommandCache) void {
        for (self.commands.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.commands.deinit();
    }

    pub fn load(self: *CommandCache, environ: std.process.Environ) void {
        if (self.loaded) return;
        self.loaded = true;

        var set = std.StringHashMap(void).init(self.allocator);
        defer set.deinit();

        for (BUILTINS_AND_KEYWORDS) |kw| {
            const dup = self.allocator.dupe(u8, kw) catch continue;
            set.put(dup, {}) catch {
                self.allocator.free(dup);
                continue;
            };
        }

        const path_env = environ.getPosix("PATH") orelse "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
        var it = std.mem.splitScalar(u8, path_env, ':');
        var buf: [8192]u8 = undefined;

        while (it.next()) |dir_path| {
            if (dir_path.len == 0 or dir_path.len >= 4000) continue;
            var dir_z: [4096:0]u8 = undefined;
            @memcpy(dir_z[0..dir_path.len], dir_path);
            dir_z[dir_path.len] = 0;

            const fd = posix.system.open(&dir_z, posix.system.O{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
            if (posix.errno(fd) != .SUCCESS) continue;
            defer _ = posix.system.close(@intCast(fd));

            while (true) {
                const rc = posix.system.getdents64(@intCast(fd), &buf, buf.len);
                if (posix.errno(rc) != .SUCCESS or rc == 0) break;
                const n: usize = @intCast(rc);
                var pos: usize = 0;
                while (pos < n) {
                    if (pos + 19 > n) break;
                    const reclen = std.mem.readInt(u16, buf[pos + 16 .. pos + 18][0..2], .little);
                    if (reclen == 0 or pos + reclen > n) break;
                    const d_type = buf[pos + 18];
                    const name_start = pos + 19;
                    var name_end = name_start;
                    while (name_end < pos + reclen and buf[name_end] != 0) : (name_end += 1) {}
                    const name = buf[name_start..name_end];
                    if (name.len > 0 and name[0] != '.' and (d_type == 8 or d_type == 10 or d_type == 0)) {
                        if (!set.contains(name)) {
                            const name_dup = self.allocator.dupe(u8, name) catch break;
                            set.put(name_dup, {}) catch {
                                self.allocator.free(name_dup);
                                break;
                            };
                        }
                    }
                    pos += reclen;
                }
            }
        }

        var key_it = set.keyIterator();
        while (key_it.next()) |key_ptr| {
            self.commands.append(key_ptr.*) catch {
                self.allocator.free(key_ptr.*);
                continue;
            };
        }

        std.mem.sort([]const u8, self.commands.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);
    }

    pub fn findMatch(self: *const CommandCache, prefix: []const u8) ?[]const u8 {
        if (prefix.len == 0) return null;

        // 1. Check high-priority common commands
        for (COMMON_COMMANDS) |cc| {
            if (std.mem.startsWith(u8, cc, prefix) and cc.len > prefix.len) {
                for (self.commands.items) |cmd| {
                    if (std.mem.eql(u8, cmd, cc)) return cc;
                }
            }
        }

        // 2. Shortest match among all available commands (with alphabetical tie-break)
        var best_match: ?[]const u8 = null;
        var best_len: usize = std.math.maxInt(usize);

        for (self.commands.items) |cmd| {
            if (std.mem.startsWith(u8, cmd, prefix) and cmd.len > prefix.len) {
                if (cmd.len < best_len) {
                    best_len = cmd.len;
                    best_match = cmd;
                }
            }
        }

        return best_match;
    }
};

pub const CommandPositionInfo = struct {
    is_command_position: bool,
    prefix: []const u8,
};

pub fn getCommandPositionInfo(line: []const u8) CommandPositionInfo {
    if (line.len == 0) return .{ .is_command_position = true, .prefix = "" };

    var in_single_quote = false;
    var in_double_quote = false;
    var escaped = false;
    var last_sep_end: usize = 0;

    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const c = line[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (c == '\\' and !in_single_quote) {
            escaped = true;
            continue;
        }
        if (c == '\'' and !in_double_quote) {
            in_single_quote = !in_single_quote;
            continue;
        }
        if (c == '"' and !in_single_quote) {
            in_double_quote = !in_double_quote;
            continue;
        }
        if (!in_single_quote and !in_double_quote) {
            if (c == '|' or c == ';' or c == '&' or c == '(' or c == '`' or c == '{' or c == '\n') {
                last_sep_end = i + 1;
            } else if (c == '$' and i + 1 < line.len and line[i + 1] == '(') {
                last_sep_end = i + 2;
                i += 1;
            }
        }
    }

    const seg = line[last_sep_end..];
    const WordItem = struct {
        slice: []const u8,
        has_trailing_space: bool,
    };
    var words_buf: [64]WordItem = undefined;
    var words_len: usize = 0;

    var seg_i: usize = 0;
    in_single_quote = false;
    in_double_quote = false;
    escaped = false;

    while (seg_i < seg.len and words_len < words_buf.len) {
        while (seg_i < seg.len and (seg[seg_i] == ' ' or seg[seg_i] == '\t')) : (seg_i += 1) {}
        if (seg_i >= seg.len) break;

        const w_start = seg_i;
        while (seg_i < seg.len) : (seg_i += 1) {
            const sc = seg[seg_i];
            if (escaped) {
                escaped = false;
                continue;
            }
            if (sc == '\\' and !in_single_quote) {
                escaped = true;
                continue;
            }
            if (sc == '\'' and !in_double_quote) {
                in_single_quote = !in_single_quote;
                continue;
            }
            if (sc == '"' and !in_single_quote) {
                in_double_quote = !in_double_quote;
                continue;
            }
            if (!in_single_quote and !in_double_quote) {
                if (sc == ' ' or sc == '\t') break;
            }
        }
        const w_end = seg_i;
        const trailing_space = (seg_i < seg.len and (seg[seg_i] == ' ' or seg[seg_i] == '\t'));
        words_buf[words_len] = .{
            .slice = seg[w_start..w_end],
            .has_trailing_space = trailing_space,
        };
        words_len += 1;
    }

    if (words_len == 0) {
        return .{ .is_command_position = true, .prefix = "" };
    }

    const WRAPPERS = [_][]const u8{
        "sudo", "doas", "env", "nohup", "time", "watch", "xargs", "which",
        "exec", "builtin", "command", "stdbuf", "nice", "ionice", "chroot",
    };

    var word_idx: usize = 0;
    var prev_was_opt_with_arg = false;

    while (word_idx < words_len) {
        const item = words_buf[word_idx];
        const w = item.slice;
        const is_last = (word_idx == words_len - 1 and !item.has_trailing_space);

        if (prev_was_opt_with_arg) {
            prev_was_opt_with_arg = false;
            if (is_last) {
                return .{ .is_command_position = false, .prefix = w };
            }
            word_idx += 1;
            continue;
        }

        const is_env = (std.mem.indexOfScalar(u8, w, '=') != null and w[0] != '-');

        var is_wrapper = false;
        for (WRAPPERS) |wr| {
            if (std.mem.eql(u8, w, wr)) {
                is_wrapper = true;
                break;
            }
        }

        if (is_wrapper or is_env) {
            if (is_last) {
                return .{ .is_command_position = true, .prefix = w };
            }
            word_idx += 1;
            continue;
        }

        if (w.len > 0 and w[0] == '-' and word_idx > 0) {
            if (is_last) {
                return .{ .is_command_position = false, .prefix = w };
            }
            if (std.mem.eql(u8, w, "-u") or std.mem.eql(u8, w, "-g") or std.mem.eql(u8, w, "-o") or
                std.mem.eql(u8, w, "-C") or std.mem.eql(u8, w, "-n") or std.mem.eql(u8, w, "-E"))
            {
                prev_was_opt_with_arg = true;
            }
            word_idx += 1;
            continue;
        }

        // Actual command word
        if (is_last) {
            return .{ .is_command_position = true, .prefix = w };
        } else {
            return .{ .is_command_position = false, .prefix = w };
        }
    }

    return .{ .is_command_position = false, .prefix = "" };
}

pub fn findPathMatch(environ: std.process.Environ, raw_path: []const u8, result_buf: []u8) ?[]const u8 {
    if (raw_path.len == 0) return null;

    var dir_part: []const u8 = "";
    var file_prefix: []const u8 = raw_path;

    if (std.mem.lastIndexOfScalar(u8, raw_path, '/')) |idx| {
        dir_part = raw_path[0 .. idx + 1];
        file_prefix = raw_path[idx + 1 ..];
    }

    var resolved_dir_buf: [4096]u8 = undefined;
    var resolved_dir: []const u8 = ".";

    if (dir_part.len > 0) {
        if (std.mem.startsWith(u8, dir_part, "~/")) {
            const home = environ.getPosix("HOME") orelse "/";
            resolved_dir = std.fmt.bufPrint(&resolved_dir_buf, "{s}/{s}", .{ home, dir_part[2..] }) catch return null;
        } else if (std.mem.eql(u8, dir_part, "~")) {
            resolved_dir = environ.getPosix("HOME") orelse "/";
        } else {
            resolved_dir = dir_part;
        }
    }

    var path_to_open_buf: [4096:0]u8 = undefined;
    var path_to_open = resolved_dir;
    if (path_to_open.len > 1 and path_to_open[path_to_open.len - 1] == '/') {
        path_to_open = path_to_open[0 .. path_to_open.len - 1];
    }
    if (path_to_open.len >= path_to_open_buf.len) return null;
    @memcpy(path_to_open_buf[0..path_to_open.len], path_to_open);
    path_to_open_buf[path_to_open.len] = 0;

    const fd = posix.system.open(&path_to_open_buf, posix.system.O{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (posix.errno(fd) != .SUCCESS) return null;
    defer _ = posix.system.close(@intCast(fd));

    var dent_buf: [8192]u8 = undefined;
    var best_match_buf: [512]u8 = undefined;
    var best_match_len: usize = 0;
    var best_match_is_dir = false;
    var exact_prefix_found = false;

    while (true) {
        const rc = posix.system.getdents64(@intCast(fd), &dent_buf, dent_buf.len);
        if (posix.errno(rc) != .SUCCESS or rc == 0) break;
        const n: usize = @intCast(rc);
        var pos: usize = 0;
        while (pos < n) {
            if (pos + 19 > n) break;
            const reclen = std.mem.readInt(u16, dent_buf[pos + 16 .. pos + 18][0..2], .little);
            if (reclen == 0 or pos + reclen > n) break;
            const d_type = dent_buf[pos + 18];
            const name_start = pos + 19;
            var name_end = name_start;
            while (name_end < pos + reclen and dent_buf[name_end] != 0) : (name_end += 1) {}
            const name = dent_buf[name_start..name_end];

            if (name.len > 0 and !std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                if (name[0] != '.' or (file_prefix.len > 0 and file_prefix[0] == '.')) {
                    var matches = false;
                    var is_exact = false;

                    if (std.mem.startsWith(u8, name, file_prefix) and name.len > file_prefix.len) {
                        matches = true;
                        is_exact = true;
                    } else if (!exact_prefix_found and name.len > file_prefix.len and std.ascii.startsWithIgnoreCase(name, file_prefix)) {
                        matches = true;
                    }

                    if (matches) {
                        const is_dir = (d_type == 4);
                        if (is_exact and !exact_prefix_found) {
                            exact_prefix_found = true;
                            best_match_len = @min(name.len, best_match_buf.len);
                            @memcpy(best_match_buf[0..best_match_len], name[0..best_match_len]);
                            best_match_is_dir = is_dir;
                        } else if (best_match_len == 0 or name.len < best_match_len) {
                            best_match_len = @min(name.len, best_match_buf.len);
                            @memcpy(best_match_buf[0..best_match_len], name[0..best_match_len]);
                            best_match_is_dir = is_dir;
                        }
                    }
                }
            }
            pos += reclen;
        }
    }

    if (best_match_len > file_prefix.len) {
        const full_match = best_match_buf[0..best_match_len];
        const suffix = full_match[file_prefix.len..];
        var out_len = suffix.len;
        if (best_match_is_dir and out_len + 1 <= result_buf.len) {
            @memcpy(result_buf[0..out_len], suffix);
            result_buf[out_len] = '/';
            out_len += 1;
            return result_buf[0..out_len];
        } else if (out_len <= result_buf.len) {
            @memcpy(result_buf[0..out_len], suffix);
            return result_buf[0..out_len];
        }
    }

    return null;
}

pub fn findArgumentPathMatch(environ: std.process.Environ, line: []const u8, result_buf: []u8) ?[]const u8 {
    if (line.len == 0) return null;
    const last_char = line[line.len - 1];
    if (last_char == ' ' or last_char == '\t' or last_char == '|' or last_char == '&' or last_char == ';') {
        return null;
    }

    const start = findCompletionStart(line, line.len);
    const token = line[start..];
    if (token.len == 0) return null;

    return findPathMatch(environ, token, result_buf);
}

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

test "getCommandPositionInfo" {
    {
        const res = getCommandPositionInfo("g");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("g", res.prefix);
    }
    {
        const res = getCommandPositionInfo("   grep");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("grep", res.prefix);
    }
    {
        const res = getCommandPositionInfo("git ");
        try std.testing.expect(!res.is_command_position);
        try std.testing.expectEqualStrings("git", res.prefix);
    }
    {
        const res = getCommandPositionInfo("cat file.txt | gr");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("gr", res.prefix);
    }
    {
        const res = getCommandPositionInfo("cat file.txt |   wc");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("wc", res.prefix);
    }
    {
        const res = getCommandPositionInfo("echo 'a | b' | gr");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("gr", res.prefix);
    }
    {
        const res = getCommandPositionInfo("cd foo && mk");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("mk", res.prefix);
    }
    {
        const res = getCommandPositionInfo("false || ec");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("ec", res.prefix);
    }
    {
        const res = getCommandPositionInfo("sudo gr");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("gr", res.prefix);
    }
    {
        const res = getCommandPositionInfo("sudo -u root gr");
        try std.testing.expect(res.is_command_position);
        try std.testing.expectEqualStrings("gr", res.prefix);
    }
    {
        const res = getCommandPositionInfo("cat gr");
        try std.testing.expect(!res.is_command_position);
        try std.testing.expectEqualStrings("cat", res.prefix);
    }
}

test "findPathMatch in local directory" {
    var buf: [512]u8 = undefined;
    const environ = std.process.Environ.empty;
    const res = findPathMatch(environ, "src/com", &buf);
    try std.testing.expect(res != null);
    try std.testing.expectEqualStrings("pletion.zig", res.?);
}

test "findArgumentPathMatch" {
    var buf: [512]u8 = undefined;
    const environ = std.process.Environ.empty;
    const res = findArgumentPathMatch(environ, "cat src/com", &buf);
    try std.testing.expect(res != null);
    try std.testing.expectEqualStrings("pletion.zig", res.?);
}

test "CommandCache builtin and PATH matching" {
    const allocator = std.testing.allocator;
    var cache = CommandCache.init(allocator);
    defer cache.deinit();

    cache.load(std.process.Environ.empty);
    try std.testing.expect(cache.commands.items.len > 0);

    // Common command priority matching
    const git_match = cache.findMatch("gi");
    try std.testing.expect(git_match != null);
    try std.testing.expectEqualStrings("git", git_match.?);

    const grep_match = cache.findMatch("gr");
    try std.testing.expect(grep_match != null);
    try std.testing.expectEqualStrings("grep", grep_match.?);

    // Builtin matching
    const cd_match = cache.findMatch("c");
    try std.testing.expect(cd_match != null);

    const echo_match = cache.findMatch("ec");
    try std.testing.expect(echo_match != null);
    try std.testing.expectEqualStrings("echo", echo_match.?);
}
