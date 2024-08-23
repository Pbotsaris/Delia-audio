const std = @import("std");
const alsa = @import("alsa/alsa.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) log.err("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    var hardware = try alsa.Hardware.init(allocator);
    defer hardware.deinit();

    const card = try hardware.getCard(0);
    const playback = try card.getPlayback(0);

    var device = try alsa.Device.init(.{
        .sample_rate = 44100,
        .channels = 2,
        .stream_type = alsa.Device.StreamType.playback,
        .mode = alsa.Device.MODE_NONE,
        .handler_name = playback.handler,
    });

    try device.deinit();
}
