//! Backend-only examples: a device, a Ctx and a callback, no graph. 
//! after a run; opening `null` versus `hw:` and comparing `negotiated` with the request.
//! Graph playback lives in `src/examples.zig`.
const std = @import("std");
const buffer = @import("core/buffer");
const device = @import("device.zig");
const dsp = @import("dsp");

const log = std.log.scoped(.alsa);
const Wave = dsp.waves.Wave(f32);

const sample_rate: u32 = 48000;

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
pub fn playbackSine(ident: [:0]const u8, seconds: f32) !void {
    const allocator = std.heap.page_allocator;

    var dev = try Device.init(.{
        .ident = ident,
        .sample_rate = sample_rate,
        .channel_count = 2,
        .period_frames = 512,
    });
    defer dev.deinit(allocator);

    // the rate the hardware agreed to, not the one asked for: the wave's increment depends on it
    const config = dev.negotiatedConfig();

    if (config.sample_rate != sample_rate) log.warn("asked for 48000 Hz, got {d}", .{config.sample_rate});

    var ctx = SineContext{
        .wave = Wave.init(440, 0.2, @floatFromInt(sample_rate)), // (freq, amp, sample rate)
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
