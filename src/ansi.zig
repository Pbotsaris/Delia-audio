const std = @import("std");
const ANSI = @This();

pub const reset = "\x1b[0m";

pub const Text = struct {
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";
    pub const blink = "\x1b[5m";
    pub const reverse = "\x1b[7m";
    pub const hidden = "\x1b[8m";
    pub const strikethrough = "\x1b[9m";
};

pub const Color = struct {
    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
};

pub const Background = struct {
    pub const black = "\x1b[40m";
    pub const red = "\x1b[41m";
    pub const green = "\x1b[42m";
    pub const yellow = "\x1b[43m";
    pub const blue = "\x1b[44m";
    pub const magenta = "\x1b[45m";
    pub const cyan = "\x1b[46m";
    pub const white = "\x1b[47m";
};

pub inline fn logColor(comptime log_scope: std.log.Level) []const u8 {
    switch (log_scope) {
        std.log.Level.err => return Color.red,
        std.log.Level.warn => return Color.yellow,
        std.log.Level.info => return Color.blue,
        std.log.Level.debug => return Color.white,
    }
}
