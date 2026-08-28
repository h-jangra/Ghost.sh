const std = @import("std");
const posix = std.posix;
const Term = @import("terminal.zig").Term;

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
    shift_tab,
    enter,
    escape,
    alt_f,
    alt_b,
    alt_d,
    ctrl_a,
    ctrl_b,
    ctrl_c,
    ctrl_d,
    ctrl_e,
    ctrl_f,
    ctrl_g,
    ctrl_k,
    ctrl_l,
    ctrl_r,
    ctrl_t,
    ctrl_u,
    ctrl_w,
    ctrl_x_e,
    paste_start,
    paste_end,
    unknown,
};

pub fn readKey(term: *const Term) Key {
    var b0_buf: [1]u8 = undefined;
    const n = posix.read(term.tty_fd, &b0_buf) catch return .unknown;
    if (n == 0) return .unknown;

    const b0 = b0_buf[0];
    if (b0 == 0x1b) {
        const b1 = term.readByte(100) orelse return .escape;
        if (b1 == '[' or b1 == 'O') {
            const b2 = term.readByte(100) orelse return .escape;
            if (b2 == 'A') return .up;
            if (b2 == 'B') return .down;
            if (b2 == 'C') return .right;
            if (b2 == 'D') return .left;
            if (b2 == 'H') return .home;
            if (b2 == 'F') return .end;
            if (b2 == 'Z') return .shift_tab;

            if (b2 >= '1' and b2 <= '9') {
                const b3 = term.readByte(100) orelse return .escape;
                if (b3 == '~') {
                    if (b2 == '1') return .home;
                    if (b2 == '3') return .delete;
                    if (b2 == '4') return .end;
                    if (b2 == '7') return .home;
                    if (b2 == '8') return .end;
                } else if (b3 == ';') {
                    const b4 = term.readByte(100) orelse return .escape;
                    const b5 = term.readByte(100) orelse return .escape;
                    if (b4 == '5' or b4 == '3') {
                        if (b5 == 'C') return .alt_f;
                        if (b5 == 'D') return .alt_b;
                        if (b5 == 'A') return .up;
                        if (b5 == 'B') return .down;
                    }
                } else if (b2 == '2' and (b3 == '0' or b3 == '1')) {
                    const b4 = term.readByte(100) orelse return .escape;
                    const b5 = term.readByte(100) orelse return .escape;
                    if (b3 == '0' and b4 == '0' and b5 == '~') return .paste_start;
                    if (b3 == '0' and b4 == '1' and b5 == '~') return .paste_end;
                }
            } else if (b2 == '5') {
                const b3 = term.readByte(100) orelse return .escape;
                if (b3 == 'C') return .alt_f;
                if (b3 == 'D') return .alt_b;
            }
            return .escape;
        } else if (b1 == 'f' or b1 == 'F') {
            return .alt_f;
        } else if (b1 == 'b' or b1 == 'B') {
            return .alt_b;
        } else if (b1 == 'd' or b1 == 'D') {
            return .alt_d;
        } else if (b1 == 127 or b1 == 8) {
            return .ctrl_w;
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
        7 => .ctrl_g,
        8 => .backspace,
        9 => .tab,
        10, 13 => .enter,
        11 => .ctrl_k,
        12 => .ctrl_l,
        14 => .down,
        16 => .up,
        18 => .ctrl_r,
        20 => .ctrl_t,
        21 => .ctrl_u,
        23 => .ctrl_w,
        24 => blk: {
            if (term.readByte(200)) |next_b| {
                if (next_b == 5 or next_b == 'e' or next_b == 'E') {
                    break :blk .ctrl_x_e;
                }
            }
            break :blk .unknown;
        },
        127 => .backspace,
        else => blk: {
            if (b0 >= 32 and b0 < 127) {
                break :blk Key{ .char = b0 };
            }
            if (b0 >= 0x80) {
                const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch break :blk .unknown;
                var utf8_buf: [4]u8 = undefined;
                utf8_buf[0] = b0;
                var i: usize = 1;
                while (i < seq_len) : (i += 1) {
                    const next_b = term.readByte(100) orelse break :blk .unknown;
                    utf8_buf[i] = next_b;
                }
                const cp = std.unicode.utf8Decode(utf8_buf[0..seq_len]) catch break :blk .unknown;
                break :blk Key{ .char = cp };
            }
            break :blk .unknown;
        },
    };
}
