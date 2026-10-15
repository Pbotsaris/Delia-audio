const std = @import("std");

/// The module's only `@cImport`: every file that touches alsa-lib goes through this one, since
/// each `@cImport` yields its own distinct opaque `snd_pcm_t`.
pub const c = @cImport({
    @cInclude("asoundlib.h");
});

pub const PcmError = error{
    xrun,
    suspended,
    io,
    timeout,
};

pub const Region = struct {
    bytes: []u8,
    frame_count: usize,
};

pub const RecoverOption = struct {
    retries: usize,
    sleep_ms: u64,
};

/// The seam's view of `snd_pcm_state_t`; `open` covers OPEN and SETUP (no prepared hw params).
pub const State = enum { open, prepared, running, xrun, draining, paused, suspended, disconnected };

/// The seam over `snd_pcm_*`. Converts negative results to errors and
/// computes the region slice from `areas`, `offset` and `step`. No policy lives here.
pub const Alsa = struct {
    const Self = @This();

    handle: *c.snd_pcm_t,
    bytes_per_frame: usize,
    offset: c.snd_pcm_uframes_t = 0,
    recover_option: RecoverOption = .{ .retries = 5, .sleep_ms = 10 },

    pub fn availUpdate(self: *Self) PcmError!usize {
        const avail = c.snd_pcm_avail_update(self.handle);
        if (avail < 0) return errnoToPcm(avail);

        return @intCast(avail);
    }

    pub fn start(self: *Self) PcmError!void {
        const result = c.snd_pcm_start(self.handle);
        if (result < 0) return errnoToPcm(result);
    }

    pub fn wait(self: *Self, timeout_ms: u32) PcmError!void {
        const result = c.snd_pcm_wait(self.handle, @intCast(timeout_ms));

        // 0 means timeout elapsed, not successful wait, so we return a timeout error
        if (result == 0) return PcmError.timeout;

        if (result < 0) return errnoToPcm(result);
    }

    pub fn mmapBegin(self: *Self, frame_count_wanted: usize) PcmError!Region {
        var areas: ?*const c.snd_pcm_channel_area_t = null;
        var frames: c.snd_pcm_uframes_t = @intCast(frame_count_wanted);

        const result = c.snd_pcm_mmap_begin(self.handle, &areas, &self.offset, &frames);
        if (result < 0) return errnoToPcm(result);

        // interleaved access: one area describes every channel; geometry was validated at prepare
        const area = areas orelse return PcmError.io;

        return regionFromArea(area, self.offset, frames, self.bytes_per_frame) orelse PcmError.io;
    }

    pub fn mmapCommit(self: *Self, frame_count: usize) PcmError!usize {
        const result = c.snd_pcm_mmap_commit(self.handle, self.offset, @intCast(frame_count));
        if (result < 0) return errnoToPcm(result);

        return @intCast(result);
    }

    /// xrun: prepare. suspended: resume until the device stops saying EAGAIN, then prepare if
    /// resume still failed. Bounded by `recover_option`.
    pub fn recover(self: *Self, err: PcmError) PcmError!void {
        if (err == PcmError.suspended) {
            var retries = self.recover_option.retries;
            var result = c.snd_pcm_resume(self.handle);

            while (result == -c.EAGAIN and retries > 0) : (retries -= 1) {
                sleepMs(self.recover_option.sleep_ms);
                result = c.snd_pcm_resume(self.handle);
            }

            if (result >= 0) return;
        }

        const result = c.snd_pcm_prepare(self.handle);
        if (result < 0) return errnoToPcm(result);
    }

    pub fn state(self: *Self) State {
        return switch (c.snd_pcm_state(self.handle)) {
            c.SND_PCM_STATE_OPEN, c.SND_PCM_STATE_SETUP => .open,
            c.SND_PCM_STATE_PREPARED => .prepared,
            c.SND_PCM_STATE_RUNNING => .running,
            c.SND_PCM_STATE_XRUN => .xrun,
            c.SND_PCM_STATE_DRAINING => .draining,
            c.SND_PCM_STATE_PAUSED => .paused,
            c.SND_PCM_STATE_SUSPENDED => .suspended,
            else => .disconnected,
        };
    }

    /// Geometry of the mmap area without transferring anything: begin(0) then commit(0).
    /// The device calls this once at prepare to validate `first` and `step`.
    pub fn inspectArea(self: *Self) PcmError!c.snd_pcm_channel_area_t {
        _ = try self.availUpdate();

        var areas: ?*const c.snd_pcm_channel_area_t = null;
        var frames: c.snd_pcm_uframes_t = 0;

        const result = c.snd_pcm_mmap_begin(self.handle, &areas, &self.offset, &frames);
        if (result < 0) return errnoToPcm(result);

        const area = (areas orelse return PcmError.io).*;
        _ = try self.mmapCommit(0);

        return area;
    }

    /// `result` is a negative ALSA result: c_int from most calls, snd_pcm_sframes_t from avail/commit.
    fn errnoToPcm(result: anytype) PcmError {
        const errno: c_int = @intCast(-result);

        return switch (errno) {
            c.EPIPE => error.xrun,
            c.ESTRPIPE => error.suspended,
            else => error.io,
        };
    }

    /// Pure arithmetic over an interleaved area, separated so it can be tested without a device.
    /// Returns null when the area's stride disagrees with the negotiated frame size.
    fn regionFromArea(area: *const c.snd_pcm_channel_area_t, offset: c.snd_pcm_uframes_t, frame_count: c.snd_pcm_uframes_t, bytes_per_frame: usize) ?Region {
        const step_bytes: usize = area.step / 8;
        if (step_bytes != bytes_per_frame) return null;

        const addr: [*]u8 = @ptrCast(area.addr orelse return null);
        const start_at: usize = area.first / 8 + offset * step_bytes;
        return .{ .bytes = addr[start_at..][0 .. frame_count * step_bytes], .frame_count = frame_count };
    }

    fn sleepMs(ms: u64) void {
        var req: std.c.timespec = .{
            .sec = @intCast(ms / 1000),
            .nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
        };

        _ = std.c.nanosleep(&req, null);
    }
};

