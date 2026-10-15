const std = @import("std");
const buffer = @import("core/buffer");
const convert = @import("convert.zig");

pub const PcmError = @import("pcm.zig").PcmError;
pub const Region = @import("pcm.zig").Region;
pub const PcmState = @import("pcm.zig").State;

const AudioBlock = buffer.AudioBlock;
const OwnedAudioBuffer = buffer.OwnedAudioBuffer;

const SampleFormat = convert.SampleFormat;
const SampleConverter = convert.SampleConverter;

pub const LoopError = error{
    no_progress,
    failed_recovery,
} || PcmError;

pub const Stats = struct {
    periods: u64 = 0,
    blocks: u64 = 0,
    xruns: u64 = 0,
    discontinuities: u64 = 0,
    short_commits: u64 = 0,
    zero_transfers: u64 = 0,
};

pub const LoopOptions = struct {
    channel_count: usize,
    period_frames: usize,
    timeout_ms: u32 = 100, // finite: stop() must be observable
    max_zero_transfers: usize = 5,
};

pub fn PlaybackLoop(comptime Ctx: type, comptime Pcm: type, comptime fmt: SampleFormat) type {
    // How a transfer outcome is counted in `Stats`. What decides it is whether rendered audio was
    // lost, not whether a count is zero.
    //
    // | case                               | callback ran | frames lost | zero_transfers | short_commits | discontinuities |
    // |------------------------------------|--------------|-------------|----------------|---------------|-----------------|
    // | begin -> 0                         | no           | none        | +1             |               |                 |
    // | commit(n) -> 0                     | yes          | n           | +1             | +1            | +1              |
    // | commit(n) -> k, 0 < k < n          | yes          | n - k       |                | +1            | +1              |
    // | commit(0) -> 0 after a zero begin  | no           | none        | at begin       |               |                 |
    //
    // short_commits and discontinuities end the period without recovery:
    // the next availUpdate reports a real xrun.
    // A failed begin or commit (an error, not a count) recovers and counts a
    // discontinuity; xruns counts only what the device reported.

    return struct {
        const Self = @This();

        pub const Callback = *const fn (ctx: *Ctx, out: AudioBlock(f32)) void;
        const Converter = SampleConverter(fmt);

        pcm: *Pcm,
        staging: OwnedAudioBuffer(f32),
        opts: LoopOptions,
        running: std.atomic.Value(bool) = .init(false),
        stop_requested: std.atomic.Value(bool) = .init(false),
        stats: Stats = .{},

        /// Prepare: Only allocations and inits
        pub fn init(allocator: std.mem.Allocator, pcm: *Pcm, opts: LoopOptions) !Self {
            const staging_buffer = try OwnedAudioBuffer(f32).init(allocator, .{ .channel_count = opts.channel_count, .max_frames = opts.period_frames });

            return .{
                .pcm = pcm,
                .staging = staging_buffer,
                .opts = opts,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            // can only be called after stop() has been called and the loop has exited
            std.debug.assert(!self.running.load(.acquire));
            self.staging.deinit(allocator);
        }

        pub fn start(self: *Self, ctx: *Ctx, callback: Callback) LoopError!void {
            self.running.store(true, .release);

            defer {
                self.stop_requested.store(false, .release);
                self.running.store(false, .release);
            }

            while (!self.stop_requested.load(.acquire)) {
                try self.runPeriod(ctx, callback);
            }
        }

        pub fn stop(self: *Self) void {
            self.stop_requested.store(true, .release);
        }

        pub fn runPeriod(self: *Self, ctx: *Ctx, callback: Callback) LoopError!void {
            self.stats.periods += 1;

            var remaining: usize = self.opts.period_frames;
            var zero_progress: usize = 0;

            while (remaining > 0) {
                const avail = self.pcm.availUpdate() catch |err| return self.recover(err);

                switch (try self.waitPeriod(avail, remaining)) {
                    .ready => {},
                    .retry => continue,
                    .skip_period => return,
                }

                const region: Region = self.pcm.mmapBegin(remaining) catch |err| {
                    self.stats.discontinuities += 1;
                    return self.recover(err);
                };

                // mmapBegin should never grant more than was asked for; borrowBlock below relies on it
                std.debug.assert(region.frame_count <= remaining);

                if (region.frame_count == 0) {
                    zero_progress += 1;
                    self.stats.zero_transfers += 1;

                    if (zero_progress >= self.opts.max_zero_transfers) return LoopError.no_progress;

                    _ = self.pcm.mmapCommit(0) catch |err| return self.recover(err);
                    continue;
                }

                zero_progress = 0;

                // region.frame_count <= remaining <= period_frames == staging.max_frames; proved at prepare.
                const block = self.staging.borrowBlock(region.frame_count) catch unreachable;

                callback(ctx, block);
                self.stats.blocks += 1;

                const byte_len = Converter.byteLength(self.opts.channel_count, region.frame_count);

                Converter.writeInterleaved(region.bytes[0..byte_len], block.asConst()) catch unreachable;

                const committed_count = self.pcm.mmapCommit(region.frame_count) catch |err| {
                    self.stats.discontinuities += 1;
                    return self.recover(err);
                };

                // nothing commited
                if (committed_count == 0) self.stats.zero_transfers += 1;

                if (committed_count != region.frame_count) {
                    self.stats.short_commits += 1;
                    self.stats.discontinuities += 1;

                    // NOTE: we do not need to recover here?
                    // Nothing to do here; Let the next period call availUpdate recorver if needed.
                    return;
                }

                remaining -= committed_count;
            }
        }

        const Readiness = enum { ready, retry, skip_period };

        /// Readiness: the loop may wait here; the callback may not (plan 8.1).
        /// A stream that was just started, or that timed out waiting, has nothing to transfer: skip the period.
        fn waitPeriod(self: *Self, avail: usize, needed: usize) LoopError!Readiness {
            if (avail >= needed) return .ready;

            if (self.pcm.state() == .prepared) {
                try self.pcm.start();
                return .skip_period;
            }

            self.pcm.wait(self.opts.timeout_ms) catch |err| {
                try self.recover(err);
                return .skip_period;
            };

            return .retry;
        }

        fn recover(self: *Self, err: PcmError) LoopError!void {
            switch (err) {
                error.xrun, error.suspended => {
                    self.stats.xruns += 1;
                    self.pcm.recover(err) catch return error.failed_recovery;
                },

                error.timeout => {}, // stop() may have been called; the while in start() decides
                error.io => return error.io,
            }
        }
    };
}

// ===========================================================================
// Scripted tests: one per rule in docs/backend-contract.md section 4, plus the section 6 rules
// the loop owns. Tests named "gap:" fail against the M4a loop on purpose.
// ===========================================================================

const testing = std.testing;
const ScriptedPcm = @import("pcm.zig").ScriptedPcm;
const Step = ScriptedPcm.Step;

const test_channels = 2;
const test_period = 512;
const S16 = SampleConverter(.s16_le);

/// Renders frame index n as n / maxInt(i16) on every channel, so frame k on the wire decodes to
/// exactly the index of the rendered frame it came from: lost or re-rendered frames show up as a
/// jump in the sequence. Fixed storage, so the context allocates nothing.
const Counter = struct {
    calls: usize = 0,
    frames_seen: [64]usize = undefined,
    next_frame: usize = 0,

    fn render(self: *Counter, out: AudioBlock(f32)) void {
        if (self.calls < self.frames_seen.len) self.frames_seen[self.calls] = out.frame_count;
        self.calls += 1;

        for (0..out.frame_count) |n| {
            const index = (self.next_frame + n) % std.math.maxInt(i16);
            const value = @as(f32, @floatFromInt(index)) / std.math.maxInt(i16);
            for (0..out.channel_count) |ch| out.getSamples(ch)[n] = value;
        }
        self.next_frame += out.frame_count;
    }

    fn seen(self: *const Counter) []const usize {
        return self.frames_seen[0..@min(self.calls, self.frames_seen.len)];
    }
};

const TestLoop = PlaybackLoop(Counter, ScriptedPcm, .s16_le);

/// Initialised in place: the loop keeps a pointer to `pcm`.
const Harness = struct {
    allocator: std.mem.Allocator,
    pcm: ScriptedPcm,
    loop: TestLoop,
    ctx: Counter,

    const Options = struct {
        period_frames: usize = test_period,
        max_zero_transfers: usize = 5,
        call_budget: usize = std.math.maxInt(usize),
    };

    fn init(self: *Harness, allocator: std.mem.Allocator, script: []const Step, opts: Options) !void {
        self.allocator = allocator;
        self.ctx = .{};
        self.pcm = try ScriptedPcm.init(allocator, script, .{
            .channel_count = test_channels,
            .bytes_per_sample = S16.bytes_per_sample,
            .period_frames = opts.period_frames,
            .call_budget = opts.call_budget,
        });
        errdefer self.pcm.deinit(allocator);

        self.loop = try TestLoop.init(allocator, &self.pcm, .{
            .channel_count = test_channels,
            .period_frames = opts.period_frames,
            .max_zero_transfers = opts.max_zero_transfers,
        });
    }

    fn deinit(self: *Harness) void {
        self.loop.deinit(self.allocator);
        self.pcm.deinit(self.allocator);
    }

    fn period(self: *Harness) LoopError!void {
        return self.loop.runPeriod(&self.ctx, Counter.render);
    }

    fn wireFrames(self: *const Harness) usize {
        return self.pcm.wire().len / (test_channels * S16.bytes_per_sample);
    }

    /// Wire frames [wire_from, wire_from + count) carry rendered frames [rendered_from, ...) in order.
    fn expectWire(self: *const Harness, wire_from: usize, rendered_from: usize, count: usize) !void {
        const frame_bytes = test_channels * S16.bytes_per_sample;
        for (0..count) |k| {
            const frame = self.pcm.wire()[(wire_from + k) * frame_bytes ..][0..frame_bytes];
            for (0..test_channels) |ch| {
                const sample = std.mem.readInt(i16, frame[ch * S16.bytes_per_sample ..][0..2], .little);
                try testing.expectEqual(@as(i16, @intCast(rendered_from + k)), sample);
            }
        }
    }
};

test "prediction: blocks of 512, 300 and 212 frames equal one offline render of 1024" {
    const script = [_]Step{ .{ .begin_frames = 512 }, .{ .begin_frames = 300 }, .{ .begin_frames = 212 } };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period(); // 512
    try h.period(); // 300 + 212

    try testing.expectEqualSlices(usize, &.{ 512, 300, 212 }, h.ctx.seen());
    try testing.expectEqual(script.len, h.pcm.next_step);

    var offline = try OwnedAudioBuffer(f32).init(testing.allocator, .{ .channel_count = test_channels, .max_frames = 1024 });
    defer offline.deinit(testing.allocator);
    const block = try offline.borrowBlock(1024);
    var reference_ctx: Counter = .{};
    Counter.render(&reference_ctx, block);

    var reference: [S16.byteLength(test_channels, 1024)]u8 = undefined;
    try S16.writeInterleaved(&reference, block.asConst());

    try testing.expectEqualSlices(u8, &reference, h.pcm.wire());
    try testing.expectEqual(0, h.loop.stats.discontinuities);
}

test "short begin: the returned count sizes the callback and the commit" {
    const script = [_]Step{.{ .begin_frames = 300 }};
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();

    try testing.expectEqualSlices(usize, &.{ 300, 212 }, h.ctx.seen());
    try testing.expectEqual(test_period, h.pcm.committed_frames);
    try testing.expectEqual(0, h.loop.stats.short_commits);
    try h.expectWire(0, 0, test_period);
}

fn expectAvailBeforeEveryBegin(log: []const ScriptedPcm.Call) !void {
    for (log, 0..) |call, i| {
        if (call != .begin) continue;
        if (i == 0 or log[i - 1] != .avail) {
            std.debug.print("begin at call {d} follows {any}\ncall log: {any}\n", .{ i, if (i == 0) null else log[i - 1], log });
            return error.TestUnexpectedResult;
        }
    }
}

test "gap: availUpdate immediately before every begin, including after a short begin" {
    const script = [_]Step{.{ .begin_frames = 300 }};

    var h: Harness = undefined;

    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();
    try expectAvailBeforeEveryBegin(h.pcm.callLog());
}

test "gap: availUpdate immediately before begin after a wait" {
    // period 1: nothing free, stream prepared -> start, skip. period 2: 100 free -> wait.
    const script = [_]Step{ .{ .avail_frames = 0 }, .{ .avail_frames = 100 } };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();
    h.period() catch {}; // the early-wake test below owns the outcome; only the order matters here
    try expectAvailBeforeEveryBegin(h.pcm.callLog());
}

test "gap: an early wakeup with less than a period free is not zero progress" {
    const script = [_]Step{ .{ .avail_frames = 0 }, .{ .avail_frames = 100 } };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period(); // start
    try h.period(); // woke with 100 free; the device frees the rest as it plays

    try testing.expectEqual(0, h.loop.stats.zero_transfers);
    try testing.expectEqual(test_period, h.pcm.committed_frames);
    try h.expectWire(0, 0, test_period);
}

test "failed begin: callback not called, region untouched, recovery counted, next period proceeds" {
    const script = [_]Step{.{ .begin_fail = error.xrun }};
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();

    try testing.expectEqual(0, h.ctx.calls);
    try testing.expectEqual(1, h.pcm.recoveries);
    try testing.expectEqual(1, h.loop.stats.discontinuities);
    try testing.expectEqual(0, h.pcm.wire().len);
    for (h.pcm.ring) |b| try testing.expectEqual(0xAA, b); // nothing dereferenced a failed begin

    try h.period();

    try testing.expectEqual(1, h.ctx.calls);
    try h.expectWire(0, 0, test_period);
}

test "gap: short commit is a discontinuity, not an xrun, and lost frames are not re-rendered" {
    const script = [_]Step{.{ .commit_frames = 100 }};
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period(); // renders 512, device takes 100

    try testing.expectEqual(1, h.ctx.calls);
    try testing.expectEqual(1, h.loop.stats.short_commits);
    try testing.expectEqual(1, h.loop.stats.discontinuities);
    try h.expectWire(0, 0, 100);

    try h.period();

    // frames 100..512 are gone; the next period continues from 512
    try testing.expectEqual(2, h.ctx.calls);
    try h.expectWire(100, test_period, test_period);

    // the stream never left running: nothing to recover, nothing to call an xrun
    try testing.expectEqual(0, h.loop.stats.xruns);
    try testing.expectEqual(0, h.pcm.recoveries);
}

test "zero begins: no_progress after max_zero_transfers" {
    const script = [_]Step{ .{ .begin_frames = 0 }, .{ .begin_frames = 0 }, .{ .begin_frames = 0 } };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{ .max_zero_transfers = 3 });
    defer h.deinit();

    try testing.expectError(error.no_progress, h.period());
    try testing.expectEqual(3, h.loop.stats.zero_transfers);
    try testing.expectEqual(0, h.ctx.calls);
}

