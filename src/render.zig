const std = @import("std");
const terminal = @import("terminal.zig");
const Editor = @import("editor.zig").Editor;
const ArrayList = @import("editor.zig").ArrayList;

pub const MenuLayout = struct {
    col_w: usize,
    num_cols: usize,
    vis_rows: usize,
    total_rows: usize,

    pub fn calculate(candidates_len: usize, max_candidate_len: usize, term_cols: usize) MenuLayout {
        const col_w = @min(@max(max_candidate_len + 2, 12), term_cols);
        const num_cols = @max(if (term_cols >= col_w) term_cols / col_w else 1, 1);
        const total_rows = (candidates_len + num_cols - 1) / num_cols;
        return .{
            .col_w = col_w,
            .num_cols = num_cols,
            .vis_rows = @min(total_rows, 5),
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
    var last_line = s;
    if (std.mem.lastIndexOfScalar(u8, s, '\n')) |idx| last_line = s[idx + 1 ..];
    if (std.mem.lastIndexOfScalar(u8, last_line, '\r')) |idx| last_line = last_line[idx + 1 ..];

    var w: usize = 0;
    var i: usize = 0;
    while (i < last_line.len) {
        if (last_line[i] == 0x1b) {
            i += 1;
            if (i < last_line.len and (last_line[i] == '[' or last_line[i] == ']')) {
                i += 1;
                while (i < last_line.len and !((last_line[i] >= 'a' and last_line[i] <= 'z') or (last_line[i] >= 'A' and last_line[i] <= 'Z') or last_line[i] == '\x07')) : (i += 1) {}
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
            if (b >= 32 and b != 127) w += 1;
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

pub fn appendFmt(list: *ArrayList(u8), comptime format: []const u8, args: anytype) !void {
    var buf: [512]u8 = undefined;
    if (std.fmt.bufPrint(&buf, format, args)) |formatted| {
        try list.appendSlice(formatted);
    } else |_| {
        const alloc_formatted = try std.fmt.allocPrint(list.allocator, format, args);
        defer list.allocator.free(alloc_formatted);
        try list.appendSlice(alloc_formatted);
    }
}

pub fn writeClearMenu(list: *ArrayList(u8), rows: usize) !void {
    if (rows == 0) return;
    var r: usize = 0;
    while (r < rows) : (r += 1) try list.appendSlice("\n\r\x1b[2K");
    try appendFmt(list, "\x1b[{d}A", .{rows});
}

pub fn getMaxCandidateWidth(candidates: []const []const u8) usize {
    var max_len: usize = 0;
    for (candidates) |c| {
        const cw = getVisibleWidth(c);
        if (cw > max_len) max_len = cw;
    }
    return max_len;
}

pub fn renderEditor(editor: *Editor) !void {
    editor.render_buf.clearRetainingCapacity();
    const buf = &editor.render_buf;

    const ws = editor.term.getWindowSize();
    const term_cols: usize = if (ws.cols > 0) ws.cols else 80;

    if (editor.first_render and editor.prompt_prefix.len > 0) {
        try buf.appendSlice(editor.prompt_prefix);
        editor.first_render = false;
    }

    try buf.appendSlice("\x1b[?25l\r\x1b[2K");

    if (editor.in_isearch) {
        try appendFmt(buf, "(reverse-i-search)`{s}': {s}", .{ editor.isearch_query.items, editor.buffer.items });
        if (editor.rendered_menu_rows > 0) {
            try writeClearMenu(buf, editor.rendered_menu_rows);
            editor.rendered_menu_rows = 0;
        }

        try buf.appendSlice("\r");
        var prefix_buf: [256]u8 = undefined;
        const prefix_str = std.fmt.bufPrint(&prefix_buf, "(reverse-i-search)`{s}': ", .{editor.isearch_query.items}) catch "(reverse-i-search)`': ";
        var total_offset = getVisibleWidth(prefix_str);
        if (editor.isearch_query.items.len > 0) {
            if (std.mem.indexOf(u8, editor.buffer.items, editor.isearch_query.items)) |idx| {
                total_offset += getVisibleWidth(editor.buffer.items[0..idx]);
            }
        }
        if (total_offset > 0) try appendFmt(buf, "\x1b[{d}C", .{total_offset});
        try buf.appendSlice("\x1b[?25h");
        terminal.writeAll(editor.term.tty_fd, buf.items);
        return;
    }

    try buf.appendSlice(editor.prompt_last_line);
    try buf.appendSlice(editor.buffer.items);

    if (editor.ghost_suggestion) |sugg| {
        try appendFmt(buf, "\x1b[38;5;244m{s}\x1b[0m", .{sugg});
    }

    var vis_rows: usize = 0;
    if (editor.in_completion and editor.candidates.items.len > 0) {
        const max_w = if (editor.max_candidate_width > 0) editor.max_candidate_width else getMaxCandidateWidth(editor.candidates.items);
        const layout = MenuLayout.calculate(editor.candidates.items.len, max_w, term_cols);
        vis_rows = layout.vis_rows;

        const cur_row = editor.selected_candidate / layout.num_cols;
        const start_row = if (cur_row >= vis_rows) cur_row - vis_rows + 1 else 0;

        var r = start_row;
        var drawn_lines: usize = 0;
        while (r < start_row + vis_rows and r < layout.total_rows) : (r += 1) {
            try buf.appendSlice("\n\r\x1b[2K");
            drawn_lines += 1;
            var c: usize = 0;
            while (c < layout.num_cols) : (c += 1) {
                const idx = r * layout.num_cols + c;
                if (idx < editor.candidates.items.len) {
                    const item = editor.candidates.items[idx];
                    const is_selected = (idx == editor.selected_candidate);
                    const is_dir = (item.len > 0 and item[item.len - 1] == '/');

                    if (is_selected) {
                        try buf.appendSlice("\x1b[7m");
                    } else if (is_dir) {
                        try buf.appendSlice("\x1b[1;34m");
                    }

                    const item_vw = getVisibleWidth(item);
                    if (item_vw > layout.col_w - 1 and layout.col_w >= 3) {
                        var trunc_bytes: usize = 0;
                        var cur_w: usize = 0;
                        while (trunc_bytes < item.len and cur_w + 2 < layout.col_w) {
                            const slen = std.unicode.utf8ByteSequenceLength(item[trunc_bytes]) catch 1;
                            if (trunc_bytes + slen > item.len) break;
                            cur_w += if (isFullWidth(std.unicode.utf8Decode(item[trunc_bytes .. trunc_bytes + slen]) catch 0)) 2 else 1;
                            trunc_bytes += slen;
                        }
                        try buf.appendSlice(item[0..trunc_bytes]);
                        try buf.appendSlice("…");
                        if (layout.col_w > cur_w + 2) {
                            var pad = (layout.col_w - 1) - (cur_w + 1);
                            while (pad > 0) : (pad -= 1) try buf.append(' ');
                        }
                    } else {
                        try buf.appendSlice(item);
                        if (layout.col_w > item_vw + 1) {
                            var pad = (layout.col_w - 1) - item_vw;
                            while (pad > 0) : (pad -= 1) try buf.append(' ');
                        }
                    }
                    try buf.appendSlice("\x1b[0m ");
                }
            }
        }

        if (drawn_lines > 0) try appendFmt(buf, "\x1b[{d}A", .{drawn_lines});
    } else if (editor.rendered_menu_rows > 0) {
        try writeClearMenu(buf, editor.rendered_menu_rows);
    }
    editor.rendered_menu_rows = vis_rows;

    try buf.appendSlice("\r");
    const total_offset = editor.prompt_vis_w + getVisibleWidth(editor.buffer.items[0..editor.cursor_pos]);
    if (total_offset > 0) try appendFmt(buf, "\x1b[{d}C", .{total_offset});

    try buf.appendSlice("\x1b[?25h");
    terminal.writeAll(editor.term.tty_fd, buf.items);
}

test "renderEditor with and without ghost suggestion" {
    const allocator = std.testing.allocator;
    const term = try terminal.Term.init();
    defer @constCast(&term).deinit();

    var ed = Editor.init(allocator, std.testing.io, std.process.Environ.empty, &term, "> ");
    defer ed.deinit();

    try ed.buffer.appendSlice("ll");
    ed.cursor_pos = ed.buffer.items.len;
    ed.ghost_suggestion = "c";

    try renderEditor(&ed);
    try std.testing.expect(std.mem.indexOf(u8, ed.render_buf.items, "\x1b[38;5;244mc\x1b[0m") != null);

    ed.ghost_suggestion = null;
    try renderEditor(&ed);
    try std.testing.expect(std.mem.indexOf(u8, ed.render_buf.items, "\x1b[38;5;244m") == null);
    try std.testing.expect(std.mem.indexOf(u8, ed.render_buf.items, "> ll") != null);
}
