const std = @import("std");
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
    alt_dot,
    alt_underscore,
    alt_caret,
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

pub fn readKey(term: *Term) Key {
    const b0 = term.readByte(-1) orelse return .unknown;

    if (b0 == 0x1b) {
        const b1 = term.readByte(20) orelse return .escape;
        if (b1 == '[' or b1 == 'O') {
            const b2 = term.readByte(20) orelse return .escape;
            return switch (b2) {
                'A' => .up,
                'B' => .down,
                'C' => .right,
                'D' => .left,
                'H' => .home,
                'F' => .end,
                'Z' => .shift_tab,
                '1'...'9' => blk: {
                    const b3 = term.readByte(20) orelse break :blk .escape;
                    if (b3 == '~') {
                        break :blk switch (b2) {
                            '1', '7' => .home,
                            '3' => .delete,
                            '4', '8' => .end,
                            else => .escape,
                        };
                    } else if (b3 == ';') {
                        const b4 = term.readByte(20) orelse break :blk .escape;
                        const b5 = term.readByte(20) orelse break :blk .escape;
                        if (b4 == '5' or b4 == '3') {
                            break :blk switch (b5) {
                                'C' => .alt_f,
                                'D' => .alt_b,
                                'A' => .up,
                                'B' => .down,
                                else => .escape,
                            };
                        }
                    } else if (b2 == '2' and (b3 == '0' or b3 == '1')) {
                        const b4 = term.readByte(20) orelse break :blk .escape;
                        const b5 = term.readByte(20) orelse break :blk .escape;
                        if (b3 == '0' and b4 == '0' and b5 == '~') break :blk .paste_start;
                        if (b3 == '0' and b4 == '1' and b5 == '~') break :blk .paste_end;
                    } else if (b2 == '5') {
                        if (b3 == 'C') break :blk .alt_f;
                        if (b3 == 'D') break :blk .alt_b;
                    }
                    break :blk .escape;
                },
                else => .escape,
            };
        }
        return switch (std.ascii.toLower(b1)) {
            'f' => .alt_f,
            'b' => .alt_b,
            'd' => .alt_d,
            '.', '>' => .alt_dot,
            '_', '-' => .alt_underscore,
            '^' => .alt_caret,
            8, 127 => .ctrl_w,
            else => .escape,
        };
    }

    return switch (b0) {
        1 => .ctrl_a,
        2 => .ctrl_b,
        3 => .ctrl_c,
        4 => .ctrl_d,
        5 => .ctrl_e,
        6 => .ctrl_f,
        7 => .ctrl_g,
        8, 127 => .backspace,
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
            if (term.readByte(100)) |next_b| {
                if (next_b == 5 or next_b == 'e' or next_b == 'E') break :blk .ctrl_x_e;
            }
            break :blk .unknown;
        },
        32...126 => .{ .char = b0 },
        else => blk: {
            if (b0 >= 0x80) {
                const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch break :blk .unknown;
                var utf8_buf: [4]u8 = undefined;
                utf8_buf[0] = b0;
                var i: usize = 1;
                while (i < seq_len) : (i += 1) {
                    utf8_buf[i] = term.readByte(20) orelse break :blk .unknown;
                }
                const cp = std.unicode.utf8Decode(utf8_buf[0..seq_len]) catch break :blk .unknown;
                break :blk .{ .char = cp };
            }
            break :blk .unknown;
        },
    };
}
