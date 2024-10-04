const std = @import("std");

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

        pub fn frequencyBinsAlloc(allocator: std.mem.Allocator, n: T, sample_rate: T) ![]T {
            const bin_count: usize = @intFromFloat(@divFloor(n, 2.0));
            const out = try allocator.alloc(T, bin_count);

            for (0..bin_count) |k| out[k] = (@as(T, @floatFromInt(k)) * sample_rate) / n;

            return out;
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
