const std = @import("std");
const posix = std.posix;

const terminal = @import("terminal.zig");
const Term = terminal.Term;
const input = @import("input.zig");
const Key = input.Key;
const editor_mod = @import("editor.zig");
const Editor = editor_mod.Editor;
const render = @import("render.zig");
const MenuLayout = render.MenuLayout;

fn cancelLine(editor: *Editor) !void {
    editor.cleanMenu();
    editor.buffer.clearRetainingCapacity();
    editor.cursor_pos = 0;
    editor.hist_index = null;
    editor.ghost_suggestion = null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();

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
    terminal.global_term_ptr = &term;
    defer terminal.global_term_ptr = null;

    const sa_int = posix.Sigaction{
        .handler = .{ .handler = terminal.sigintHandler },
        .mask = posix.empty_sigset,
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sa_int, null);
    const sa_term = posix.Sigaction{
        .handler = .{ .handler = terminal.sigtermHandler },
        .mask = posix.empty_sigset,
        .flags = 0,
    };
    posix.sigaction(posix.SIG.TERM, &sa_term, null);

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
    try render.renderEditor(&editor);

    var exit_code: u8 = 0;
    var accepted = false;

    while (true) {
        const key = input.readKey(&term);

        if (editor.in_paste) {
            switch (key) {
                .paste_end => {
                    editor.in_paste = false;
                },
                .char => |cp| {
                    try editor.insertChar(cp);
                },
                .enter => {
                    try editor.insertSlice("\n");
                },
                .tab => {
                    try editor.insertSlice("\t");
                },
                else => {},
            }
            if (!editor.in_paste) {
                editor.updateGhost();
                try render.renderEditor(&editor);
            }
            continue;
        }

        if (editor.in_isearch) {
            switch (key) {
                .ctrl_r => {
                    editor.isearchNextMatch();
                },
                .backspace => {
                    editor.isearchDeleteBackward();
                },
                .char => |cp| {
                    try editor.isearchInsertChar(cp);
                },
                .enter => {
                    editor.acceptIsearch();
                    accepted = true;
                    break;
                },
                .escape, .ctrl_c, .ctrl_g => {
                    editor.cancelIsearch();
                },
                else => {
                    editor.acceptIsearch();
                },
            }
            editor.updateGhost();
            try render.renderEditor(&editor);
            continue;
        }

        if (editor.in_completion) {
            const total = editor.candidates.items.len;
            const ws = term.getWindowSize();
            const cols: usize = if (ws.cols > 0) @as(usize, ws.cols) else 80;
            const layout = MenuLayout.calculate(total, render.getMaxCandidateWidth(editor.candidates.items), cols);

            switch (key) {
                .tab, .right => {
                    editor.selected_candidate = (editor.selected_candidate + 1) % total;
                },
                .shift_tab, .left => {
                    editor.selected_candidate = (editor.selected_candidate + total - 1) % total;
                },
                .down => {
                    if (editor.selected_candidate + layout.num_cols < total) {
                        editor.selected_candidate += layout.num_cols;
                    } else {
                        editor.selected_candidate = (editor.selected_candidate + 1) % total;
                    }
                },
                .up => {
                    if (editor.selected_candidate >= layout.num_cols) {
                        editor.selected_candidate -= layout.num_cols;
                    } else {
                        editor.selected_candidate = (editor.selected_candidate + total - 1) % total;
                    }
                },
                .enter => {
                    editor.applySelectedCompletion(true);
                    editor.in_completion = false;
                },
                .escape, .ctrl_c => {
                    editor.in_completion = false;
                },
                .paste_start => {
                    editor.in_completion = false;
                    editor.in_paste = true;
                    continue;
                },
                .char => |cp| {
                    editor.applySelectedCompletion(false);
                    editor.in_completion = false;
                    try editor.insertChar(cp);
                },
                else => {
                    editor.in_completion = false;
                },
            }
            editor.updateGhost();
            try render.renderEditor(&editor);
            continue;
        }

        switch (key) {
            .paste_start => {
                editor.in_paste = true;
                continue;
            },
            .paste_end => {
                editor.in_paste = false;
            },
            .char => |cp| try editor.insertChar(cp),
            .backspace => editor.deleteBackward(),
            .delete => editor.deleteForward(),
            .left, .ctrl_b => editor.moveCursorLeft(),
            .right, .ctrl_f => editor.moveCursorRight(),
            .alt_f => editor.moveWordForward(),
            .alt_b => editor.moveWordBackward(),
            .alt_d => editor.killWordForward(),
            .ctrl_t => editor.transposeChars(),
            .home, .ctrl_a => editor.cursor_pos = 0,
            .end, .ctrl_e => editor.moveCursorEnd(),
            .ctrl_w => editor.killWordBackward(),
            .ctrl_u => editor.killLineToStart(),
            .ctrl_k => editor.killLineToEnd(),
            .ctrl_l => try editor.clearScreen(),
            .ctrl_r => {
                _ = try editor.historySearchInteractive();
            },
            .up => editor.historyUp(),
            .down => editor.historyDown(),
            .tab, .shift_tab => {
                editor.collectCompletions();
                if (editor.candidates.items.len == 1) {
                    editor.selected_candidate = 0;
                    editor.applySelectedCompletion(true);
                } else if (editor.candidates.items.len > 1) {
                    const total = editor.candidates.items.len;
                    const ws = term.getWindowSize();
                    const cols: usize = if (ws.cols > 0) @as(usize, ws.cols) else 80;
                    const layout = MenuLayout.calculate(total, render.getMaxCandidateWidth(editor.candidates.items), cols);

                    if (!editor.in_completion and layout.vis_rows > 0) {
                        var pre_scroll: usize = 0;
                        while (pre_scroll < layout.vis_rows) : (pre_scroll += 1) {
                            _ = posix.write(term.tty_fd, "\n") catch {};
                        }
                        var up_buf: [32]u8 = undefined;
                        const up_seq = std.fmt.bufPrint(&up_buf, "\x1b[{d}A", .{layout.vis_rows}) catch "";
                        _ = posix.write(term.tty_fd, up_seq) catch {};
                    }

                    editor.in_completion = true;
                    editor.selected_candidate = 0;
                }
            },
            .enter => {
                accepted = true;
                break;
            },
            .ctrl_c => {
                try cancelLine(&editor);
            },
            .ctrl_d => {
                if (editor.buffer.items.len == 0) {
                    exit_code = 1;
                    break;
                } else {
                    editor.deleteForward();
                }
            },
            .ctrl_x_e => {
                if (try editor.editAndExecute()) {
                    accepted = true;
                    break;
                }
            },
            .escape => {},
            else => {},
        }

        editor.updateGhost();
        try render.renderEditor(&editor);
    }

    editor.cleanMenu();
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
