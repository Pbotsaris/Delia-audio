const std = @import("std");
const alsa = @import("../alsa.zig");

pub fn selectingAudioCardAndSupportedSettings() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    // hardware holds information about your system's audio cards and ports
    var hardware = alsa.Hardware.init(allocator) catch |err| {
        std.debug.print("Failed to init hardware: {}", .{err});
        return;
    };

    defer hardware.deinit();

    // you first need to select a audio card and port.
    // You can check what is available by printing the hardware struct
    std.debug.print("{s}", .{hardware});

    hardware.selectAudioCardAt(0) catch |err| std.debug.print("Failed to select audio card: {}", .{err});
    hardware.selectAudioPortAt(.playback, 0) catch |err| std.debug.print("Failed to select audio port: {}", .{err});
}

pub fn providing() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    // hardware holds information about your system's audio cards and ports
    var hardware = try alsa.Hardware.init(allocator);
    defer hardware.deinit();

    // more options and low level control
    const card = try hardware.getAudioCardByIdent("hw:0");
    const playback = try card.getPlaybackAt(0);

    std.debug.print("{s}", .{playback});

    var device = try alsa.Device.init(.{
        .sample_rate = .sr_44Khz,
        .channels = .stereo,
        .stream_type = .playback,
        .format = .signed_16bits_little_endian,
        .mode = .none,
        .ident = playback.identifier,
    });

    //std.debug.print("{s}", .{device.format});

    try device.prepare(.min_available);
    try device.deinit();
}
