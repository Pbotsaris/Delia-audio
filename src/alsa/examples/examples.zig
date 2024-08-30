const std = @import("std");
const alsa = @import("../alsa.zig");

pub fn selectingAudioCardAndSupportedSettings() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    // hardware holds information about your system's audio cards and ports
    var hardware = alsa.Hardware.init(allocator) catch |err| {
        std.debug.print("Failed to initialize hardware: {}", .{err});
        return;
    };

    defer hardware.deinit();

    // To have an overview of the available audio cards, ports as well as their supported settings
    // you can just print the hardware object
    //std.debug.print("{s}", .{hardware});
    //
    //  For every card and port there is a hint on how to select an specific card or port. We will use those.
    //     ├──  Select Methods:
    //     │    │  hardware.selectPortAt(.playback, 0)
    //     │    │  card.selectPlaybackAt(0)
    //     │    └──
    //

    hardware.selectAudioCardAt(0) catch |err| std.debug.print("Failed to select audio card: {}", .{err});
    hardware.selectAudioPortAt(.playback, 0) catch |err| std.debug.print("Failed to select audio port: {}", .{err});

    // hardware will fail to select if the setting is not supported by the hardware
    hardware.setSelectedFormat(.signed_16bits_little_endian) catch |err| {
        std.debug.print("Format settings not supported: {}", .{err});
    };

    hardware.setSelectedChannelCount(.stereo) catch |err| {
        std.debug.print("Channel settings not supported: {}", .{err});
    };

    hardware.setSelectedSampleRate(.sr_44Khz) catch |err| {
        std.debug.print("Sample rate settings not supported: {}", .{err});
    };

    // now you can initialize the device knowing that your settings are supported
    // if you don't set the settings above, the device will be initialized with the default settings

    var device = alsa.Device.fromHardware(hardware) catch |err| {
        std.debug.print("Failed to init device: {}", .{err});
        return;
    };

    defer device.deinit() catch |err| {
        std.debug.print("Failed to deinit device: {}", .{err});
    };

    //printing the devices format for an overview
    std.debug.print("{s}", .{device});

    // Prepare the device for playback with the minimum available strategy
    device.prepare(.min_available) catch |err| {
        std.debug.print("Failed to prepare device: {}", .{err});
    };
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