// Section 4 counts commit returning 0 as zero progress. Whether repeated ones also end in
// no_progress, and whether the block counts as a discontinuity too, is for the contract to say.
test "gap: commit returning 0 counts as a zero transfer" {
    const script = [_]Step{.{ .commit_frames = 0 }};
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    h.period() catch {};

    try testing.expectEqual(1, h.loop.stats.zero_transfers);
    try testing.expectEqual(1, h.ctx.calls); // the rendered block is lost, not rendered again
}

test "gap: a stream resumed after suspend is running and is not started again" {
    const script = [_]Step{
        .{ .avail_frames = 0 }, // period 1: prepared -> start
        .{ .avail_fail = error.suspended }, // period 2: suspend
        .{ .recover_to = .running }, // resume succeeded: no prepare, still running
        .{ .avail_frames = 100 }, // period 3: running with little free -> wait, not start
        .{ .wait_fail = error.timeout },
    };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();
    try h.period();
    try h.period();

    try testing.expectEqual(1, h.pcm.starts);
    try testing.expectEqual(1, h.loop.stats.xruns);
    try testing.expectEqual(script.len, h.pcm.next_step);
}

test "after an xrun the prepared stream is started again; staging is not cleared" {
    const script = [_]Step{
        .{ .avail_frames = 0 }, // period 1: start
        .{ .commit_fail = error.xrun }, // period 2: rendered, then xrun on commit
        .{ .avail_frames = 0 }, // period 3: recovered to prepared, nothing free -> start again
    };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();
    try h.period();

    try testing.expectEqual(1, h.loop.stats.xruns);
    try testing.expectEqual(1, h.loop.stats.discontinuities);
    try testing.expectEqual(1, h.pcm.recoveries);
    try testing.expectEqual(0, h.pcm.wire().len);
    // resetting audio is the engine's call (M5); the backend leaves the rendered block in staging
    try testing.expectEqual(@as(f32, 1) / std.math.maxInt(i16), h.loop.staging.storage[1]);

    try h.period();

    try testing.expectEqual(2, h.pcm.starts);
    try testing.expectEqual(script.len, h.pcm.next_step);
}

