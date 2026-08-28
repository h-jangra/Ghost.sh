const std = @import("std");
const posix = std.posix;

pub var global_term_ptr: ?*Term = null;

pub fn sigintHandler(_: c_int) callconv(.C) void {
    if (global_term_ptr) |t| t.deinit();
    std.posix.exit(130);
}

pub fn sigtermHandler(_: c_int) callconv(.C) void {
    if (global_term_ptr) |t| t.deinit();
    std.posix.exit(143);
}

pub const Term = struct {
    orig_termios: posix.termios,
    raw_active: bool = false,
    tty_fd: posix.fd_t,
    owns_fd: bool = false,

    pub fn init() !Term {
        const rc = posix.system.open("/dev/tty", posix.system.O{ .ACCMODE = .RDWR }, 0);
        var fd: posix.fd_t = posix.STDIN_FILENO;
        var owns = false;
        if (posix.errno(rc) == .SUCCESS) {
            fd = @intCast(rc);
            owns = true;
        }
        const orig = try posix.tcgetattr(fd);
        return Term{
            .orig_termios = orig,
            .raw_active = false,
            .tty_fd = fd,
            .owns_fd = owns,
        };
    }

    pub fn deinit(self: *Term) void {
        self.disableRaw();
        _ = posix.write(self.tty_fd, "\x1b[?2004l\x1b[?25h") catch {};
        if (self.owns_fd) {
            posix.close(self.tty_fd);
            self.owns_fd = false;
        }
    }

    pub fn enableRaw(self: *Term) !void {
        if (self.raw_active) return;
        var raw = self.orig_termios;

        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;

        raw.oflag.OPOST = true;
        raw.cflag.CSIZE = .CS8;

        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;

        raw.cc[@intFromEnum(posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(posix.V.TIME)] = 0;

        try posix.tcsetattr(self.tty_fd, .FLUSH, raw);
        self.raw_active = true;
        _ = posix.write(self.tty_fd, "\x1b[?2004h") catch {};
    }

    pub fn disableRaw(self: *Term) void {
        if (!self.raw_active) return;
        _ = posix.write(self.tty_fd, "\x1b[?2004l\x1b[?25h") catch {};
        posix.tcsetattr(self.tty_fd, .FLUSH, self.orig_termios) catch {};
        self.raw_active = false;
    }

    pub fn suspendRaw(self: *Term) void {
        _ = posix.write(self.tty_fd, "\r\x1b[2K") catch {};
        self.disableRaw();
    }

    pub fn resumeRaw(self: *Term) !void {
        try self.enableRaw();
    }

    pub fn getWindowSize(self: *const Term) struct { rows: u16, cols: u16 } {
        var ws: posix.winsize = undefined;
        const rc = posix.system.ioctl(self.tty_fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (rc == 0 and ws.col > 0) {
            return .{ .rows = ws.row, .cols = ws.col };
        }
        return .{ .rows = 24, .cols = 80 };
    }

    pub fn readByte(self: *const Term, timeout_ms: i32) ?u8 {
        var pfd = [1]posix.pollfd{.{
            .fd = self.tty_fd,
            .events = posix.POLL.IN,
            .revents = 0,
        }};
        const ready = posix.poll(&pfd, timeout_ms) catch return null;
        if (ready <= 0) return null;

        var b: [1]u8 = undefined;
        const n = posix.read(self.tty_fd, &b) catch return null;
        if (n == 0) return null;
        return b[0];
    }
};