// ===========================================================================
// Test double: ScriptedPcm. Only test code instantiates it.
//
// Device memory is a ring of two periods. Every committed byte is copied to `wire`, which is
// what "the hardware played". Outcomes come from a script consumed in order: a step is taken only
// by the call it names, so a step the loop never reaches blocks the rest (tests check
// `next_step == script.len`). Unscripted calls succeed: avail reports one period, begin grants
// min(want, avail, until wrap), commit commits everything.
//
// Like ALSA, begin is bounded by the avail of the last availUpdate minus what was committed
// since; only availUpdate refreshes it, wait() does not. start() on a stream that is not
// prepared fails like snd_pcm_start (EBADFD -> io).
// All storage is allocated in init, so a test can count allocations across periods.
// ===========================================================================

pub const ScriptedPcm = struct {
    const Self = @This();

    pub const Step = union(enum) {
        avail_frames: usize,
        avail_fail: PcmError,
        wait_fail: PcmError,
        begin_frames: usize, // begin returns min(want, avail, n)
        begin_fail: PcmError,
        commit_frames: usize, // commit returns min(requested, n)
        commit_fail: PcmError,
        recover_to: State, // state after recover(); a resumed stream is .running
    };

    pub const Call = enum { avail, start, wait, begin, commit, recover };

    pub const Options = struct {
        channel_count: usize,
        bytes_per_sample: usize,
        period_frames: usize,
        wire_frames: usize = 8 * 1024, // wire stops recording past this; committed_frames keeps counting
        call_budget: usize = std.math.maxInt(usize), // availUpdate returns io past this; ends a runaway loop
    };

    const call_log_capacity = 256;
    ring: []u8,
    wire_storage: []u8,
    wire_len: usize = 0,
    frame_bytes: usize,
    period_frames: usize,
    head: usize = 0, // byte offset of the next begin
    avail: usize = 0, // frames begin may grant; refreshed by availUpdate only
    script: []const Step,
    next_step: usize = 0,
    current_state: State = .prepared,
    recoveries: u32 = 0,
    starts: u32 = 0,
    committed_frames: usize = 0,
    calls: [call_log_capacity]Call = undefined,
    call_count: usize = 0, // keeps counting past capacity; only the first call_log_capacity are logged
    call_budget: usize,

    pub fn init(allocator: std.mem.Allocator, script: []const Step, opts: Options) !Self {
        const frame_bytes = opts.channel_count * opts.bytes_per_sample;

        const ring = try allocator.alloc(u8, frame_bytes * opts.period_frames * 2);
        errdefer allocator.free(ring);
        @memset(ring, 0xAA);

        const wire_storage = try allocator.alloc(u8, frame_bytes * opts.wire_frames);

        return .{
            .ring = ring,
            .wire_storage = wire_storage,
            .frame_bytes = frame_bytes,
            .period_frames = opts.period_frames,
            .script = script,
            .call_budget = opts.call_budget,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.ring);
        allocator.free(self.wire_storage);
    }

    pub fn wire(self: *const Self) []const u8 {
        return self.wire_storage[0..self.wire_len];
    }

    pub fn callLog(self: *const Self) []const Call {
        return self.calls[0..@min(self.call_count, call_log_capacity)];
    }

    fn log(self: *Self, call: Call) void {
        if (self.call_count < call_log_capacity) self.calls[self.call_count] = call;
        self.call_count += 1;
    }

    fn take(self: *Self, comptime tag: std.meta.Tag(Step)) ?@FieldType(Step, @tagName(tag)) {
        if (self.next_step >= self.script.len) return null;
        const step = self.script[self.next_step];

        if (step != tag) return null;
        self.next_step += 1;
        return @field(step, @tagName(tag));
    }

    fn fail(self: *Self, err: PcmError) PcmError {
        switch (err) {
            error.xrun => self.current_state = .xrun,
            error.suspended => self.current_state = .suspended,
            error.io, error.timeout => {},
        }
        return err;
    }

    pub fn availUpdate(self: *Self) PcmError!usize {
        self.log(.avail);
        if (self.call_count > self.call_budget) return error.io;

        if (self.take(.avail_fail)) |err| return self.fail(err);

        self.avail = self.take(.avail_frames) orelse self.period_frames;
        return self.avail;
    }

    pub fn start(self: *Self) PcmError!void {
        self.log(.start);
        if (self.current_state != .prepared) return error.io;

        self.starts += 1;
        self.current_state = .running;
    }

    pub fn wait(self: *Self, _: u32) PcmError!void {
        self.log(.wait);
        if (self.take(.wait_fail)) |err| return self.fail(err);
    }

    pub fn mmapBegin(self: *Self, want: usize) PcmError!Region {
        self.log(.begin);

        if (self.take(.begin_fail)) |err| return self.fail(err);

        const scripted = self.take(.begin_frames) orelse want;
        // never hand out a region that wraps; a real ring does the same by shortening
        const until_wrap = (self.ring.len - self.head) / self.frame_bytes;
        const granted = @min(want, scripted, self.avail, until_wrap);

        return .{ .bytes = self.ring[self.head..][0 .. granted * self.frame_bytes], .frame_count = granted };
    }

    pub fn mmapCommit(self: *Self, frame_count: usize) PcmError!usize {
        self.log(.commit);
        if (self.take(.commit_fail)) |err| return self.fail(err);

        const committed = @min(frame_count, self.take(.commit_frames) orelse frame_count);
        const bytes = committed * self.frame_bytes;

        const kept = @min(bytes, self.wire_storage.len - self.wire_len);
        @memcpy(self.wire_storage[self.wire_len..][0..kept], self.ring[self.head..][0..kept]);
        self.wire_len += kept;

        self.head = (self.head + bytes) % self.ring.len;
        self.avail -= committed;
        self.committed_frames += committed;
        return committed;
    }

    pub fn recover(self: *Self, _: PcmError) PcmError!void {
        self.log(.recover);
        self.recoveries += 1;
        self.current_state = self.take(.recover_to) orelse .prepared;
    }

    pub fn state(self: *Self) State {
        return self.current_state;
    }
};

test "regionFromArea rejects a stride that disagrees with the frame size, slices otherwise" {
    var storage: [64]u8 = undefined;
    const area: c.snd_pcm_channel_area_t = .{ .addr = &storage, .first = 0, .step = 4 * 8 }; // 4 bytes/frame

    try std.testing.expectEqual(null, Alsa.regionFromArea(&area, 0, 4, 8));

    const region = Alsa.regionFromArea(&area, 2, 3, 4).?;
    try std.testing.expectEqual(3, region.frame_count);
    try std.testing.expectEqual(12, region.bytes.len);
    try std.testing.expectEqual(@intFromPtr(&storage[8]), @intFromPtr(region.bytes.ptr));
}

test "errnoToPcm maps EPIPE and ESTRPIPE, everything else is io" {
    try std.testing.expectEqual(PcmError.xrun, Alsa.errnoToPcm(@as(c_int, -c.EPIPE)));
    try std.testing.expectEqual(PcmError.suspended, Alsa.errnoToPcm(@as(c_long, -c.ESTRPIPE)));
    try std.testing.expectEqual(PcmError.io, Alsa.errnoToPcm(@as(c_int, -c.EBADFD)));
}
