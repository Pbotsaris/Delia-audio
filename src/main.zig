const std = @import("std");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

pub fn main() !void {
    log.info("Hello, {s}!", .{"world"});
    log.warn("Hello, {s}!", .{"world"});
    log.err("Hello, {s}!", .{"world"});
    log.debug("Hello, {s}!", .{"world"});
}
