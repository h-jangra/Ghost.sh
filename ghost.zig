const std = @import("std");
const posix = std.posix;

pub const Key = union(enum) {
    char: u21,
    up,
    down,
    left,
    right,
    home,
    end,
    backspace,
    delete,
    tab,
    enter,
    escape,
    ctrl_a,
    ctrl_b,
    ctrl_c,
    ctrl_d,
    ctrl_e,
    ctrl_f,
    ctrl_k,
    ctrl_l,
    ctrl_u,
    ctrl_w,
    unknown,
};

pub const Term = struct {
    orig_termios: posix.termios,
    raw_active: bool = false,
    tty_fd: posix.fd_t,

    pub fn init() !Term {
        // Safely try opening /dev/tty via system call without triggering std.posix panic on ENXIO
        const rc = posix.system.open("/dev/tty", posix.system.O{ .ACCMODE = .RDWR }, 0);
        const fd: posix.fd_t = if (posix.errno(rc) == .SUCCESS) @intCast(rc) else posix.STDIN_FILENO;
        const orig = try posix.tcgetattr(fd);
        return Term{
            .orig_termios = orig,
            .raw_active = false,
            .tty_fd = fd,
        };
    }

    pub fn deinit(self: *Term) void {
        self.disableRaw();
        if (self.tty_fd != posix.STDIN_FILENO and self.tty_fd != posix.STDOUT_FILENO and self.tty_fd != posix.STDERR_FILENO) {
            posix.close(self.tty_fd);
        }
    }

    pub fn enableRaw(self: *Term) !void {
        if (self.raw_active) return;
        var raw = self.orig_termios;

        // Input modes: no break, no CR to NL, no parity check, no strip 8th bit, no flow control
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;

        // Output modes
        raw.oflag.OPOST = true;

        // Control modes: 8-bit chars
        raw.cflag.CSIZE = .CS8;

        // Local modes: echo off, canonical off, extended input off, signal chars off
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;

        // Control characters: min bytes = 1, timeout = 0
        raw.cc[@intFromEnum(posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(posix.V.TIME)] = 0;

        try posix.tcsetattr(self.tty_fd, .FLUSH, raw);
        self.raw_active = true;
    }

    pub fn disableRaw(self: *Term) void {
        if (!self.raw_active) return;
        posix.tcsetattr(self.tty_fd, .FLUSH, self.orig_termios) catch {};
        self.raw_active = false;
    }

    pub fn getWindowSize(self: *const Term) struct { rows: u16, cols: u16 } {
        var ws: posix.winsize = undefined;
        const rc = posix.system.ioctl(self.tty_fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (rc == 0 and ws.col > 0) {
            return .{ .rows = ws.row, .cols = ws.col };
        }
        return .{ .rows = 24, .cols = 80 };
    }

    pub fn readKey(self: *const Term) Key {
        var buf: [32]u8 = undefined;
        const n = posix.read(self.tty_fd, &buf) catch return .unknown;
        if (n == 0) return .unknown;

        const b0 = buf[0];
        if (b0 == 0x1b) {
            if (n == 1) return .escape;
            if (buf[1] == '[' or buf[1] == 'O') {
                if (n == 2) return .escape;
                const code = buf[2];
                if (code == 'A') return .up;
                if (code == 'B') return .down;
                if (code == 'C') return .right;
                if (code == 'D') return .left;
                if (code == 'H') return .home;
                if (code == 'F') return .end;
                if (code == 'Z') return .tab; // Shift-Tab
                if (code >= '1' and code <= '9' and n >= 4 and buf[3] == '~') {
                    if (code == '1') return .home;
                    if (code == '3') return .delete;
                    if (code == '4') return .end;
                    if (code == '7') return .home;
                    if (code == '8') return .end;
                }
                // Ctrl/Alt modified arrows: \e[1;3C etc
                if (n >= 6 and buf[1] == '[' and buf[2] == '1' and buf[3] == ';' and (buf[4] == '5' or buf[4] == '3')) {
                    if (buf[5] == 'C') return .ctrl_f;
                    if (buf[5] == 'D') return .ctrl_b;
                }
            } else if (buf[1] == 'f') {
                return .ctrl_f; // Alt-f
            } else if (buf[1] == 'b') {
                return .ctrl_b; // Alt-b
            }
            return .escape;
        }

        return switch (b0) {
            1 => .ctrl_a,
            2 => .ctrl_b,
            3 => .ctrl_c,
            4 => .ctrl_d,
            5 => .ctrl_e,
            6 => .ctrl_f,
            9 => .tab,
            10, 13 => .enter,
            11 => .ctrl_k,
            12 => .ctrl_l,
            21 => .ctrl_u,
            23 => .ctrl_w,
            127, 8 => .backspace,
            else => blk: {
                if (b0 >= 32 and b0 < 127) {
                    break :blk Key{ .char = b0 };
                }
                // Decode UTF-8 if present
                var utf8_view = std.unicode.Utf8View.init(buf[0..n]) catch {
                    break :blk .unknown;
                };
                var iter = utf8_view.iterator();
                if (iter.nextCodepoint()) |cp| {
                    break :blk Key{ .char = cp };
                }
                break :blk .unknown;
            },
        };
    }
};

pub const Editor = struct {
    allocator: std.mem.Allocator,
    term: *const Term,
    prompt_prefix: []const u8,
    prompt_last_line: []const u8,
    first_render: bool = true,
    buffer: std.ArrayList(u8),
    cursor_pos: usize = 0, // byte position in buffer
    history: std.ArrayList([]const u8),
    hist_index: ?usize = null,
    saved_input: std.ArrayList(u8),
    ghost_suggestion: ?[]const u8 = null,

    // Completion state
    in_completion: bool = false,
    candidates: std.ArrayList([]const u8),
    selected_candidate: usize = 0,
    comp_prefix_len: usize = 0,
    comp_start_byte: usize = 0,
    rendered_menu_rows: usize = 0,

    render_buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, term: *const Term, prompt: []const u8) Editor {
        var prefix: []const u8 = "";
        var last: []const u8 = prompt;
        if (std.mem.lastIndexOfScalar(u8, prompt, '\n')) |idx| {
            prefix = prompt[0 .. idx + 1];
            last = prompt[idx + 1 ..];
        }
        return Editor{
            .allocator = allocator,
            .term = term,
            .prompt_prefix = prefix,
            .prompt_last_line = last,
            .first_render = true,
            .buffer = std.ArrayList(u8).init(allocator),
            .history = std.ArrayList([]const u8).init(allocator),
            .saved_input = std.ArrayList(u8).init(allocator),
            .candidates = std.ArrayList([]const u8).init(allocator),
            .render_buf = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buffer.deinit();
        for (self.history.items) |item| self.allocator.free(item);
        self.history.deinit();
        self.saved_input.deinit();
        self.clearCandidates();
        self.candidates.deinit();
        self.render_buf.deinit();
    }

    pub fn loadHistoryFromFile(self: *Editor, path: []const u8) void {
        const file = std.fs.cwd().openFile(path, .{}) catch return;
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var r = buf_reader.reader();

        var lines = std.ArrayList([]const u8).init(self.allocator);
        defer lines.deinit();

        var line_buf: [4096]u8 = undefined;
        while (r.readUntilDelimiterOrEof(&line_buf, '\n') catch null) |line| {
            var trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            // Strip leading command numbers if from `history` command output
            var idx: usize = 0;
            while (idx < trimmed.len and ((trimmed[idx] >= '0' and trimmed[idx] <= '9') or trimmed[idx] == ' ' or trimmed[idx] == '\t')) : (idx += 1) {}
            if (idx > 0 and idx < trimmed.len and (trimmed[idx - 1] == ' ' or trimmed[idx - 1] == '\t')) {
                trimmed = trimmed[idx..];
            }
            const dup = self.allocator.dupe(u8, trimmed) catch continue;
            lines.append(dup) catch {
                self.allocator.free(dup);
                continue;
            };
        }

        // Store deduplicated in reverse order (most recent first) up to 5000
        var i: usize = lines.items.len;
        var count: usize = 0;
        while (i > 0 and count < 5000) {
            i -= 1;
            const line = lines.items[i];
            var seen = false;
            for (self.history.items) |h| {
                if (std.mem.eql(u8, h, line)) {
                    seen = true;
                    break;
                }
            }
            if (!seen) {
                self.history.append(line) catch {
                    self.allocator.free(line);
                    continue;
                };
                count += 1;
            } else {
                self.allocator.free(line);
            }
        }
    }

    pub fn updateGhost(self: *Editor) void {
        self.ghost_suggestion = null;
        if (self.in_completion) return;
        if (self.cursor_pos != self.buffer.items.len) return;
        if (self.buffer.items.len == 0) return;

        const input = self.buffer.items;
        for (self.history.items) |h| {
            if (std.mem.startsWith(u8, h, input) and h.len > input.len) {
                self.ghost_suggestion = h[input.len..];
                return;
            }
        }
    }

    pub fn clearCandidates(self: *Editor) void {
        for (self.candidates.items) |c| {
            self.allocator.free(c);
        }
        self.candidates.clearRetainingCapacity();
    }

    pub fn collectCompletions(self: *Editor) void {
        self.clearCandidates();
        const line = self.buffer.items;
        const pt = self.cursor_pos;

        // Find start of current token
        var start: usize = pt;
        while (start > 0) {
            const ch = line[start - 1];
            if (ch == ' ' or ch == '\t' or ch == '|' or ch == '&' or ch == ';' or ch == '(' or ch == ')' or ch == '<' or ch == '>') {
                break;
            }
            start -= 1;
        }
        self.comp_start_byte = start;
        const cur_word = line[start..pt];
        self.comp_prefix_len = cur_word.len;

        // Determine if first word (command completion) or arguments (file/dir completion)
        const is_first_word = blk: {
            var i: usize = 0;
            while (i < start and (line[i] == ' ' or line[i] == '\t')) : (i += 1) {}
            break :blk (i == start);
        };

        if (is_first_word and !std.mem.containsAtLeast(u8, cur_word, 1, "/")) {
            // Complete commands from PATH and builtins
            self.collectCommandCompletions(cur_word);
        } else {
            // Complete files / directories
            self.collectFileCompletions(cur_word);
        }
    }

    fn collectCommandCompletions(self: *Editor, prefix: []const u8) void {
        const builtins = [_][]const u8{
            "cd", "echo", "exit", "export", "history", "pwd", "source", "alias", "unalias",
            "set", "unset", "type", "which", "help", "exec", "eval", "read", "local", "return",
        };
        for (builtins) |b| {
            if (std.mem.startsWith(u8, b, prefix)) {
                self.addCandidate(b);
            }
        }

        const path_env = std.posix.getenv("PATH") orelse "/bin:/usr/bin";
        var it = std.mem.splitScalar(u8, path_env, ':');
        while (it.next()) |dir_path| {
            var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var dir_it = dir.iterate();
            while (dir_it.next() catch null) |entry| {
                if (entry.kind == .file or entry.kind == .sym_link) {
                    if (std.mem.startsWith(u8, entry.name, prefix)) {
                        self.addCandidate(entry.name);
                    }
                }
            }
        }
    }

    fn collectFileCompletions(self: *Editor, prefix: []const u8) void {
        var search_dir_path: []const u8 = ".";
        var file_prefix: []const u8 = prefix;
        var dir_prefix_to_prepend: []const u8 = "";

        if (std.mem.lastIndexOfScalar(u8, prefix, '/')) |idx| {
            search_dir_path = if (idx == 0) "/" else prefix[0..idx];
            file_prefix = prefix[idx + 1 ..];
            dir_prefix_to_prepend = prefix[0 .. idx + 1];
        }

        var dir = std.fs.cwd().openDir(search_dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var it = dir.iterate();
        while (it.next() catch null) |entry| {
            if (entry.name.len > 0 and entry.name[0] == '.' and file_prefix.len == 0) {
                // Don't show hidden files unless prefix starts with '.'
                continue;
            }
            if (std.mem.startsWith(u8, entry.name, file_prefix)) {
                var name_buf: [512]u8 = undefined;
                const is_dir = (entry.kind == .directory);
                const full_cand = if (is_dir)
                    std.fmt.bufPrint(&name_buf, "{s}{s}/", .{ dir_prefix_to_prepend, entry.name }) catch continue
                else
                    std.fmt.bufPrint(&name_buf, "{s}{s}", .{ dir_prefix_to_prepend, entry.name }) catch continue;

                self.addCandidate(full_cand);
            }
        }
    }

    fn addCandidate(self: *Editor, cand: []const u8) void {
        for (self.candidates.items) |c| {
            if (std.mem.eql(u8, c, cand)) return;
        }
        if (self.candidates.items.len >= 200) return;
        const dup = self.allocator.dupe(u8, cand) catch return;
        self.candidates.append(dup) catch {
            self.allocator.free(dup);
        };
    }

    pub fn insertChar(self: *Editor, cp: u21) !void {
        var utf8_buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &utf8_buf) catch return;
        try self.buffer.insertSlice(self.cursor_pos, utf8_buf[0..len]);
        self.cursor_pos += len;
    }

    pub fn deleteBackward(self: *Editor) void {
        if (self.cursor_pos == 0) return;
        // Handle utf-8 codepoint boundary backwards
        var step: usize = 1;
        while (self.cursor_pos >= step and (self.buffer.items[self.cursor_pos - step] & 0xC0) == 0x80) {
            step += 1;
        }
        const start = self.cursor_pos - step;
        _ = self.buffer.orderedRemove(start);
        var i: usize = 1;
        while (i < step) : (i += 1) {
            _ = self.buffer.orderedRemove(start);
        }
        self.cursor_pos = start;
    }

    pub fn deleteForward(self: *Editor) void {
        if (self.cursor_pos >= self.buffer.items.len) return;
        var step: usize = 1;
        while (self.cursor_pos + step < self.buffer.items.len and (self.buffer.items[self.cursor_pos + step] & 0xC0) == 0x80) {
            step += 1;
        }
        var i: usize = 0;
        while (i < step) : (i += 1) {
            _ = self.buffer.orderedRemove(self.cursor_pos);
        }
    }

    pub fn killWordBackward(self: *Editor) void {
        if (self.cursor_pos == 0) return;
        var p = self.cursor_pos;
        while (p > 0 and (self.buffer.items[p - 1] == ' ' or self.buffer.items[p - 1] == '\t')) : (p -= 1) {}
        while (p > 0 and self.buffer.items[p - 1] != ' ' and self.buffer.items[p - 1] != '\t') : (p -= 1) {}
        const count = self.cursor_pos - p;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            _ = self.buffer.orderedRemove(p);
        }
        self.cursor_pos = p;
    }

    pub fn killLineToEnd(self: *Editor) void {
        self.buffer.shrinkRetainingCapacity(self.cursor_pos);
    }

    pub fn clearLine(self: *Editor) void {
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn acceptGhost(self: *Editor) void {
        if (self.cursor_pos < self.buffer.items.len) {
            self.cursor_pos += 1;
        } else if (self.ghost_suggestion) |sugg| {
            self.buffer.appendSlice(sugg) catch return;
            self.cursor_pos = self.buffer.items.len;
            self.ghost_suggestion = null;
        }
    }

    pub fn acceptGhostWord(self: *Editor) void {
        if (self.cursor_pos < self.buffer.items.len) {
            var p = self.cursor_pos;
            while (p < self.buffer.items.len and self.buffer.items[p] != ' ') : (p += 1) {}
            while (p < self.buffer.items.len and self.buffer.items[p] == ' ') : (p += 1) {}
            self.cursor_pos = p;
        } else if (self.ghost_suggestion) |sugg| {
            var end: usize = 0;
            while (end < sugg.len and sugg[end] != ' ') : (end += 1) {}
            while (end < sugg.len and sugg[end] == ' ') : (end += 1) {}
            const word = sugg[0..end];
            self.buffer.appendSlice(word) catch return;
            self.cursor_pos = self.buffer.items.len;
            self.updateGhost();
        }
    }

    pub fn historyUp(self: *Editor) void {
        if (self.history.items.len == 0) return;
        if (self.hist_index == null) {
            self.saved_input.clearRetainingCapacity();
            self.saved_input.appendSlice(self.buffer.items) catch return;
            self.hist_index = 0;
        } else if (self.hist_index.? + 1 < self.history.items.len) {
            self.hist_index.? += 1;
        } else {
            return;
        }

        const h = self.history.items[self.hist_index.?];
        self.buffer.clearRetainingCapacity();
        self.buffer.appendSlice(h) catch return;
        self.cursor_pos = self.buffer.items.len;
    }

    pub fn historyDown(self: *Editor) void {
        if (self.hist_index == null) return;
        if (self.hist_index.? > 0) {
            self.hist_index.? -= 1;
            const h = self.history.items[self.hist_index.?];
            self.buffer.clearRetainingCapacity();
            self.buffer.appendSlice(h) catch return;
            self.cursor_pos = self.buffer.items.len;
        } else {
            self.hist_index = null;
            self.buffer.clearRetainingCapacity();
            self.buffer.appendSlice(self.saved_input.items) catch return;
            self.cursor_pos = self.buffer.items.len;
        }
    }

    pub fn applySelectedCompletion(self: *Editor, add_space_if_file: bool) void {
        if (self.candidates.items.len == 0) return;
        const cand = self.candidates.items[self.selected_candidate];
        const tail = self.allocator.dupe(u8, self.buffer.items[self.cursor_pos..]) catch "";
        defer if (tail.len > 0) self.allocator.free(tail);

        self.buffer.shrinkRetainingCapacity(self.comp_start_byte);
        self.buffer.appendSlice(cand) catch return;
        if (add_space_if_file and cand.len > 0 and cand[cand.len - 1] != '/') {
            self.buffer.append(' ') catch return;
        }
        self.cursor_pos = self.buffer.items.len;
        if (tail.len > 0) {
            self.buffer.appendSlice(tail) catch return;
        }
    }

    pub fn render(self: *Editor) !void {
        self.render_buf.clearRetainingCapacity();
        var w = self.render_buf.writer();

        const ws = self.term.getWindowSize();
        const term_cols = ws.cols;

        // If prompt has multiple lines, print prefix lines once on startup
        if (self.first_render and self.prompt_prefix.len > 0) {
            try w.writeAll(self.prompt_prefix);
            self.first_render = false;
        }

        // Hide cursor while updating buffer
        try w.writeAll("\x1b[?25l");

        // Move to start of line and clear line
        try w.writeAll("\r\x1b[2K");

        // Write prompt and buffer
        try w.writeAll(self.prompt_last_line);
        try w.writeAll(self.buffer.items);

        // Write ghost suggestion if any
        if (self.ghost_suggestion) |sugg| {
            try w.print("\x1b[38;5;244m{s}\x1b[0m", .{sugg});
        }

        // Render completion menu below if active
        var vis_rows: usize = 0;
        if (self.in_completion and self.candidates.items.len > 0) {
            const total = self.candidates.items.len;
            var max_len: usize = 0;
            for (self.candidates.items) |c| {
                if (c.len > max_len) max_len = c.len;
            }

            var col_w = max_len + 2;
            if (col_w < 12) col_w = 12;
            if (col_w > term_cols - 2) col_w = term_cols - 2;

            var num_cols = (term_cols - 2) / @as(u16, @intCast(col_w));
            if (num_cols < 1) num_cols = 1;

            const total_rows = (total + num_cols - 1) / num_cols;
            const max_rows: usize = 5;
            vis_rows = if (total_rows < max_rows) total_rows else max_rows;

            const cur_row = self.selected_candidate / num_cols;
            var start_row: usize = 0;
            if (cur_row >= vis_rows) {
                start_row = cur_row - vis_rows + 1;
            }

            var r: usize = start_row;
            var drawn_lines: usize = 0;
            while (r < start_row + vis_rows and r < total_rows) : (r += 1) {
                try w.writeAll("\n\r\x1b[2K");
                drawn_lines += 1;
                var c: usize = 0;
                while (c < num_cols) : (c += 1) {
                    const idx = r * num_cols + c;
                    if (idx < total) {
                        const item = self.candidates.items[idx];
                        const is_selected = (idx == self.selected_candidate);
                        const is_dir = (item.len > 0 and item[item.len - 1] == '/');

                        if (is_selected) {
                            try w.writeAll("\x1b[7m");
                        } else if (is_dir) {
                            try w.writeAll("\x1b[1;34m");
                        }

                        // Print truncated/padded item
                        const print_len = item.len;
                        if (print_len > col_w - 1) {
                            try w.writeAll(item[0 .. col_w - 2]);
                            try w.writeAll("…");
                        } else {
                            try w.writeAll(item);
                            var pad = (col_w - 1) - print_len;
                            while (pad > 0) : (pad -= 1) try w.writeAll(" ");
                        }

                        try w.writeAll("\x1b[0m ");
                    }
                }
            }

            // Move cursor back up to prompt line
            if (drawn_lines > 0) {
                try w.print("\x1b[{d}A", .{drawn_lines});
            }
        } else if (self.rendered_menu_rows > 0) {
            // Clean up previously rendered menu rows if we exited completion
            var i: usize = 0;
            while (i < self.rendered_menu_rows) : (i += 1) {
                try w.writeAll("\n\r\x1b[2K");
            }
            try w.print("\x1b[{d}A", .{self.rendered_menu_rows});
        }
        self.rendered_menu_rows = vis_rows;

        // Position cursor at cursor_pos
        // Carriage return + move forward visual prompt width + cursor_pos
        try w.writeAll("\r");
        const prompt_vis_w = getVisibleWidth(self.prompt_last_line);
        // Visual width of buffer up to cursor_pos
        const buf_vis_w = getVisibleWidth(self.buffer.items[0..self.cursor_pos]);
        const total_offset = prompt_vis_w + buf_vis_w;
        if (total_offset > 0) {
            try w.print("\x1b[{d}C", .{total_offset});
        }

        // Show cursor
        try w.writeAll("\x1b[?25h");

        // Flush single atomic write to terminal
        _ = try posix.write(self.term.tty_fd, self.render_buf.items);
    }
};

fn getVisibleWidth(s: []const u8) usize {
    // If multiline, take the last line
    var last_line: []const u8 = s;
    if (std.mem.lastIndexOfScalar(u8, s, '\n')) |idx| {
        last_line = s[idx + 1 ..];
    }
    if (std.mem.lastIndexOfScalar(u8, last_line, '\r')) |idx| {
        last_line = last_line[idx + 1 ..];
    }

    var w: usize = 0;
    var i: usize = 0;
    while (i < last_line.len) {
        if (last_line[i] == 0x1b) {
            // Escape sequence
            i += 1;
            if (i < last_line.len and (last_line[i] == '[' or last_line[i] == ']')) {
                i += 1;
                while (i < last_line.len and !((last_line[i] >= 'a' and last_line[i] <= 'z') or (last_line[i] >= 'A' and last_line[i] <= 'Z') or last_line[i] == '\x07')) {
                    i += 1;
                }
                if (i < last_line.len) i += 1;
            }
            continue;
        }

        const b = last_line[i];
        if (b == 0x01 or b == 0x02) {
            // Bash Readline invisible character delimiters (RL_PROMPT_START_IGNORE / RL_PROMPT_END_IGNORE)
            i += 1;
            continue;
        }

        if (b < 0x80) {
            if (b >= 32 and b != 127) {
                w += 1;
            }
            i += 1;
        } else {
            const seq_len = std.unicode.utf8ByteSequenceLength(b) catch 1;
            w += 1; // standard unicode cell width
            i += seq_len;
        }
    }
    return w;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // prog name

    var prompt: []const u8 = "";
    var hist_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--prompt") or std.mem.eql(u8, arg, "-p")) {
            prompt = args.next() orelse "";
        } else if (std.mem.eql(u8, arg, "--histfile")) {
            hist_file = args.next();
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            output_file = args.next();
        }
    }

    var term = try Term.init();
    defer term.deinit();
    try term.enableRaw();

    var editor = Editor.init(allocator, &term, prompt);
    defer editor.deinit();

    if (hist_file) |hf| {
        editor.loadHistoryFromFile(hf);
    } else {
        if (std.posix.getenv("HISTFILE")) |hf| {
            editor.loadHistoryFromFile(hf);
        } else if (std.posix.getenv("HOME")) |home| {
            var buf: [512]u8 = undefined;
            const hf = std.fmt.bufPrint(&buf, "{s}/.bash_history", .{home}) catch null;
            if (hf) |p| editor.loadHistoryFromFile(p);
        }
    }

    editor.updateGhost();
    try editor.render();

    var exit_code: u8 = 0;
    var accepted = false;

    while (true) {
        const key = term.readKey();

        if (editor.in_completion) {
            const total = editor.candidates.items.len;
            const ws = term.getWindowSize();
            var max_len: usize = 0;
            for (editor.candidates.items) |c| {
                if (c.len > max_len) max_len = c.len;
            }
            var col_w = max_len + 2;
            if (col_w < 12) col_w = 12;
            if (col_w > ws.cols - 2) col_w = ws.cols - 2;
            var num_cols = (ws.cols - 2) / @as(u16, @intCast(col_w));
            if (num_cols < 1) num_cols = 1;

            switch (key) {
                .tab, .right => {
                    editor.selected_candidate = (editor.selected_candidate + 1) % total;
                },
                .left => {
                    editor.selected_candidate = (editor.selected_candidate + total - 1) % total;
                },
                .down => {
                    if (editor.selected_candidate + num_cols < total) {
                        editor.selected_candidate += num_cols;
                    } else {
                        editor.selected_candidate = (editor.selected_candidate + 1) % total;
                    }
                },
                .up => {
                    if (editor.selected_candidate >= num_cols) {
                        editor.selected_candidate -= num_cols;
                    } else {
                        editor.selected_candidate = (editor.selected_candidate + total - 1) % total;
                    }
                },
                .enter => {
                    editor.applySelectedCompletion(true);
                    editor.in_completion = false;
                    editor.updateGhost();
                },
                .escape, .ctrl_c => {
                    editor.in_completion = false;
                    editor.updateGhost();
                },
                .char => |cp| {
                    editor.applySelectedCompletion(false);
                    editor.in_completion = false;
                    try editor.insertChar(cp);
                    editor.updateGhost();
                },
                else => {
                    editor.in_completion = false;
                    editor.updateGhost();
                },
            }
            try editor.render();
            continue;
        }

        switch (key) {
            .char => |cp| {
                try editor.insertChar(cp);
                editor.updateGhost();
            },
            .backspace => {
                editor.deleteBackward();
                editor.updateGhost();
            },
            .delete => {
                editor.deleteForward();
                editor.updateGhost();
            },
            .left => {
                if (editor.cursor_pos > 0) editor.cursor_pos -= 1;
                editor.updateGhost();
            },
            .right => {
                editor.acceptGhost();
                editor.updateGhost();
            },
            .home, .ctrl_a => {
                editor.cursor_pos = 0;
                editor.updateGhost();
            },
            .end, .ctrl_e => {
                if (editor.cursor_pos < editor.buffer.items.len) {
                    editor.cursor_pos = editor.buffer.items.len;
                } else {
                    editor.acceptGhost();
                }
                editor.updateGhost();
            },
            .ctrl_w => {
                editor.killWordBackward();
                editor.updateGhost();
            },
            .ctrl_u => {
                editor.clearLine();
                editor.updateGhost();
            },
            .ctrl_k => {
                editor.killLineToEnd();
                editor.updateGhost();
            },
            .ctrl_f => {
                editor.acceptGhostWord();
            },
            .up => {
                editor.historyUp();
                editor.updateGhost();
            },
            .down => {
                editor.historyDown();
                editor.updateGhost();
            },
            .tab => {
                editor.collectCompletions();
                if (editor.candidates.items.len == 1) {
                    editor.selected_candidate = 0;
                    editor.applySelectedCompletion(true);
                    editor.updateGhost();
                } else if (editor.candidates.items.len > 1) {
                    editor.in_completion = true;
                    editor.selected_candidate = 0;
                    editor.ghost_suggestion = null;
                }
            },
            .enter => {
                accepted = true;
                break;
            },
            .ctrl_c => {
                exit_code = 130;
                break;
            },
            .ctrl_d => {
                if (editor.buffer.items.len == 0) {
                    exit_code = 1;
                    break;
                } else {
                    editor.deleteForward();
                    editor.updateGhost();
                }
            },
            .escape => {},
            else => {},
        }

        try editor.render();
    }

    // Clean up menu lines below if any
    if (editor.rendered_menu_rows > 0) {
        var r: usize = 0;
        while (r < editor.rendered_menu_rows) : (r += 1) {
            _ = posix.write(term.tty_fd, "\n\r\x1b[2K") catch {};
        }
        var up_buf: [32]u8 = undefined;
        const up_seq = std.fmt.bufPrint(&up_buf, "\x1b[{d}A", .{editor.rendered_menu_rows}) catch "";
        _ = posix.write(term.tty_fd, up_seq) catch {};
    }

    // Move cursor to newline on enter/ctrl-c
    _ = posix.write(term.tty_fd, "\n\r") catch {};
    term.disableRaw();

    if (accepted) {
        if (output_file) |out_path| {
            const out_f = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
            defer out_f.close();
            try out_f.writeAll(editor.buffer.items);
            try out_f.writeAll("\n");
        } else {
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll(editor.buffer.items);
            try stdout.writeAll("\n");
        }
        return;
    }

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}
