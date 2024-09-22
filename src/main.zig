const std = @import("std");
const alsa = @import("alsa/alsa.zig");
const examples = @import("alsa/examples/examples.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};
const log = std.log.scoped(.main);

pub fn main() !void {
    // examples.printingHardwareInfo();
    examples.playbackSineWave();
}

test {
    std.testing.refAllDeclsRecursive(alsa);
}
