const std = @import("std");
const buffer = @import("core/buffer");
const SampleRate = @import("core/common").audio_specs.SampleRate;
const c = @import("pcm.zig").c;

const SampleFormat = @import("convert.zig").SampleFormat;
const SampleConverter = @import("convert.zig").SampleConverter;
const PlaybackLoop = @import("loop.zig").PlaybackLoop;
const LoopError = @import("loop.zig").LoopError;
const LoopStats = @import("loop.zig").Stats;
const AlsaPcm = @import("pcm.zig").Alsa;

pub const DeviceError = error{
    open_failed,
    prepare_failed,
    hw_params_invalid,
    area_geometry_invalid,
    sw_params_invalid,
    access_unsupported, // only MMAP_INTERLEAVED for now
    format_unsupported,
    rate_unsupported, // the hardware refused the rate, or negotiated one that is not a `SampleRate`
    channels_unsupported,
    period_changed, // the hardware moved period or buffer size away from the request
    not_prepared, // start() before prepare()
} || std.mem.Allocator.Error;
const RealtimeError = DeviceError || LoopError;


pub const DeviceOptions = struct {
    ident: [:0]const u8 = "default",
    sample_rate: SampleRate,
    channel_count: u32,
    period_frames: usize,
    n_periods: u32 = 2,
    timeout_ms: u32 = 100,
};

/// What the hardware actually agreed to. The plan is compiled against these, not the request.
pub const NegotiatedConfig = struct {
    sample_rate: SampleRate, // may differ from the request, but is always a listed rate
    channel_count: u32,
    period_frames: usize,
    buffer_frames: usize,
};

