const std = @import("std");
const alsa = @import("../alsa.zig");
const wave = @import("../../../dsp/waves.zig");

const log = std.log.scoped(.alsa);

// TODO: Please check this code still runs

// providing the format and the context in which you callback will ruin from
// at comptime type will allow operation on device to be type safe
const Device = alsa.device.HalfDuplexDevice(.signed_16bits_little_endian, PlaybackContext);

const PlaybackContext = struct {
    const Self = @This();
    w: wave.Wave(f32) = wave.Wave(f32).init(100.0, 0.2, 48000.0),

    pub fn callback(self: *Self, data: Device.AudioDataType()) void {
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    var dev = Device.init(allocator, .{
        .sample_rate = .sr_44100,
        .channels = .quad,
        .stream_type = .playback,
        .buffer_size = .buf_512,
        .ident = "hw:3,0",
    }) catch |err| {
        log.err("Failed to init device: {}", .{err});
        return;
    };

    defer dev.deinit() catch |err| {
        log.err("Failed to deinit device: {}", .{err});
    };

    dev.prepare(.min_available) catch |err| {
        log.err("Failed to prepare device: {}", .{err});
    };

    var ctx = PlaybackContext{ .w = wave.Wave(f32).init(100.0, 0.2, 48000.0) };

    dev.start(&ctx, @field(PlaybackContext, "callback")) catch |err| {
        log.err("Failed to start device: {}", .{err});
    };
}

pub fn printingHardwareInfo() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    // hardware holds information about your system's audio cards and ports
    var hardware = alsa.Hardware.init(allocator) catch |err| {
        log.err("Failed to start device: {}", .{err});
        return;
    };

    defer hardware.deinit();

    // To have an overview of the available audio cards, ports as well as their supported settings
    // you can just print the hardware object
    std.debug.print("{s}", .{hardware});
}

pub fn findAndPrintCardPortInfo(card_name: []const u8) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    // hardware holds information about your system's audio cards and ports
    var hardware = alsa.Hardware.init(allocator) catch |err| {
        log.err("Failed to start device: {}", .{err});
        return;
    };

    defer hardware.deinit();

    const found_card = hardware.findCardBy(.name, card_name);

    if (found_card) |card| {
        std.debug.print("{s}", .{card});
        return;
    }

    std.debug.print("Card {s} not found", .{card_name});
}

pub fn findingCardAndPortBy() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    var hardware = alsa.Hardware.init(allocator) catch |err| {
        log.err("Failed to start device: {}", .{err});
        return;
    };

    defer hardware.deinit();

    const found_card = hardware.findCardBy(.name, "webcam");

    if (found_card) |card| {
        // webcams don't have playback ports, generally :)
        const found_port = card.findCaptureBy(.name, "USB");

        std.debug.print("{?}", .{found_port});
        return;
    }

    std.debug.print("Card not found", .{});
}

pub fn selectAudioPortCounterpart() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) log.err("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    var hardware = alsa.Hardware.init(allocator) catch |err| {
        log.err("Failed to initialize hardware: {}", .{err});
        return;
    };

    defer hardware.deinit();

    hardware.selectAudioCardBy(.name, "USB") catch |err| {
        log.err("Failed to select audio card: {}", .{err});
        return;
    };

    hardware.selectAudioPortBy(.playback, .name, "USB Audio #1") catch |err| {
        log.err("Failed to select audio port: {}", .{err});
        return;
    };
    const port = hardware.getSelectedAudioPort() catch |err| {
        log.err("Failed to get selected port: {}", .{err});
        return;
    };

    const counterpart = hardware.getSelectedAudioPortCounterpart() catch |err| {
        log.err("Failed to get counterpart: {}", .{err});
        return;
    };

    std.debug.print("SELECTED PORT:\n{s}", .{port});
    std.debug.print("COUNTERPART PORT:\n{s}", .{counterpart});
}

