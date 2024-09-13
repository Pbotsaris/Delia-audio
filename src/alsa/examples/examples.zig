const std = @import("std");
const alsa = @import("../alsa.zig");

// providing the format at comptime type will allow operation on device to be type safe
const Device = alsa.device.GenericDevice(.signed_16bits_little_endian);

// testing with a simple sine wave
var phase: f64 = 0.0;

fn callback(data: Device.AudioDataType()) void {
    const freq: f64 = 400.0;
    const amp: f64 = @as(f64, @floatFromInt(Device.maxFormatSize())) * 0.001;
    const sr: f64 = @floatFromInt(data.sample_rate);
    const phase_inc: f64 = 2.0 * std.math.pi * freq / sr;
    const nb_samples = data.bufferSize() * data.channels;

    for (0..nb_samples) |_| {
        const sample = switch (data.T) {
            f32, f64 => @as(data.T, @floatCast(amp * std.math.sin(phase))),
            else => @as(data.T, @intFromFloat(amp * std.math.sin(phase))),
        };

        for (0..data.channels) |_| {
            data.writeSample(sample) catch {
                return;
            };
        }

        phase += phase_inc;

        if (phase >= 2.0 * std.math.pi) {
            phase -= 2.0 * std.math.pi;
        }
    }
}

pub fn creatingDevice() void {
    var dev = Device.init(.{
        .sample_rate = .sr_44k100hz,
        .channels = .stereo,
        .stream_type = .playback,
        .buffer_size = .bz_1024,
        .ident = "hw:0,0",
    }) catch |err| {
        std.debug.print("Failed to init device: {any}", .{err});
        return;
    };

    dev.prepare(.min_available) catch |err| {
        std.debug.print("Failed to prepare device: {any}", .{err});
    };

    dev.start(callback) catch |err| {
        std.debug.print("Failed to start device: {any}", .{err});
    };
}

// This example shows how to use the hardware object to initialize a device
//pub fn usingHardwareToInitDevice() void {
//    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});
//
//    const allocator = gpa.allocator();
//
//    // hardware holds information about your system's audio cards and ports
//    var hardware = alsa.Hardware.init(allocator) catch |err| {
//        std.debug.print("Failed to initialize hardware: {}", .{err});
//        return;
//    };
//
//    defer hardware.deinit();
//
//    // To have an overview of the available audio cards, ports as well as their supported settings
//    // you can just print the hardware object
//    //
//    //  std.debug.print("{s}", .{hardware});
//    //
//    //  For every card and port there is a hint on how to select an specific card or port. We will use those.
//    //     ├──  Select Methods:
//    //     │    │  hardware.selectPortAt(.playback, 0)
//    //     │    │  card.selectPlaybackAt(0)
//    //     │    └──
//    //
//
//    hardware.selectAudioCardAt(0) catch |err| std.debug.print("Failed to select audio card: {}", .{err});
//    hardware.selectAudioPortAt(.playback, 0) catch |err| std.debug.print("Failed to select audio port: {}", .{err});
//
//    hardware.setSelectedFormat(.signed_16bits_little_endian) catch |err| {
//        std.debug.print("Format settings not supported: {}", .{err});
//        // hardware will fail to select if the setting is not supported by the hardware
//    };
//
//    hardware.setSelectedChannelCount(.stereo) catch |err| {
//        std.debug.print("Channel settings not supported: {}", .{err});
//    };
//
//    hardware.setSelectedSampleRate(.sr_44Khz) catch |err| {
//        std.debug.print("Sample rate settings not supported: {}", .{err});
//    };
//    // now you can initialize the device knowing that your settings are supported
//    //  The hardware object will provide the basic info to initialize the device
//    //  but it is possible to configure the device with more options.
//    //  Below an example of setting the buffer size and access type
//    var device = alsa.Device.fromHardware(hardware, .{ .buffer_size = .bz_1024, .access_type = .mmap_interleaved }) catch |err| {
//        std.debug.print("Failed to init device: {}", .{err});
//        return;
//    };
//
//    defer device.deinit() catch |err| {
//        std.debug.print("Failed to deinit device: {}", .{err});
//    };
//
//    //printing the devices format for an overview
//    std.debug.print("{s}", .{device});
//
//    // Prepare the device for playback with the minimum available strategy
//    device.prepare(.min_available) catch |err| {
//        std.debug.print("Failed to prepare device: {}", .{err});
//    };
//}

// This example shows how to manually use your hardware information to initialize a device
//pub fn manuallyInitializingDevice() void {
//    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});
//
//    const allocator = gpa.allocator();
//
//    // hardware holds information about your system's audio cards and ports
//    var hardware = alsa.Hardware.init(allocator) catch |err| {
//        std.debug.print("Failed to initialize hardware: {}", .{err});
//        return;
//    };
//
//    defer hardware.deinit();
//
//    // grab the first audio card and the first playback port
//    const card = hardware.getAudioCardByIdent("hw:0") catch |err| {
//        std.debug.print("Failed to get audio card: {}", .{err});
//        return;
//    };
//    const playback = card.getPlaybackAt(0) catch |err| {
//        std.debug.print("Failed to get playback port: {}", .{err});
//        return;
//    };
//
//    // you can check the supported settings for the card and port
//    // playback.supported_settings.?.formats
//    // playback.supported_settings.?.channels
//    // playback.supported_settings.?.sample_rates
//
//    // device will fail if settings are not supported by the hardware
//    var device = alsa.Device.init(.{
//        // you must provide sample rate, chnanels, format and steam type.
//        .sample_rate = .sr_44k100hz,
//        .channels = .stereo,
//        .stream_type = .playback,
//        .audio_format = .signed_16bits_little_endian,
//        .ident = playback.identifier,
//    }) catch |err| {
//        std.debug.print("Failed to init device: {}", .{err});
//        return;
//    };
//
//    defer device.deinit() catch |err| {
//        std.debug.print("Failed to deinit device: {}", .{err});
//    };
//
//    std.debug.print("{s}", .{device});
//
//    device.prepare(.min_available) catch |err| {
//        std.debug.print("Failed to prepare device: {}", .{err});
//    };
//}
