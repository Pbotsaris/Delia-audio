const std = @import("std");

pub fn Sine(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("wave.Sine operates on f32 or f64");
    }

    return struct {
        freq: T,
        amp: T,
        sr: T,

        const Self = @This();
        const two: T = 2;

        pub fn init(freq: T, amp: T, sr: T) Self {
            return .{ .freq = freq, .amp = amp, .sr = sr };
        }

        pub fn generate(self: Self, output: []T) []T {
            var phase: T = 0;
            const phase_inc: T = two * std.math.pi * self.freq / self.sr;

            for (output) |*sample| {
                sample.* = self.amp * std.math.sin(phase);
                phase += phase_inc;

                if (phase >= two * std.math.pi) {
                    phase -= two * std.math.pi;
                }
            }

            return output;
        }
    };
}
