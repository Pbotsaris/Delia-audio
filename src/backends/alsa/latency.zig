const std = @import("std");
const utils = @import("utils.zig");

const c_alsa = @cImport({
    @cInclude("asoundlib.h");
});

const log = std.log.scoped(.alsa);

const s_to_us = 1_000_000;

pub fn noopCallback(_: LatencyData) void {}

const ProbeOptions = struct {
    sample_rate: u32,
    hardware_buffer_size: u32,
    probe_cycles: u32 = 3,
};

pub const LatencyData = struct {
    start_time: TimeSpec,
    end_time: TimeSpec,
    expect_time: TimestampDiff,
    actual_time: TimestampDiff,
    latency: TimestampDiff,
    frames_processed: usize,
};

pub const ProbeCallback = *const fn (probe: LatencyData) void;

pub const Probe = struct {
    start_time: ?TimeSpec = null,
    hardware_buffer_size: u32,
    sample_rate: u32,
    probe_cycles: u32,
    frames_processed: usize = 0,
    max_frames: usize,
    callback: ProbeCallback,

    pub fn init(callback: ProbeCallback, opts: ProbeOptions) Probe {
        return .{
            .sample_rate = opts.sample_rate,
            .hardware_buffer_size = opts.hardware_buffer_size,
            .frames_processed = 0,
            .probe_cycles = opts.probe_cycles,
            .max_frames = opts.probe_cycles * opts.hardware_buffer_size,
            .callback = callback,
        };
    }

    pub fn start(self: *Probe) void {
        self.start_time = getMonotonicTime() catch {
            return;
        };
    }
    pub fn addFrames(self: *Probe, frames: c_long) void {
        self.frames_processed += @intCast(frames);

        if (self.frames_processed >= self.max_frames) {
            self.calcLatency();
            self.reset();
        }
    }

    pub fn reset(self: *Probe) void {
        self.start_time = getMonotonicTime() catch {
            return;
        };

        self.frames_processed = 0;
    }

    pub fn calcLatency(self: *Probe) void {
        const now = getMonotonicTime() catch {
            return;
        };

        const expect_time = TimestampDiff.fromMicros(self.framesToMicros());

        const start_time = self.start_time orelse {
            log.warn("Failed to calculate latency. Start time is null.", .{});
            return;
        };

        const actual_time = start_time.diff(now);

        const latency = LatencyData{
            .start_time = start_time,
            .end_time = now,
            .actual_time = actual_time,
            .expect_time = expect_time,
            .latency = expect_time.diff(actual_time),
            .frames_processed = self.frames_processed,
        };

        self.callback(latency);
    }

    pub inline fn framesToMicros(self: Probe) i64 {
        return @intCast(@divFloor(self.frames_processed * s_to_us, self.sample_rate));
    }
};

const TimeSpec = struct {
    tv_sec: i64 = 0,
    tv_nsec: i64 = 0,

    pub fn diff(start: TimeSpec, end: TimeSpec) TimestampDiff {
        var difference = TimeSpec{};

        if (end.tv_nsec < start.tv_nsec) {
            difference.tv_sec = end.tv_sec - start.tv_sec - 1;
            difference.tv_nsec = 1_000_000_000 + end.tv_nsec - start.tv_nsec;
        } else {
            difference.tv_sec = end.tv_sec - start.tv_sec;
            difference.tv_nsec = end.tv_nsec - start.tv_nsec;
        }
        return difference.toDiffStruct();
    }

    fn toDiffStruct(self: TimeSpec) TimestampDiff {
        return .{
            .sec = self.tv_sec,
            .usec = @divFloor(self.tv_nsec, 1000),
        };
    }
};

fn getMonotonicTime() !TimeSpec {
    var timespec: c_alsa.timespec = undefined;
    const err = c_alsa.clock_gettime(c_alsa.CLOCK_MONOTONIC_RAW, &timespec);

    if (err != 0) {
        log.warn("Could not start latency.Probe. Failed to get current time: {s} ", .{c_alsa.snd_strerror(err)});
        return error.ClockError;
    }
    return .{
        .tv_sec = @intCast(timespec.tv_sec),
        .tv_nsec = @intCast(timespec.tv_nsec),
    };
}

pub const TimestampDiff = struct {
    sec: i64,
    usec: i64,

    pub fn diff(self: TimestampDiff, other: TimestampDiff) TimestampDiff {
        return .{
            .sec = self.sec - other.sec,
            .usec = self.usec - other.usec,
        };
    }

    pub fn fromMicros(micros: i64) TimestampDiff {
        return .{
            .sec = @divTrunc(micros, 1_000_000),
            .usec = @mod(micros, 1_000_000),
        };
    }

    pub fn toMicros(self: TimestampDiff) i64 {
        return (self.sec * 1_000_000 + self.usec);
    }

    pub fn toMillisFloat(self: TimestampDiff) f64 {
        const total_micros: f64 = @floatFromInt(self.toMicros());
        return total_micros / 1000.0;
    }

    pub fn formatBuf(self: TimestampDiff, buf: []u8) ![]u8 {
        const total_millis = @divTrunc(self.toMicros(), 1000);
        const whole_seconds = @divTrunc(total_millis, 1000);
        const remaining_millis = @mod(total_millis, 1000);
        const remaining_micros = @mod(self.usec, 1000);

        if (whole_seconds > 0) {
            return std.fmt.bufPrint(buf, "{d}s {d}ms {d}us", .{ whole_seconds, remaining_millis, remaining_micros });
        }
        if (remaining_millis > 0) {
            return std.fmt.bufPrint(buf, "{d}ms {d}us", .{ remaining_millis, remaining_micros });
        }

        return std.fmt.bufPrint(buf, "{d}us", .{remaining_micros});
    }
};
