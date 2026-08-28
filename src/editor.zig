const std = @import("std");
const posix = std.posix;
const Term = @import("terminal.zig").Term;
const completion = @import("completion.zig");

pub const Editor = struct {
    allocator: std.mem.Allocator,
    term: *const Term,
    prompt_prefix: []const u8,
    prompt_last_line: []const u8,
    first_render: bool = true,
    buffer: std.ArrayList(u8),
    cursor_pos: usize = 0,
    history: std.ArrayList([]const u8),
    hist_index: ?usize = null,
    saved_input: std.ArrayList(u8),
    ghost_suggestion: ?[]const u8 = null,

    in_completion: bool = false,
    candidates: std.ArrayList([]const u8),
    selected_candidate: usize = 0,
    comp_start_byte: usize = 0,
    rendered_menu_rows: usize = 0,
    in_paste: bool = false,
    in_isearch: bool = false,
    isearch_query: std.ArrayList(u8),
    isearch_match_index: ?usize = null,

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
            .isearch_query = std.ArrayList(u8).init(allocator),
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
        self.isearch_query.deinit();
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
            if (trimmed[0] >= '0' and trimmed[0] <= '9') {
                var idx: usize = 0;
                while (idx < trimmed.len and (trimmed[idx] >= '0' and trimmed[idx] <= '9')) : (idx += 1) {}
                if (idx < trimmed.len and (trimmed[idx] == ' ' or trimmed[idx] == '\t')) {
                    while (idx < trimmed.len and (trimmed[idx] == ' ' or trimmed[idx] == '\t')) : (idx += 1) {}
                    trimmed = trimmed[idx..];
                }
            }
            if (trimmed.len == 0) continue;
            const dup = self.allocator.dupe(u8, trimmed) catch continue;
            lines.append(dup) catch {
                self.allocator.free(dup);
                continue;
            };
        }

        var i: usize = lines.items.len;
        var count: usize = 0;
        while (i > 0 and count < 2000) {
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
        if (self.in_completion or self.in_paste) return;
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
        self.comp_start_byte = completion.findCompletionStart(self.buffer.items, self.cursor_pos);
        completion.collectCompletions(self.allocator, &self.candidates, self.buffer.items, self.cursor_pos);
    }

    pub fn insertChar(self: *Editor, cp: u21) !void {
        var utf8_buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &utf8_buf) catch return;
        try self.buffer.insertSlice(self.cursor_pos, utf8_buf[0..len]);
        self.cursor_pos += len;
    }

    pub fn insertSlice(self: *Editor, bytes: []const u8) !void {
        try self.buffer.insertSlice(self.cursor_pos, bytes);
        self.cursor_pos += bytes.len;
    }

    fn utf8StepBack(self: *const Editor, from: usize) usize {
        if (from == 0) return 0;
        var step: usize = 1;
        while (from >= step and (self.buffer.items[from - step] & 0xC0) == 0x80) step += 1;
        return step;
    }

    fn utf8StepForward(self: *const Editor, from: usize) usize {
        if (from >= self.buffer.items.len) return 0;
        var step: usize = 1;
        while (from + step < self.buffer.items.len and (self.buffer.items[from + step] & 0xC0) == 0x80) step += 1;
        return step;
    }

    pub fn deleteBackward(self: *Editor) void {
        const step = self.utf8StepBack(self.cursor_pos);
        if (step == 0) return;
        const start = self.cursor_pos - step;
        var i: usize = 0;
        while (i < step) : (i += 1) _ = self.buffer.orderedRemove(start);
        self.cursor_pos = start;
    }

    pub fn deleteForward(self: *Editor) void {
        const step = self.utf8StepForward(self.cursor_pos);
        if (step == 0) return;
        var i: usize = 0;
        while (i < step) : (i += 1) _ = self.buffer.orderedRemove(self.cursor_pos);
    }

    pub fn killWordBackward(self: *Editor) void {
        if (self.cursor_pos == 0) return;
        var p = self.cursor_pos;
        while (p > 0 and (self.buffer.items[p - 1] == ' ' or self.buffer.items[p - 1] == '\t')) : (p -= 1) {}
        while (p > 0 and self.buffer.items[p - 1] != ' ' and self.buffer.items[p - 1] != '\t') : (p -= 1) {}
        const count = self.cursor_pos - p;
        var i: usize = 0;
        while (i < count) : (i += 1) _ = self.buffer.orderedRemove(p);
        self.cursor_pos = p;
    }

    pub fn killLineToEnd(self: *Editor) void {
        self.buffer.shrinkRetainingCapacity(self.cursor_pos);
    }

    pub fn killLineToStart(self: *Editor) void {
        if (self.cursor_pos == 0) return;
        const count = self.cursor_pos;
        var i: usize = 0;
        while (i < count) : (i += 1) _ = self.buffer.orderedRemove(0);
        self.cursor_pos = 0;
    }

    pub fn killWordForward(self: *Editor) void {
        if (self.cursor_pos >= self.buffer.items.len) return;
        var p = self.cursor_pos;
        while (p < self.buffer.items.len and (self.buffer.items[p] == ' ' or self.buffer.items[p] == '\t')) : (p += 1) {}
        while (p < self.buffer.items.len and self.buffer.items[p] != ' ' and self.buffer.items[p] != '\t') : (p += 1) {}
        const count = p - self.cursor_pos;
        var i: usize = 0;
        while (i < count) : (i += 1) _ = self.buffer.orderedRemove(self.cursor_pos);
    }

    pub fn clearLine(self: *Editor) void {
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn moveCursorLeft(self: *Editor) void {
        const step = self.utf8StepBack(self.cursor_pos);
        self.cursor_pos -= step;
    }

    pub fn acceptGhost(self: *Editor) void {
        if (self.ghost_suggestion) |sugg| {
            self.buffer.appendSlice(sugg) catch return;
            self.cursor_pos = self.buffer.items.len;
            self.ghost_suggestion = null;
        }
    }

    pub fn moveCursorRight(self: *Editor) void {
        if (self.cursor_pos < self.buffer.items.len) {
            self.cursor_pos += self.utf8StepForward(self.cursor_pos);
        } else {
            self.acceptGhost();
        }
    }

    pub fn moveCursorEnd(self: *Editor) void {
        if (self.cursor_pos < self.buffer.items.len) {
            self.cursor_pos = self.buffer.items.len;
        } else {
            self.acceptGhost();
        }
    }

    pub fn moveWordForward(self: *Editor) void {
        if (self.cursor_pos < self.buffer.items.len) {
            var p = self.cursor_pos;
            while (p < self.buffer.items.len and (self.buffer.items[p] == ' ' or self.buffer.items[p] == '\t')) : (p += 1) {}
            while (p < self.buffer.items.len and self.buffer.items[p] != ' ' and self.buffer.items[p] != '\t') : (p += 1) {}
            self.cursor_pos = p;
        } else if (self.ghost_suggestion) |sugg| {
            var end: usize = 0;
            while (end < sugg.len and (sugg[end] == ' ' or sugg[end] == '\t')) : (end += 1) {}
            while (end < sugg.len and sugg[end] != ' ' and sugg[end] != '\t') : (end += 1) {}
            while (end < sugg.len and (sugg[end] == ' ' or sugg[end] == '\t')) : (end += 1) {}
            if (end == 0) end = sugg.len;
            self.buffer.appendSlice(sugg[0..end]) catch return;
            self.cursor_pos = self.buffer.items.len;
        }
    }

    pub fn moveWordBackward(self: *Editor) void {
        if (self.cursor_pos == 0) return;
        var p = self.cursor_pos;
        while (p > 0 and (self.buffer.items[p - 1] == ' ' or self.buffer.items[p - 1] == '\t')) : (p -= 1) {}
        while (p > 0 and self.buffer.items[p - 1] != ' ' and self.buffer.items[p - 1] != '\t') : (p -= 1) {}
        self.cursor_pos = p;
    }

    pub fn transposeChars(self: *Editor) void {
        if (self.buffer.items.len < 2 or self.cursor_pos == 0) return;
        const idx = if (self.cursor_pos < self.buffer.items.len) self.cursor_pos else self.buffer.items.len - 1;
        const tmp = self.buffer.items[idx - 1];
        self.buffer.items[idx - 1] = self.buffer.items[idx];
        self.buffer.items[idx] = tmp;
        if (self.cursor_pos < self.buffer.items.len) self.cursor_pos += 1;
    }

    pub fn clearScreen(self: *Editor) !void {
        _ = posix.write(self.term.tty_fd, "\x1b[2J\x1b[H") catch {};
        self.first_render = true;
    }

    pub fn cleanMenu(self: *Editor) void {
        if (self.rendered_menu_rows > 0) {
            var clear_buf: [64]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&clear_buf);
            const render = @import("render.zig");
            render.writeClearMenu(fbs.writer(), self.rendered_menu_rows) catch {};
            _ = posix.write(self.term.tty_fd, fbs.getWritten()) catch {};
            self.rendered_menu_rows = 0;
        }
    }

    pub fn editAndExecute(self: *Editor) !bool {
        const editor_cmd = std.posix.getenv("VISUAL") orelse
            std.posix.getenv("EDITOR") orelse
            "nano";

        var tmp_buf: [128]u8 = undefined;
        const pid = std.os.linux.getpid();
        const tmp_path = try std.fmt.bufPrint(&tmp_buf, "/tmp/ghost_edit_{d}.sh", .{pid});

        {
            const f = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true });
            defer f.close();
            try f.writeAll(self.buffer.items);
            try f.writeAll("\n");
        }
        defer std.fs.cwd().deleteFile(tmp_path) catch {};

        var term_ptr = @constCast(self.term);
        self.cleanMenu();
        term_ptr.suspendRaw();

        var child = std.process.Child.init(&[_][]const u8{ editor_cmd, tmp_path }, self.allocator);
        _ = child.spawnAndWait() catch {
            var fallback = std.process.Child.init(&[_][]const u8{ "vi", tmp_path }, self.allocator);
            _ = fallback.spawnAndWait() catch {};
        };

        try term_ptr.resumeRaw();

        const f = std.fs.cwd().openFile(tmp_path, .{}) catch return false;
        defer f.close();
        const content = f.readToEndAlloc(self.allocator, 1024 * 1024) catch return false;
        defer self.allocator.free(content);

        const trimmed = std.mem.trimRight(u8, content, " \t\r\n");
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(trimmed);
        self.cursor_pos = self.buffer.items.len;

        if (trimmed.len > 0) return true;
        self.first_render = true;
        return false;
    }

    pub fn historySearchInteractive(self: *Editor) !bool {
        if (self.history.items.len == 0) return false;

        if (std.posix.getenv("GHOST_CTRL_R_COMMAND")) |cmd| {
            if (cmd.len > 0) {
                var term_ptr = @constCast(self.term);
                self.cleanMenu();
                term_ptr.suspendRaw();

                var selected_opt: ?[]const u8 = null;

                var child = std.process.Child.init(&[_][]const u8{
                    "bash",
                    "--norc",
                    "-c",
                    "eval \"$GHOST_CTRL_R_COMMAND\"",
                    "_",
                    self.buffer.items,
                }, self.allocator);

                child.stdin_behavior = .Pipe;
                child.stdout_behavior = .Pipe;
                child.stderr_behavior = .Inherit;

                if (child.spawn()) {
                    if (child.stdin) |*stdin_pipe| {
                        for (self.history.items) |h| {
                            _ = stdin_pipe.write(h) catch break;
                            _ = stdin_pipe.write("\n") catch break;
                        }
                        stdin_pipe.close();
                        child.stdin = null;
                    }

                    var out_list = std.ArrayList(u8).init(self.allocator);
                    defer out_list.deinit();

                    if (child.stdout) |*stdout_pipe| {
                        var buf: [1024]u8 = undefined;
                        while (true) {
                            const n = stdout_pipe.read(&buf) catch break;
                            if (n == 0) break;
                            out_list.appendSlice(buf[0..n]) catch break;
                        }
                    }

                    const term_res = child.wait() catch null;
                    if (term_res) |res| {
                        if (res == .Exited and res.Exited == 0 and out_list.items.len > 0) {
                            selected_opt = self.allocator.dupe(u8, std.mem.trimRight(u8, out_list.items, "\r\n")) catch null;
                        }
                    }
                } else |_| {}

                try term_ptr.resumeRaw();

                if (selected_opt) |sel| {
                    defer self.allocator.free(sel);
                    self.buffer.clearRetainingCapacity();
                    try self.buffer.appendSlice(sel);
                    self.cursor_pos = self.buffer.items.len;
                    self.hist_index = null;
                }

                self.first_render = true;
                return true;
            }
        }

        self.startIsearch();
        return false;
    }

    pub fn startIsearch(self: *Editor) void {
        self.cleanMenu();
        self.in_completion = false;
        self.in_isearch = true;
        self.isearch_query.clearRetainingCapacity();
        self.saved_input.clearRetainingCapacity();
        self.saved_input.appendSlice(self.buffer.items) catch {};
        self.isearch_match_index = null;
        self.updateIsearchMatch(true);
    }

    pub fn cancelIsearch(self: *Editor) void {
        self.in_isearch = false;
        self.buffer.clearRetainingCapacity();
        self.buffer.appendSlice(self.saved_input.items) catch {};
        self.cursor_pos = self.buffer.items.len;
        self.isearch_query.clearRetainingCapacity();
        self.isearch_match_index = null;
    }

    pub fn acceptIsearch(self: *Editor) void {
        self.in_isearch = false;
        self.isearch_query.clearRetainingCapacity();
        self.isearch_match_index = null;
    }

    pub fn updateIsearchMatch(self: *Editor, forward_or_first: bool) void {
        _ = forward_or_first;
        if (self.history.items.len == 0) return;
        const q = self.isearch_query.items;
        if (q.len == 0) {
            self.isearch_match_index = null;
            self.buffer.clearRetainingCapacity();
            self.buffer.appendSlice(self.saved_input.items) catch {};
            self.cursor_pos = self.buffer.items.len;
            return;
        }

        var start_idx: usize = 0;
        if (self.isearch_match_index) |cur| {
            start_idx = cur;
        }

        var i: usize = start_idx;
        while (i < self.history.items.len) : (i += 1) {
            if (std.mem.indexOf(u8, self.history.items[i], q)) |_| {
                self.isearch_match_index = i;
                self.buffer.clearRetainingCapacity();
                self.buffer.appendSlice(self.history.items[i]) catch {};
                self.cursor_pos = self.buffer.items.len;
                return;
            }
        }

        // Wrap around from start if not found from current
        if (start_idx > 0) {
            i = 0;
            while (i < start_idx) : (i += 1) {
                if (std.mem.indexOf(u8, self.history.items[i], q)) |_| {
                    self.isearch_match_index = i;
                    self.buffer.clearRetainingCapacity();
                    self.buffer.appendSlice(self.history.items[i]) catch {};
                    self.cursor_pos = self.buffer.items.len;
                    return;
                }
            }
        }
    }

    pub fn isearchNextMatch(self: *Editor) void {
        if (self.history.items.len == 0) return;
        const q = self.isearch_query.items;
        if (q.len == 0) return;

        const start_idx: usize = if (self.isearch_match_index) |cur| cur + 1 else 0;
        var i = start_idx;
        while (i < self.history.items.len) : (i += 1) {
            if (std.mem.indexOf(u8, self.history.items[i], q)) |_| {
                self.isearch_match_index = i;
                self.buffer.clearRetainingCapacity();
                self.buffer.appendSlice(self.history.items[i]) catch {};
                self.cursor_pos = self.buffer.items.len;
                return;
            }
        }

        // Wrap around
        i = 0;
        while (i < start_idx and i < self.history.items.len) : (i += 1) {
            if (std.mem.indexOf(u8, self.history.items[i], q)) |_| {
                self.isearch_match_index = i;
                self.buffer.clearRetainingCapacity();
                self.buffer.appendSlice(self.history.items[i]) catch {};
                self.cursor_pos = self.buffer.items.len;
                return;
            }
        }
    }

    pub fn isearchInsertChar(self: *Editor, cp: u21) !void {
        var utf8_buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &utf8_buf) catch return;
        try self.isearch_query.appendSlice(utf8_buf[0..len]);
        self.updateIsearchMatch(true);
    }

    pub fn isearchDeleteBackward(self: *Editor) void {
        if (self.isearch_query.items.len == 0) return;
        var step: usize = 1;
        const from = self.isearch_query.items.len;
        while (from >= step and (self.isearch_query.items[from - step] & 0xC0) == 0x80) step += 1;
        self.isearch_query.shrinkRetainingCapacity(from - step);
        self.isearch_match_index = null;
        self.updateIsearchMatch(true);
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
        if (add_space_if_file and cand.len > 0 and cand[cand.len - 1] != '/' and cand[cand.len - 1] != ' ' and cand[cand.len - 1] != '=') {
            self.buffer.append(' ') catch return;
        }
        self.cursor_pos = self.buffer.items.len;
        if (tail.len > 0) self.buffer.appendSlice(tail) catch return;
    }
};
