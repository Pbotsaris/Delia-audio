const std = @import("std");
const waves = @import("waves.zig");
const test_data = @import("test_data.zig");

const log = @import("log.zig").log;

pub fn Utils(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("Only f32 and f64 are supported");
    }

    const Error = error{
        invalid_size,
    };

    return struct {
        pub const ComplexType: type = std.math.Complex(T);

        // note that when converting fft mags to decibels use a reference of 0.5 because of
        // the fft represents the sum positives and negatives of the signal
        pub fn DecibelsFromMagnitude(magnitude: T, reference: T) T {
            return 20.0 * std.math.log10(magnitude / reference);
        }

        pub fn magnitudeFromDecibels(db: T, reference: T) T {
            return reference * std.math.pow(10.0, db / 20.0);
        }

        pub fn frequencyBins(n: T, sample_rate: T, out: []T) ![]T {
            if (out.len != @as(usize, @intFromFloat(@divFloor(n, 2.0)))) {
                return Error.invalid_size;
            }

            // divide by to because fft is symmetric and we can ignore the negative frequencies
            // or the frequencies above the nyquist frequency
            const bin_count: usize = @intFromFloat(@divFloor(n, 2.0));
            for (0..bin_count) |k| out[k] = (@as(T, @floatFromInt(k)) * sample_rate) / n;

            return out;
        }

        pub fn frequencyBinsAlloc(allocator: std.mem.Allocator, fft_size: T, sample_rate: T) ![]T {
            const bin_count: usize = @intFromFloat(@divFloor(fft_size, 2.0));
            const out = try allocator.alloc(T, bin_count);

            for (0..bin_count) |k| out[k] = (@as(T, @floatFromInt(k)) * sample_rate) / fft_size;

            return out;
        }

        pub fn blackman(index: usize, window_size: usize) T {
            const indexf: T = @floatFromInt(index);
            const windowf: T = @floatFromInt(window_size);

            const first_harm: T = 2.0 * std.math.pi * indexf / (windowf - 1.0);
            const second_harm: T = 4.0 * std.math.pi * indexf / (windowf - 1.0);

            return 0.42 - 0.5 * std.math.cos(first_harm) + 0.08 * std.math.cos(second_harm);
        }

        pub fn hanning(index: usize, window_size: usize) T {
            const indexf: T = @floatFromInt(index);
            const windowf: T = @floatFromInt(window_size);

            const harm: T = 2.0 * std.math.pi * indexf / (windowf - 1.0);
            return 0.5 * (1.0 - std.math.cos(harm));
        }

        pub fn phase(x: ComplexType) T {
            return std.math.atan2(x.im, x.re);
        }

        pub fn nyquist(sample_rate: T) T {
            return sample_rate / 2.0;
        }

        pub fn largestPowerOfTwo(size: T) T {
            const exp: T = std.math.floor(std.math.log2(size));
            return std.math.pow(2.0, exp);
        }
    };
}

const testing = std.testing;

test "DSP Utils hanning window function" {
    const utils = Utils(f32);

    var input: [128]f32 = undefined;
    var w = waves.Wave(f32).init(400.0, 1.0, 44100.0);

    const sine_input = w.sine(&input);

    for (0..sine_input.len) |i| {
        sine_input[i] *= utils.hanning(i, input.len);
    }

    for (sine_input, 0..sine_input.len) |sample, i| {
        try testing.expectApproxEqAbs(test_data.hanning_expect[i], sample, 0.000001);
    }
}

test "DSP Utils blackman window function" {
    const utils = Utils(f32);

    var input: [128]f32 = undefined;
    var w = waves.Wave(f32).init(400.0, 1.0, 44100.0);

    const sine_input = w.sine(&input);

    for (0..sine_input.len) |i| {
        sine_input[i] *= utils.blackman(i, input.len);
    }

    for (sine_input, 0..sine_input.len) |sample, i| {
        try testing.expectApproxEqAbs(test_data.blackman_expect[i], sample, 0.000001);
    }
}
