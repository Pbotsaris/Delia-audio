const std = @import("std");
const alsa = @import("alsa/alsa.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

pub fn main() !void {
    var device = try alsa.Device.init(.{
        .sample_rate = 44100,
        .channels = 2,
        .stream_type = alsa.Device.StreamType.playback,
        .mode = alsa.Device.MODE_NONE,
    });

    try device.deinit();
}