test "gap: the second half of a split period does not wait for a whole period" {
    const script = [_]Step{
        .{ .avail_frames = 0 }, // period 1: start
        .{ .begin_frames = 300 }, // period 2: full period free, device grants 300
        .{ .avail_frames = 212 }, // exactly what is still owed: begin, no wait
    };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();
    try h.period();

    try testing.expectEqualSlices(usize, &.{ 300, 212 }, h.ctx.seen());
    try testing.expectEqual(script.len, h.pcm.next_step);
    for (h.pcm.callLog()) |call| try testing.expect(call != .wait);
}

test "a wait timeout skips the period without recovery" {
    const script = [_]Step{ .{ .avail_frames = 0 }, .{ .avail_frames = 100 }, .{ .wait_fail = error.timeout } };
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{});
    defer h.deinit();

    try h.period();
    try h.period();

    try testing.expectEqual(0, h.ctx.calls);
    try testing.expectEqual(0, h.pcm.recoveries);
    try testing.expectEqual(0, h.loop.stats.xruns);
    try testing.expectEqual(script.len, h.pcm.next_step);
}

test "staging padding keeps its sentinel after a short block" {
    // 500 frames -> stride 512: 12 frames of padding per channel (a 512 period has none)
    const period_frames = 500;
    const script = [_]Step{.{ .begin_frames = 100 }};
    var h: Harness = undefined;
    try h.init(testing.allocator, &script, .{ .period_frames = period_frames });
    defer h.deinit();

    const stride = h.loop.staging.channel_stride;
    try testing.expect(stride > period_frames);
    for (0..test_channels) |ch| @memset(h.loop.staging.storage[ch * stride ..][period_frames..stride], 99);

    try h.period();

    try testing.expectEqualSlices(usize, &.{ 100, 400 }, h.ctx.seen());
    for (0..test_channels) |ch| {
        for (h.loop.staging.storage[ch * stride ..][period_frames..stride]) |s| try testing.expectEqual(99, s);
    }
}

