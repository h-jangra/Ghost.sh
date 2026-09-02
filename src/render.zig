const std = @import("std");
const posix = std.posix;
const terminal = @import("terminal.zig");
const Editor = @import("editor.zig").Editor;

pub const MenuLayout = struct {
    col_w: usize,
    num_cols: usize,
    vis_rows: usize,
    total_rows: usize,

    pub fn calculate(candidates_len: usize, max_candidate_len: usize, term_cols: usize) MenuLayout {
        var col_w: usize = max_candidate_len + 2;
        if (col_w < 12) col_w = 12;
        if (col_w > term_cols) col_w = term_cols;

        var num_cols: usize = if (term_cols >= col_w) term_cols / col_w else 1;
        if (num_cols < 1) num_cols = 1;

        const total_rows = (candidates_len + num_cols - 1) / num_cols;
        const max_rows: usize = 5;
        const vis_rows = if (total_rows < max_rows) total_rows else max_rows;

        return .{
            .col_w = col_w,
            .num_cols = num_cols,
            .vis_rows = vis_rows,
            .total_rows = total_rows,
        };
    }
};

fn isFullWidth(cp: u21) bool {
    if (cp < 0x1100) return false;
    return (cp >= 0x1100 and cp <= 0x115F) or
        (cp >= 0x2E80 and cp <= 0xA4CF and cp != 0x303F) or
        (cp >= 0xAC00 and cp <= 0xD7A3) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0xFE10 and cp <= 0xFE19) or
        (cp >= 0xFE30 and cp <= 0xFE6F) or
        (cp >= 0xFF00 and cp <= 0xFF60) or
        (cp >= 0xFFE0 and cp <= 0xFFE6) or
        (cp >= 0x1F300 and cp <= 0x1F64F) or
        (cp >= 0x1F900 and cp <= 0x1F9FF) or
        (cp >= 0x20000 and cp <= 0x3FFFD);
}

pub fn getVisibleWidth(s: []const u8) usize {
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
            if (i + seq_len <= last_line.len) {
                if (std.unicode.utf8Decode(last_line[i .. i + seq_len])) |cp| {
                    w += if (isFullWidth(cp)) 2 else 1;
                } else |_| {
                    w += 1;
                }
            } else {
                w += 1;
            }
            i += seq_len;
        }
    }
    return w;
}

pub fn writeClearMenu(w: anytype, rows: usize) !void {
    if (rows == 0) return;
    var r: usize = 0;
    while (r < rows) : (r += 1) try w.writeAll("\n\r\x1b[2K");
    try w.print("\x1b[{d}A", .{rows});
}

pub fn getMaxCandidateWidth(candidates: []const []const u8) usize {
    var max_len: usize = 0;
    for (candidates) |c| {
        const cw = getVisibleWidth(c);
        if (cw > max_len) max_len = cw;
    }
    return max_len;
}

const editor_mod = @import("editor.zig");

pub const BufWriter = struct {
    list: *editor_mod.ArrayList(u8),

    pub fn writeAll(self: *BufWriter, bytes: []const u8) !void {
        try self.list.appendSlice(bytes);
    }

    pub fn print(self: *BufWriter, comptime format: []const u8, args: anytype) !void {
        var buf: [512]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, format, args) catch {
            const alloc_formatted = try std.fmt.allocPrint(self.list.allocator, format, args);
            defer self.list.allocator.free(alloc_formatted);
            try self.list.appendSlice(alloc_formatted);
            return;
        };
        try self.list.appendSlice(formatted);
    }
};

