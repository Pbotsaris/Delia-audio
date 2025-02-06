const std = @import("std");
const log = @import("log.zig").log;

pub fn Wave(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("wave.Sine operates on f32 or f64");
    }

    return struct {
        freq: T,
        amp: T,
        sr: T,
        phase: T = 0,
        inc: T = 0,

        const two: T = 2;
        const Self = @This();

        pub fn init(freq: T, amp: T, sr: T) Self {
            const inc = two * std.math.pi * freq / sr;
            return .{ .freq = freq, .amp = amp, .sr = sr, .inc = inc };
        }

        pub fn setSampleRate(self: *Self, sr: T) void {
            self.sr = sr;
            self.inc = two * std.math.pi * self.freq / sr;
        }

        pub fn bufferSizeFor(self: Self, seconds: T) usize {
            return @intFromFloat(self.sr * seconds);
        }

        pub fn sine(self: *Self, output: []T) []T {
            for (output) |*sample| {
                sample.* = self.sineSample();
            }

            return output;
        }

        pub inline fn sineSample(self: *Self) T {
            const sample = self.amp * std.math.sin(self.phase);
            self.phase += self.inc;

            if (self.phase >= two * std.math.pi) {
                self.phase -= two * std.math.pi;
            }

            return sample;
        }

        pub inline fn sawtoothSample(self: *Self) T {
            const sample = self.amp * (2 * self.phase / (two * std.math.pi) - 1);
            self.phase += self.inc;

            if (self.phase >= two * std.math.pi) {
                self.phase -= two * std.math.pi;
            }

            return sample;
        }

        pub fn sawtooth(self: *Self, output: []T) []T {
            for (output) |*sample| {
                sample.* = self.sawtoothSample();
            }

            return output;
        }
    };
}

pub fn unitInpulse(T: type, output: []T) []T {
    output[0] = 1;

    for (output[1..]) |*sample| {
        sample.* = 0;
    }

    return output;
}