test "stop() from another thread returns start()" {
    var h: Harness = undefined;
    try h.init(testing.allocator, &.{}, .{ .call_budget = 1 << 20 }); // a broken stop() fails, not hangs
    defer h.deinit();

    const Stopper = struct {
        fn run(loop: *TestLoop) void {
            while (!loop.running.load(.acquire)) std.atomic.spinLoopHint();
            loop.stop();
        }
    };

    const thread = try std.Thread.spawn(.{}, Stopper.run, .{&h.loop});
    try h.loop.start(&h.ctx, Counter.render);
    thread.join();

    try testing.expect(!h.loop.running.load(.acquire));
    try testing.expect(h.loop.stats.periods >= 1);
}

test "gap: stop() before start() is not lost" {
    var h: Harness = undefined;
    try h.init(testing.allocator, &.{}, .{ .call_budget = 64 }); // a lost stop() fails, not hangs
    defer h.deinit();

    h.loop.stop();
    try h.loop.start(&h.ctx, Counter.render);

    try testing.expectEqual(0, h.loop.stats.periods);
}

test "the loop allocates nothing after init (100 periods)" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{});
    var h: Harness = undefined;
    try h.init(failing.allocator(), &.{}, .{});
    defer h.deinit();

    failing.fail_index = failing.alloc_index; // any allocation from here on fails
    const allocations = failing.allocations;

    for (0..100) |_| try h.period();

    try testing.expectEqual(allocations, failing.allocations);
    try testing.expectEqual(100, h.ctx.calls);
}

test "s16 encode/decode round trip" {
    var bytes: [2]u8 = undefined;
    S16.encode(&bytes, 0.5);
    try std.testing.expectApproxEqAbs(0.5, S16.decode(&bytes), 1.0 / 32767.0);
    S16.encode(&bytes, 1.5);
    try std.testing.expectEqual(std.math.maxInt(i16), std.mem.readInt(i16, &bytes, .little));
}
