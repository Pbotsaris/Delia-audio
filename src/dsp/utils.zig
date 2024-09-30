const std = @import("std");

pub fn Utils(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("Only f32 and f64 are supported");
    }

    return struct {
        // note that when converting fft mags to decibels use a reference of 0.5 because of
        // the fft represents the sum positives and negatives of the signal
        pub fn DecibelsFromMagnitude(magnitude: T, reference: T) T {
            return 20.0 * std.math.log10(magnitude / reference);
        }

        pub fn magnitudeFromDecibels(db: T, reference: T) T {
            return reference * std.math.pow(10.0, db / 20.0);
        }

        pub fn frequencyBins(n: T, sample_rate: T, out: []T) []T {
            const bin_count: usize = @intFromFloat(@divFloor(n, 2.0));

            for (0..bin_count) |k| out[k] = (@as(T, @floatFromInt(k)) * sample_rate) / n;

            return out;
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
