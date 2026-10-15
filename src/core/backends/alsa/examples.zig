//! Backend-only examples: a device, a Ctx and a callback, no graph.
//! after a run; opening `null` versus `hw:` and comparing `negotiated` with the request.
//! Graph playback lives in `src/examples.zig`.
const std = @import("std");
const buffer = @import("core/buffer");
const device = @import("device.zig");
const dsp = @import("dsp");
const SampleRate = @import("core/common").audio_specs.SampleRate;
const examples = @import("core/common").examples;

const log = std.log.scoped(.alsa);
const Wave = dsp.waves.Wave(f32);

const requested_rate: SampleRate = .sr_48000;

/// Runnable from `zig build example -- alsa <name> [args...]`.
pub const commands = [_]examples.Command{
    .{ .name = "playback-sine", .usage = "[ident=default] [seconds=2]", .run = runPlaybackSine },
};

pub fn runPlaybackSine(args: []const [:0]const u8) anyerror!void {
    const ident: [:0]const u8 = if (args.len > 0) args[0] else "default";
    const secs: f32 = if (args.len > 1) try std.fmt.parseFloat(f32, args[1]) else 2.0;

    try playbackSine(ident, secs);
}

/// Everything the callback needs, owned by the caller. The device only sees `*SineContext`.
const SineContext = struct {
    wave: Wave,
    frames_left: usize, // stop after this many frames
    device: *Device,

    fn render(self: *SineContext, out: buffer.AudioBlock(f32)) void {
        const first_block = self.wave.sine(out.getSamples(0));

        // copy the first channel to all other channels
        for (1..out.channel_count) |ch| @memcpy(out.getSamples(ch), first_block);

        // stop() only sets an atomic flag, so it is fine to call from the callback
        self.frames_left -|= out.frame_count;
        if (self.frames_left == 0) self.device.stop();
    }
};

const Device = device.PlaybackDevice(SineContext, .s16_le);

/// Plays a 440 Hz sine for `seconds` on `ident` and logs what the device did.
fn playbackSine(ident: [:0]const u8, seconds: f32) !void {
    const allocator = std.heap.page_allocator;

    var dev = try Device.init(.{
        .ident = ident,
        .sample_rate = requested_rate,
        .channel_count = 2,
        .period_frames = 512,
    });

    defer dev.deinit(allocator);

    // the config the hardware agreed to. Must be a supported by core/common/audio_specs.zig
    const config = dev.negotiatedConfig();

    const sample_rate = config.sample_rate.toFloat(f32);

    if (config.sample_rate != requested_rate) {
        log.warn("asked for {d} Hz, got {d}", .{ requested_rate.toUsize(), config.sample_rate.toUsize() });
    }

    var ctx = SineContext{
        .wave = Wave.init(440, 0.2, sample_rate), // (freq, amp, sample rate)
        .frames_left = @intFromFloat(seconds * sample_rate),
        .device = &dev,
    };

    try dev.prepare(allocator);
    try dev.start(&ctx, SineContext.render); // blocks until render calls stop()

    const stats = dev.getStats();

    log.info("{d} periods, {d} blocks, {d} xruns, {d} discontinuities", .{
        stats.periods, stats.blocks, stats.xruns, stats.discontinuities,
    });
}
