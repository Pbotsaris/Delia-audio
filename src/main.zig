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

    const card = try hardware.getCardAt(1);
    const playback = try card.getPlayback(0);

    std.debug.print("{s}", .{playback});

    var device = try alsa.Device.init(.{
        .sample_rate = .sr_44Khz,
        .channels = .stereo,
        .stream_type = .playback,
        .format = .signed_16bits_little_endian,
        .mode = .none,
        .ident = playback.identifier,
    });

    std.debug.print("{s}", .{device.format});

    try device.prepare(.min_available);
    try device.deinit();
}
