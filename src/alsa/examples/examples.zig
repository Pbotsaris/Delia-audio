const std = @import("std");
const alsa = @import("../alsa.zig");
const wave = @import("../../dsp/waves.zig");

// TODO: Please check this code still runs

// providing the format at comptime type will allow operation on device to be type safe
const Device = alsa.device.GenericDevice(.signed_16bits_little_endian);

const PlaybackContext = struct {
    const Self = @This();
    w: wave.Wave(f32).init(100.0, 0.2, 48000.0),

    fn callback(self: *Self, data: Device.AudioDataType()) void {
        self.w.setSampleRate(@floatFromInt(data.sample_rate));

        for (0..data.totalSampleCount()) |_| {
            const sample = self.w.sineSample();

            for (0..data.channels) |_| {
                data.writeSample(sample) catch {
                    return;
                };
            }
        }
    }
};

pub fn playbackSineWave() void {
    var dev = Device.init(.{
        .sample_rate = .sr_44100,
        .channels = .stereo,
        .stream_type = .playback,
        .buffer_size = .bz_512,
        .ident = "hw:3,0",
    }) catch |err| {
        std.debug.print("Failed to init device: {any}", .{err});
        return;
    };

    dev.prepare(.min_available) catch |err| {
        std.debug.print("Failed to prepare device: {any}", .{err});
    };

    var ctx = PlaybackContext{ .w = wave.Wave(f32).init(100.0, 0.2, 48000.0) };

    dev.start(&ctx, ctx.callback) catch |err| {
        std.debug.print("Failed to start device: {any}", .{err});
    };
}

pub fn printingHardwareInfo() void {
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
    std.debug.print("{s}", .{hardware});
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