pub fn PlaybackDevice(comptime Ctx: type, comptime fmt: SampleFormat) type {
    return struct {
        const Self = @This();
        pub const Loop = PlaybackLoop(Ctx, AlsaPcm, fmt);
        pub const Callback = Loop.Callback;
        const Converter = SampleConverter(fmt);

        const alsa_format: c.snd_pcm_format_t = switch (fmt) {
            .s16_le => c.SND_PCM_FORMAT_S16_LE,
            .f32_le => c.SND_PCM_FORMAT_FLOAT_LE,
        };

        handle: *c.snd_pcm_t,
        config: NegotiatedConfig,
        timeout_ms: u32,
        pcm: AlsaPcm,
        loop: ?Loop = null, // set by prepare

        /// Open and negotiate hardware parameters. Allocates nothing of ours; alsa-lib's
        /// hw_params struct is freed before returning, only the negotiated values are kept.
        pub fn init(opts: DeviceOptions) DeviceError!Self {
            var maybe_handle: ?*c.snd_pcm_t = null;

            if (c.snd_pcm_open(&maybe_handle, opts.ident.ptr, c.SND_PCM_STREAM_PLAYBACK, 0) < 0) return DeviceError.open_failed;
            const handle = maybe_handle orelse return DeviceError.open_failed;

            // any error we just close the device
            errdefer _ = c.snd_pcm_close(handle);

            var maybe_params: ?*c.snd_pcm_hw_params_t = null;

            if (c.snd_pcm_hw_params_malloc(&maybe_params) < 0) return DeviceError.hw_params_invalid;
            const params = maybe_params orelse return DeviceError.hw_params_invalid;
            defer c.snd_pcm_hw_params_free(params);

            if (c.snd_pcm_hw_params_any(handle, params) < 0) return DeviceError.hw_params_invalid;

            // negotiation table, contract section 3: M4a implements row 4 only
            if (c.snd_pcm_hw_params_set_access(handle, params, c.SND_PCM_ACCESS_MMAP_INTERLEAVED) < 0) return DeviceError.access_unsupported;
            if (c.snd_pcm_hw_params_set_format(handle, params, alsa_format) < 0) return DeviceError.format_unsupported;
            if (c.snd_pcm_hw_params_set_channels(handle, params, opts.channel_count) < 0) return DeviceError.channels_unsupported;

            var rate: c_uint = @intCast(opts.sample_rate.toUsize());
            var dir: c_int = 0;
            if (c.snd_pcm_hw_params_set_rate_near(handle, params, &rate, &dir) < 0) return DeviceError.rate_unsupported;

            var period: c.snd_pcm_uframes_t = opts.period_frames;
            var buffer_frames: c.snd_pcm_uframes_t = opts.period_frames * opts.n_periods;
            if (c.snd_pcm_hw_params_set_period_size_near(handle, params, &period, &dir) < 0) return DeviceError.period_changed;
            if (c.snd_pcm_hw_params_set_buffer_size_near(handle, params, &buffer_frames) < 0) return DeviceError.period_changed;

            if (c.snd_pcm_hw_params(handle, params) < 0) return DeviceError.hw_params_invalid;

            // read back what was set; `_near` may have moved any of these
            if (c.snd_pcm_hw_params_get_period_size(params, &period, &dir) < 0) return DeviceError.hw_params_invalid;
            if (c.snd_pcm_hw_params_get_buffer_size(params, &buffer_frames) < 0) return DeviceError.hw_params_invalid;
            if (c.snd_pcm_hw_params_get_rate(params, &rate, &dir) < 0) return DeviceError.hw_params_invalid;

            // the period is the loop's unit and the staging capacity: a different one is an error.
            if (period != opts.period_frames or buffer_frames != opts.period_frames * opts.n_periods) return DeviceError.period_changed;

            // A different listed rate is not an error: the caller builds its DSP against
            // `negotiatedConfig().sample_rate`. An unlisted one (some cards answer 44056) is.
            const negotiated_rate = std.enums.fromInt(SampleRate, rate) orelse return DeviceError.rate_unsupported;

            return .{
                .handle = handle,
                .config = .{ .sample_rate = negotiated_rate, .channel_count = opts.channel_count, .period_frames = period, .buffer_frames = buffer_frames },
                .timeout_ms = opts.timeout_ms,
                .pcm = .{ .handle = handle, .bytes_per_frame = opts.channel_count * Converter.bytes_per_sample },
            };
        }

        pub fn negotiatedConfig(self: *const Self) NegotiatedConfig {
            return self.config;
        }

        pub fn prepare(self: *Self, allocator: std.mem.Allocator) DeviceError!void {
            // re-prepare after a failed start drops the old staging first
            if (self.loop) |*loop| loop.deinit(allocator);

            self.loop = null;

            var maybe_sw: ?*c.snd_pcm_sw_params_t = null;

            if (c.snd_pcm_sw_params_malloc(&maybe_sw) < 0) return DeviceError.sw_params_invalid;
            const sw = maybe_sw orelse return DeviceError.sw_params_invalid;
            defer c.snd_pcm_sw_params_free(sw);

            const neg = self.config;

            if (c.snd_pcm_sw_params_current(self.handle, sw) < 0) return DeviceError.sw_params_invalid;

            // wake when one period is free; the loop starts the stream itself, so the start
            // threshold is "never": buffer_frames + 1 disables automatic start
            if (c.snd_pcm_sw_params_set_avail_min(self.handle, sw, neg.period_frames) < 0) return DeviceError.sw_params_invalid;
            if (c.snd_pcm_sw_params_set_start_threshold(self.handle, sw, neg.buffer_frames + 1) < 0) return DeviceError.sw_params_invalid;
            if (c.snd_pcm_sw_params_set_stop_threshold(self.handle, sw, neg.buffer_frames) < 0) return DeviceError.sw_params_invalid;
            // the legacy driver set all of the above and never applied them (driver.zig:525-533)
            if (c.snd_pcm_sw_params(self.handle, sw) < 0) return DeviceError.sw_params_invalid;

            if (c.snd_pcm_prepare(self.handle) < 0) return DeviceError.prepare_failed;

            // validate area geometry once, here, not per period
            const area = self.pcm.inspectArea() catch return DeviceError.area_geometry_invalid;
            if (area.first % 8 != 0 or area.step % 8 != 0) return DeviceError.area_geometry_invalid;
            if (area.step / 8 != self.pcm.bytes_per_frame) return DeviceError.area_geometry_invalid;

            // staging is `channels x period_frames`; a shape error here means the negotiated
            // values are unusable, which is a hw_params problem, not a loop one
            self.loop = Loop.init(allocator, &self.pcm, .{
                .channel_count = neg.channel_count,
                .period_frames = neg.period_frames,
                .timeout_ms = self.timeout_ms,
            }) catch |err| return switch (err) {
                error.OutOfMemory => DeviceError.OutOfMemory,
                else => DeviceError.hw_params_invalid,
            };
        }

        /// Runs the loop on the calling thread until `stop()` or an unrecoverable error.
        pub fn start(self: *Self, ctx: *Ctx, callback: Callback) RealtimeError!void {
            // capture by pointer: the loop holds the running flag that stop() flips
            const loop = if (self.loop) |*loop| loop else return DeviceError.not_prepared;
            return loop.start(ctx, callback);
        }

        pub fn stop(self: *Self) void {
            if (self.loop) |*loop| loop.stop();
        }

        pub fn getStats(self: *const Self) LoopStats {
            return if (self.loop) |*loop| loop.stats else .{};
        }

        /// After stop. Drops pending frames.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (self.loop) |*loop| loop.deinit(allocator);
            _ = c.snd_pcm_drop(self.handle);
            _ = c.snd_pcm_close(self.handle);
            self.* = undefined;
        }
    };
}

// Forces analysis of the generic body above; the hardware path is exercised by src/examples.zig.
test "PlaybackDevice instantiates" {
    const Ctx = struct {
        const Self = @This();

        fn cb(_: *Self, _: buffer.AudioBlock(f32)) void {}
    };
    std.testing.refAllDecls(PlaybackDevice(Ctx, .s16_le));
    std.testing.refAllDecls(PlaybackDevice(Ctx, .f32_le));
}

