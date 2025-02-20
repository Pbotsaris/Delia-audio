const std = @import("std");
const utils = @import("utils.zig");

const c_alsa = @cImport({
    @cInclude("asoundlib.h");
});

const log = std.log.scoped(.alsa);

pub const Probe = struct {
    start_time: TimeSpec,
    hardware_buffer_size: usize,
    sample_rate: u32,
    frames_processed: usize = 0,
    handle: ?*c_alsa.snd_pcm_t,

    pub fn init(handle: ?*c_alsa.snd_pcm_t, sample_rate: u32, hardware_buffer_size: u32) !Probe {
        return .{
            .start_time = try getMonotonicTime(),
            .sample_rate = sample_rate,
            .hardware_buffer_size = @intCast(hardware_buffer_size),
            .frames_processed = 0,
            .handle = handle,
        };
    }

    pub fn addFrames(self: *Probe, frames: c_long) void {
        self.frames_processed += @as(usize, @intCast(frames));
    }

    pub fn framesToMicros(self: Probe, frames: usize) i64 {
        return @intCast(@divFloor(frames * 1_000_000, self.sample_rate));
    }

    pub fn logLatencyStats(self: *Probe) void {
        const now = getMonotonicTime() catch {
            log.warn("Failed to get current time", .{});
            return;
        };

        const avail = c_alsa.snd_pcm_avail(self.handle);
        if (avail < 0) {
            log.warn("Failed to get available frames: {s}", .{c_alsa.snd_strerror(@intCast(avail))});
            return;
        }

        const buffer_size = self.hardware_buffer_size;
        const fill = if (avail >= 0) buffer_size - @as(usize, @intCast(avail)) else 0;

        const expected_time = TimestampDiff.fromMicros(self.framesToMicros(self.frames_processed));

        const actual_time = self.start_time.diff(now);
        const total_drift = expected_time.diff(actual_time);

        var actual_time_buff: [64]u8 = undefined;
        var drift_buff: [64]u8 = undefined;
        var expected_time_buff: [64]u8 = undefined;

        const actual_time_str = actual_time.formatBuf(&actual_time_buff) catch {
            log.warn("Failed to format real time.", .{});
            return;
        };

        const expected_time_str = expected_time.formatBuf(&expected_time_buff) catch {
            log.warn("Failed to format device time.", .{});
            return;
        };

        const drift_str = total_drift.formatBuf(&drift_buff) catch {
            log.warn("Failed to format difference.", .{});
            return;
        };

        log.info(
            \\
            \\    Time Stats:
            \\    Expected time:   {s}
            \\    Actual time:     {s}
            \\    Total Drift:     {s}
            \\    Buffer fill:   {d}/{d} frames
            \\    Frames processed: {d}
        , .{
            expected_time_str,
            actual_time_str,
            drift_str,
            fill,
            buffer_size,
            self.frames_processed,
        });
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
    if (c_alsa.clock_gettime(c_alsa.CLOCK_MONOTONIC_RAW, &timespec) != 0) {
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
