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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) log.err("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    var a = try alsa.Alsa.init(allocator);
    defer a.deinit();
    const card = a.cards.items[0];
    const dev = card.playbacks.items[0];

    log.info("Card: {s}", .{card.details.name});
    log.info("Device: {s}", .{dev.name});
}