pub fn renderEditor(editor: *Editor) !void {
    editor.render_buf.clearRetainingCapacity();
    var w = BufWriter{ .list = &editor.render_buf };

    const ws = editor.term.getWindowSize();
    const term_cols: usize = if (ws.cols > 0) @as(usize, ws.cols) else 80;

    if (editor.first_render and editor.prompt_prefix.len > 0) {
        try w.writeAll(editor.prompt_prefix);
        editor.first_render = false;
    }

    try w.writeAll("\x1b[?25l");
    try w.writeAll("\r\x1b[2K");

    if (editor.in_isearch) {
        try w.print("(reverse-i-search)`{s}': {s}", .{ editor.isearch_query.items, editor.buffer.items });
        if (editor.rendered_menu_rows > 0) {
            try writeClearMenu(&w, editor.rendered_menu_rows);
            editor.rendered_menu_rows = 0;
        }

        try w.writeAll("\r");
        var prefix_buf: [256]u8 = undefined;
        const prefix_str = std.fmt.bufPrint(&prefix_buf, "(reverse-i-search)`{s}': ", .{editor.isearch_query.items}) catch "(reverse-i-search)`': ";
        const prefix_vis_w = getVisibleWidth(prefix_str);

        var match_vis_offset: usize = 0;
        if (editor.isearch_query.items.len > 0) {
            if (std.mem.indexOf(u8, editor.buffer.items, editor.isearch_query.items)) |idx| {
                match_vis_offset = getVisibleWidth(editor.buffer.items[0..idx]);
            }
        }
        const total_offset = prefix_vis_w + match_vis_offset;
        if (total_offset > 0) {
            try w.print("\x1b[{d}C", .{total_offset});
        }
        try w.writeAll("\x1b[?25h");
        terminal.writeAll(editor.term.tty_fd, editor.render_buf.items);
        return;
    }

    try w.writeAll(editor.prompt_last_line);
    try w.writeAll(editor.buffer.items);

    if (editor.ghost_suggestion) |sugg| {
        try w.print("\x1b[38;5;244m{s}\x1b[0m", .{sugg});
    }

    var vis_rows: usize = 0;
    if (editor.in_completion and editor.candidates.items.len > 0) {
        const max_w = getMaxCandidateWidth(editor.candidates.items);
        const layout = MenuLayout.calculate(editor.candidates.items.len, max_w, term_cols);
        vis_rows = layout.vis_rows;

        const cur_row = editor.selected_candidate / layout.num_cols;
        var start_row: usize = 0;
        if (cur_row >= vis_rows) {
            start_row = cur_row - vis_rows + 1;
        }

        var r: usize = start_row;
        var drawn_lines: usize = 0;
        while (r < start_row + vis_rows and r < layout.total_rows) : (r += 1) {
            try w.writeAll("\n\r\x1b[2K");
            drawn_lines += 1;
            var c: usize = 0;
            while (c < layout.num_cols) : (c += 1) {
                const idx = r * layout.num_cols + c;
                if (idx < editor.candidates.items.len) {
                    const item = editor.candidates.items[idx];
                    const is_selected = (idx == editor.selected_candidate);
                    const is_dir = (item.len > 0 and item[item.len - 1] == '/');

                    if (is_selected) {
                        try w.writeAll("\x1b[7m");
                    } else if (is_dir) {
                        try w.writeAll("\x1b[1;34m");
                    }

                    const item_vw = getVisibleWidth(item);
                    if (item_vw > layout.col_w - 1 and layout.col_w >= 3) {
                        var trunc_bytes: usize = 0;
                        var cur_w: usize = 0;
                        while (trunc_bytes < item.len and cur_w + 2 < layout.col_w) {
                            const b = item[trunc_bytes];
                            const slen = std.unicode.utf8ByteSequenceLength(b) catch 1;
                            if (trunc_bytes + slen > item.len) break;
                            cur_w += if (isFullWidth(std.unicode.utf8Decode(item[trunc_bytes .. trunc_bytes + slen]) catch 0)) 2 else 1;
                            trunc_bytes += slen;
                        }
                        try w.writeAll(item[0..trunc_bytes]);
                        try w.writeAll("…");
                        if (layout.col_w > cur_w + 2) {
                            var pad = (layout.col_w - 1) - (cur_w + 1);
                            while (pad > 0) : (pad -= 1) try w.writeAll(" ");
                        }
                    } else {
                        try w.writeAll(item);
                        if (layout.col_w > item_vw + 1) {
                            var pad = (layout.col_w - 1) - item_vw;
                            while (pad > 0) : (pad -= 1) try w.writeAll(" ");
                        }
                    }

                    try w.writeAll("\x1b[0m ");
                }
            }
        }

        if (drawn_lines > 0) {
            try w.print("\x1b[{d}A", .{drawn_lines});
        }
    } else if (editor.rendered_menu_rows > 0) {
        try writeClearMenu(&w, editor.rendered_menu_rows);
    }
    editor.rendered_menu_rows = vis_rows;

    try w.writeAll("\r");
    const prompt_vis_w = getVisibleWidth(editor.prompt_last_line);
    const buf_vis_w = getVisibleWidth(editor.buffer.items[0..editor.cursor_pos]);
    const total_offset = prompt_vis_w + buf_vis_w;
    if (total_offset > 0) {
        try w.print("\x1b[{d}C", .{total_offset});
    }

    try w.writeAll("\x1b[?25h");
    terminal.writeAll(editor.term.tty_fd, editor.render_buf.items);
}