//This example shows how to use the hardware object to initialize a device
pub fn usingHardwareToInitDevice() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) log.err("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    // hardware holds information about your system's audio cards and ports
    var hardware = alsa.Hardware.init(allocator) catch |err| {
        log.err("Failed to initialize hardware: {}", .{err});
        return;
    };

    defer hardware.deinit();

    // To have an overview of the available audio cards, ports as well as their supported settings
    // you can just print the hardware object
    //
    //  std.debug.print("{s}", .{hardware});
    //
    //  For every card and port there is a hint on how to select an specific card or port. We will use those.
    //     ├──  Select Methods:
    //     │    │  hardware.selectPortAt(.playback, 0)
    //     │    │  card.selectPlaybackAt(0)
    //     │    └──
    //

    // select the audio card and port you want to use

    // by index
    // hardware.selectAudioCardAt(3) catch |err| {
    //     log.err("Failed to select audio card: {}", .{err});
    //     return;
    // };

    // or by name / alsa id. Harware attempts to match the name with the card's name or id
    // Replace "Audio" with the name of your card
    hardware.selectAudioCardBy(.name, "Audio") catch |err| {
        log.err("Failed to select audio card: {}", .{err});
        return;
    };

    // by index
    // hardware.selectAudioPortAt(.playback, 0) catch |err| {
    //     log.err("Failed to select audio port: {}", .{err});
    //     return;
    // };

    // or again by name / alsa id. Note that this function will return the first match
    // For my audio Card for Example the Ports are all called USB Audio #1, USB Audio #2, etc
    //  So I need to be specific
    //  Replace "USB Audio #1" with the name of your port
    hardware.selectAudioPortBy(.playback, .name, "USB Audio #1") catch |err| {
        log.err("Failed to select audio port: {}", .{err});
        return;
    };

    hardware.setSelectedFormat(.signed_16bits_little_endian) catch |err| {
        // hardware will fail to select if the setting is not supported by the hardware
        log.err("Format settings not supported: {}", .{err});
        return;
    };

    hardware.setSelectedChannelCount(.stereo) catch |err| {
        log.err("Channel settings not supported: {}", .{err});
        return;
    };

    hardware.setSelectedSampleRate(.sr_44100) catch |err| {
        log.err("Sample rate settings not supported: {}", .{err});
        return;
    };

    // now you can initialize the device knowing that your settings are supported
    //  The hardware object will provide the basic info to initialize the device
    //  but it is possible to configure the device with more options.
    //  Below an example of setting the buffer size and access type
    var device = Device.fromHardware(allocator, hardware, .{ .buffer_size = .buf_1024 }) catch |err| {
        log.err("Failed to init device: {}", .{err});
        return;
    };

    defer device.deinit() catch |err| {
        log.err("Failed to deinit device: {}", .{err});
    };

    //printing the devices format for an overview
    std.debug.print("{s}", .{device});

    // Prepare the device for playback with the minimum available strategy
    device.prepare(.min_available) catch |err| {
        std.debug.print("Failed to prepare device: {}", .{err});
        return;
    };
}

// This example shows how to manually use your hardware information to initialize a device
pub fn manuallyInitializingDevice() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.debug.print("Failed to deinit allocator.", .{});

    const allocator = gpa.allocator();

    // hardware holds information about your system's audio cards and ports
    var hardware = alsa.Hardware.init(allocator) catch |err| {
        std.debug.print("Failed to initialize hardware: {}", .{err});
        return;
    };

    defer hardware.deinit();

    // grab the first audio card and the first playback port
    const card = hardware.getAudioCardByIdent("hw:0") catch |err| {
        std.debug.print("Failed to get audio card: {}", .{err});
        return;
    };
    const playback = card.getPlaybackAt(0) catch |err| {
        std.debug.print("Failed to get playback port: {}", .{err});
        return;
    };

    // you can check the supported settings for the card and port
    // playback.supported_settings.?.formats
    // playback.supported_settings.?.channels
    // playback.supported_settings.?.sample_rates

    // device will fail if settings are not supported by the hardware
    var device = Device.init(allocator, .{
        // you must provide sample rate, chnanels, format and steam type.
        .sample_rate = .sr_44100,
        .channels = .stereo,
        .stream_type = .playback,
        .ident = playback.identifier,
    }) catch |err| {
        std.debug.print("Failed to init device: {}", .{err});
        return;
    };

    defer device.deinit() catch |err| {
        std.debug.print("Failed to deinit device: {}", .{err});
    };

    std.debug.print("{s}", .{device});

    device.prepare(.min_available) catch |err| {
        std.debug.print("Failed to prepare device: {}", .{err});
    };
}
