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
    buffer_cycles: u32 = 3,
};

/// LatencyData struct is passed in to the user-defined callback function
/// when a probe is complete
pub const LatencyData = struct {
    start_time: TimeSpec,
    end_time: TimeSpec,
    expect_time: TimestampDiff,
    actual_time: TimestampDiff,
    latency: TimestampDiff,
    frames_processed: usize,
    cycles: u32,
};

pub const ProbeCallback = *const fn (probe: LatencyData) void;

/// Probe struct is used to measure the latency of an audio device
pub const Probe = struct {
    /// The time the probe was started
    start_time: ?TimeSpec = null,
    /// The harware buffer size, or the number of per cycle.
    hardware_buffer_size: u32,
    /// The sample rate of the audio device
    sample_rate: u32,
    /// The number of hardware buffer cycles the probe will run before calculating the latency
    buffer_cycles: u32,
    /// Counts the number of frames processed to calculate the expected time
    frames_processed: usize = 0,
    /// The maximum number of frames to process before calculating the latency
    max_frames: usize,
    /// The user-defined callback function that is called when the probe is complete
    callback: ProbeCallback,

    pub fn init(callback: ProbeCallback, opts: ProbeOptions) Probe {
        return .{
            .sample_rate = opts.sample_rate,
            .hardware_buffer_size = opts.hardware_buffer_size,
            .frames_processed = 0,
            .buffer_cycles = opts.buffer_cycles,
            .max_frames = opts.buffer_cycles * opts.hardware_buffer_size,
            .callback = callback,
        };
    }

    /// Start the probe
    pub fn start(self: *Probe) void {
        self.start_time = getMonotonicTime() catch {
            return;
        };
    }

    /// Called in the audio loop as it processes frames to count the number of frames processed
    pub fn addFrames(self: *Probe, frames: c_long) void {
        self.frames_processed += @intCast(frames);

        if (self.frames_processed >= self.max_frames) {
            self.calcLatency();
            self.reset();
        }
    }

    /// Reset the probe to start a new measurement
    pub fn reset(self: *Probe) void {
        self.start_time = getMonotonicTime() catch {
            return;
        };

        self.frames_processed = 0;
    }

    /// Calculate the latency and call the user-defined callback function
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
            .cycles = self.buffer_cycles,
        };

        self.callback(latency);
    }

    pub inline fn framesToMicros(self: Probe) i64 {
        return @intCast(@divFloor(self.frames_processed * s_to_us, self.sample_rate));
    }
};

/// TimeSpec struct represents the timestamp returned by alsa's clock_gettime function
const TimeSpec = struct {
    tv_sec: i64 = 0,
    tv_nsec: i64 = 0,

    /// Compute the difference between two TimeSpec structs
    /// Returns TimpstampDiff struct
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

    /// Formats TimeSpec as a string in the format e.g. "1h 10m 1s 2ms 3us"
    /// Truncates the resolution to microseconds
    pub fn formatBuf(self: TimeSpec, buf: []u8) ![]u8 {
        const total_seconds = self.tv_sec;
        const hours = @divTrunc(total_seconds, 3600);
        const minutes = @divTrunc(@mod(total_seconds, 3600), 60);
        const seconds = @mod(total_seconds, 60);
        const millis = @divTrunc(self.tv_nsec, 1_000_000);
        const micros = @mod(@divTrunc(self.tv_nsec, 1000), 1000);

        if (hours > 0) {
            return std.fmt.bufPrint(buf, "{d}h {d}m {d}s {d}ms {d}us", .{ hours, minutes, seconds, millis, micros });
        }
        if (minutes > 0) {
            return std.fmt.bufPrint(buf, "{d}m {d}s {d}ms {d}us", .{ minutes, seconds, millis, micros });
        }
        if (seconds > 0) {
            return std.fmt.bufPrint(buf, "{d}s {d}ms {d}us", .{ seconds, millis, micros });
        }
        if (millis > 0) {
            return std.fmt.bufPrint(buf, "{d}ms {d}us", .{ millis, micros });
        }
        return std.fmt.bufPrint(buf, "{d}us", .{micros});
    }

    /// Convert TimeSpec to microseconds as an integer
    /// Truncates the resolution to microseconds
    pub fn toMicros(self: TimeSpec) i64 {
        return self.tv_sec * 1_000_000 + @divFloor(self.tv_nsec, 1000);
    }

    /// Convert TimeSpec to microseconds as an integer
    /// Truncates the resolution to microseconds
    pub fn toMillis(self: TimeSpec) f64 {
        const total_micros: f64 = @floatFromInt(self.toMicros());
        return total_micros / 1000.0;
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

/// The TimestampDiff struct represents a difference between two timestamps
/// It converts the resolution to microseconds from a TimeSpec struct
pub const TimestampDiff = struct {
    sec: i64,
    usec: i64,

    /// Compute the difference between two TimestampDiff structs
    fn diff(self: TimestampDiff, other: TimestampDiff) TimestampDiff {
        return .{
            .sec = self.sec - other.sec,
            .usec = self.usec - other.usec,
        };
    }

    fn fromMicros(micros: i64) TimestampDiff {
        return .{
            .sec = @divTrunc(micros, 1_000_000),
            .usec = @mod(micros, 1_000_000),
        };
    }

    /// Convert TimestampDiff to microseconds as an integer
    /// Truncates the resolution to microseconds
    pub fn toMicros(self: TimestampDiff) i64 {
        return (self.sec * 1_000_000 + self.usec);
    }

    /// Convert TimestampDiff to milliseconds as a float
    /// Truncates the resolution to microseconds
    pub fn toMillis(self: TimestampDiff) f64 {
        const total_micros: f64 = @floatFromInt(self.toMicros());
        return total_micros / 1000.0;
    }

    /// Formats TimeSpec as a string in the format e.g. "1s 2ms 3us"
    /// If the value is less than 1 second, the seconds are omitted
    /// Truncates the resolution to microseconds
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