// The whole open/negotiate/prepare/render/stop/close path on ALSA's `null` plugin, which every
// machine with alsa-lib has. It accepts any format and geometry, so these check the plumbing
// through the real `Alsa` seam (state, start, wait, begin/commit), not hardware timing: `null`
// consumes frames as fast as they are committed. Timing is the `hw:` run in src/examples.zig.

/// Stops the device itself after `stop_after` frames (0: never, something else stops it).
const NullCtx = struct {
    calls: usize = 0,
    frames: usize = 0,
    stop_after: usize = 0,
    device: *PlaybackDevice(NullCtx, .s16_le) = undefined,

    fn cb(self: *NullCtx, out: buffer.AudioBlock(f32)) void {
        self.calls += 1;
        // atomic: a stopper thread polls `frames` (only this thread writes it)
        @atomicStore(usize, &self.frames, self.frames + out.frame_count, .release);
        for (0..out.channel_count) |ch| @memset(out.getSamples(ch), 0.25);
        if (self.stop_after > 0 and self.frames >= self.stop_after) self.device.stop();
    }
};

const NullDevice = PlaybackDevice(NullCtx, .s16_le);
const null_options: DeviceOptions = .{ .ident = "null", .sample_rate = .sr_48000, .channel_count = 2, .period_frames = 512 };

test "PlaybackDevice renders periods on the null device" {
    var device = try NullDevice.init(null_options);
    defer device.deinit(std.testing.allocator);
    try device.prepare(std.testing.allocator);

    // prepare leaves the stream prepared; the loop, not the start threshold, starts it
    try std.testing.expectEqual(.prepared, device.pcm.state());

    var ctx = NullCtx{ .device = &device, .stop_after = 4 * 512 };
    try device.start(&ctx, NullCtx.cb);

    try std.testing.expectEqual(.running, device.pcm.state());
    try std.testing.expect(ctx.frames >= 4 * 512);

    const stats = device.getStats();
    try std.testing.expectEqual(ctx.calls, stats.blocks);
    try std.testing.expectEqual(0, stats.xruns);
    try std.testing.expectEqual(0, stats.discontinuities);
    try std.testing.expectEqual(0, stats.short_commits);
    try std.testing.expectEqual(0, stats.zero_transfers);
}

test "PlaybackDevice: stop() from another thread ends start() on the null device" {
    var device = try NullDevice.init(null_options);
    defer device.deinit(std.testing.allocator);
    try device.prepare(std.testing.allocator);

    const Stopper = struct {
        fn run(dev: *NullDevice, ctx: *const NullCtx) void {
            // let it render a few periods first, so stop() lands mid-run, not before start()
            while (@atomicLoad(usize, &ctx.frames, .acquire) < 8 * 512) std.atomic.spinLoopHint();
            dev.stop();
        }
    };

    var ctx = NullCtx{ .device = &device };
    const thread = try std.Thread.spawn(.{}, Stopper.run, .{ &device, &ctx });
    try device.start(&ctx, NullCtx.cb);
    thread.join();

    try std.testing.expect(ctx.frames >= 8 * 512);
    try std.testing.expectEqual(0, device.getStats().xruns);
}

test "PlaybackDevice: stop() before start() runs no periods on the null device" {
    var device = try NullDevice.init(null_options);
    defer device.deinit(std.testing.allocator);
    try device.prepare(std.testing.allocator);

    var ctx = NullCtx{ .device = &device };
    device.stop();
    try device.start(&ctx, NullCtx.cb);

    try std.testing.expectEqual(0, ctx.calls);
    try std.testing.expectEqual(0, device.getStats().periods);
    try std.testing.expectEqual(.prepared, device.pcm.state()); // never started
}

test "PlaybackDevice: start() again after stop() renders again (stop is consumed)" {
    var device = try NullDevice.init(null_options);
    defer device.deinit(std.testing.allocator);
    try device.prepare(std.testing.allocator);

    var ctx = NullCtx{ .device = &device, .stop_after = 2 * 512 };
    try device.start(&ctx, NullCtx.cb);
    const first = ctx.frames;

    ctx.stop_after = first + 2 * 512;
    try device.start(&ctx, NullCtx.cb);

    try std.testing.expect(ctx.frames >= first + 2 * 512);
    try std.testing.expectEqual(0, device.getStats().xruns);
}

test "PlaybackDevice: the negotiated rate is a SampleRate" {
    // `null` accepts any rate, so the request comes back unchanged. The unlisted-rate rejection
    // (`rate_unsupported` from `std.enums.fromInt`) needs a card that moves the rate.
    var device = try NullDevice.init(.{ .ident = "null", .sample_rate = .sr_44100, .channel_count = 2, .period_frames = 512 });
    defer device.deinit(std.testing.allocator);

    try std.testing.expectEqual(SampleRate.sr_44100, device.negotiatedConfig().sample_rate);
}
