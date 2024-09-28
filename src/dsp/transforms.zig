const std = @import("std");
const waves = @import("waves.zig");
const test_data = @import("test_data.zig");

// nayuki.io/res/how-to-implement-the-discrete-fourier-transform/

pub fn FourierTransforms(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("FourierTransforms only supports f32 and f64");
    }

    const Direction = enum {
        forward,
        inverse,
    };

    const Error = error{
        invalidInput,
        overflow,
    } || std.mem.Allocator.Error;

    return struct {
        const ComplexType = std.math.Complex(T);
        const MultiArrayList = std.MultiArrayList(ComplexType);

        // This implementation is O(n^2)
        pub fn dft(allocator: std.mem.Allocator, in: []T) !MultiArrayList {
            var out = MultiArrayList{};
            try out.setCapacity(allocator, in.len);

            const n = in.len;

            for (0..n) |k| {
                var sum = ComplexType.init(0.0, 0.0);

                for (0..n) |t| {
                    const phase = 2.0 *
                        std.math.pi *
                        @as(T, @floatFromInt(t)) *
                        @as(T, @floatFromInt(k)) /
                        @as(T, @floatFromInt(n));

                    const exp = ComplexType.init(std.math.cos(phase), -std.math.sin(phase));
                    sum = sum.add(exp.mul(ComplexType.init(in[t], 0)));
                }

                try out.append(allocator, sum);
            }

            return out;
        }

        pub fn fft(allocator: std.mem.Allocator, in: []T) Error!MultiArrayList {
            if (in.len == 0) return MultiArrayList{};

            var inout = MultiArrayList{};
            try inout.setCapacity(allocator, in.len);

            errdefer inout.deinit(allocator);

            for (in) |item| try inout.append(allocator, ComplexType.init(item, 0));

            if (isPowerOfTwo(in.len)) return try fftRadix2(allocator, &inout, .forward)
            // more complex algorithms are used for non power of two sizes
            else return try fftBluestein(allocator, &inout, .forward);
        }

        pub fn ifft(allocator: std.mem.Allocator, inout: *MultiArrayList) Error!MultiArrayList {
            if (inout.len == 0) return inout.*;

            var out = if (isPowerOfTwo(inout.len)) try fftRadix2(allocator, inout, .inverse) else try fftBluestein(allocator, inout, .inverse);

            // Scaling the output
            for (0..out.len) |i| {
                const len = ComplexType.init(@as(T, @floatFromInt(out.len)), 0);
                out.set(i, out.get(i).div(len));
            }

            return out;
        }

        fn fftComplex(allocator: std.mem.Allocator, inout: *MultiArrayList, direction: Direction) Error!MultiArrayList {
            if (inout.len == 0) return MultiArrayList{};

            if (isPowerOfTwo(inout.len)) return try fftRadix2(allocator, inout, direction)
            // more complex algorithms are used for non power of two sizes
            else return try fftBluestein(allocator, inout, direction);
        }

        fn fftRadix2(allocator: std.mem.Allocator, inout: *MultiArrayList, direction: Direction) Error!MultiArrayList {
            // sanity check for power of two
            if (!isPowerOfTwo(inout.len)) return Error.invalidInput;

            // calculate "levels"  needed to split the input down to a single element
            // "levels" is then the number of times the input can be divided by 2
            var levels: usize = 0;
            var n: usize = inout.len;

            // shifting by 1 is the same as dividing by 2
            // equivalent to log2(n)
            while (n > 1) : (n >>= 1) levels += 1;

            var exp_table = MultiArrayList{};
            const exp_table_len: usize = @divFloor(inout.len, 2);

            defer exp_table.deinit(allocator);
            try exp_table.setCapacity(allocator, exp_table_len);

            for (0..exp_table_len) |i| {
                const pi: T = if (direction == .inverse) -2.0 * std.math.pi else 2.0 * std.math.pi;
                const phase: T = pi * @as(T, @floatFromInt(i)) / @as(T, @floatFromInt(inout.len));
                const exp = ComplexType.init(std.math.cos(phase), -std.math.sin(phase));

                try exp_table.append(allocator, exp);
            }

            // bit-reversal permutation
            // https://en.wikipedia.org/wiki/Bit-reversal_permutation
            for (0..inout.len) |idx| {
                const rev_idx = reverseBits(idx, levels);

                if (idx > rev_idx) {
                    const tmp = inout.get(idx);
                    inout.set(idx, inout.get(rev_idx));
                    inout.set(rev_idx, tmp);
                }
            }

            // Cooley-Tukey decimation-in-time radix-2 FFT
            var size: usize = 2;

            while (size <= inout.len) : (size *= 2) {
                const half_size: usize = @divFloor(size, 2);
                const table_step: usize = @divFloor(inout.len, size);
                var idx: usize = 0;

                while (idx < inout.len) : (idx += size) {
                    var inner_idx = idx;
                    var table_idx: usize = 0;

                    while (inner_idx < idx + half_size) : (inner_idx += 1) {
                        const out_idx = inner_idx + half_size;
                        const tmp = inout.get(out_idx).mul(exp_table.get(table_idx));
                        inout.set(out_idx, inout.get(inner_idx).sub(tmp));
                        inout.set(inner_idx, inout.get(inner_idx).add(tmp));

                        table_idx += table_step;
                    }
                }

                // Prevent overflow in 'size *= 2'
                if (size == inout.len) break;
            }

            return inout.*;
        }

        fn fftBluestein(allocator: std.mem.Allocator, inout: *MultiArrayList, direction: Direction) Error!MultiArrayList {
            var conv_len: usize = 1;

            // Find power of 2 conv_len such that -> conv_len  >= in.len * 2 + 1;
            while (conv_len / 2 < inout.len) {
                // sanity check for overflows
                if (conv_len > std.math.maxInt(usize) / 2) return Error.overflow;
                conv_len *= 2;
            }

            var exp_table = MultiArrayList{};
            defer exp_table.deinit(allocator);

            var avec = MultiArrayList{};
            defer avec.deinit(allocator);

            var bvec = MultiArrayList{};
            defer bvec.deinit(allocator);

            try exp_table.setCapacity(allocator, inout.len);

            // resize to capacity ot initialize the memory
            try avec.setCapacity(allocator, conv_len);
            try avec.resize(allocator, conv_len);

            try bvec.setCapacity(allocator, conv_len);
            try bvec.resize(allocator, conv_len);

            // trig tables
            for (0..inout.len) |i| {
                const idx: usize = (i * i) % (inout.len * 2);
                const pi: T = if (direction == .inverse) -std.math.pi else std.math.pi;
                const phase = pi * @as(T, @floatFromInt(idx)) / @as(T, @floatFromInt(inout.len));
                const exp = ComplexType.init(std.math.cos(phase), -std.math.sin(phase));
                try exp_table.append(allocator, exp);
            }

            for (0..inout.len) |i| {
                avec.set(i, inout.get(i).mul(exp_table.get(i)));
            }

            bvec.set(0, exp_table.get(0));

            for (1..inout.len) |i| {
                const conj = exp_table.get(i).conjugate();
                bvec.set(i, conj);
                bvec.set(conv_len - i, conj);
            }

            // convolution phase here
            // Note that it modifies both avec and bvec in place
            // we return avec
            avec = try convolve(allocator, &avec, &bvec);

            for (0..inout.len) |i| {
                inout.set(i, avec.get(i).mul(exp_table.get(i)));
            }

            return inout.*;
        }

        pub fn convolve(allocator: std.mem.Allocator, avec: *MultiArrayList, bvec: *MultiArrayList) !MultiArrayList {
            var avec_ffted = try fftComplex(allocator, avec, Direction.forward);
            const bvec_ffted = try fftComplex(allocator, bvec, Direction.forward);

            for (0..avec_ffted.len) |i| {
                avec_ffted.set(i, avec_ffted.get(i).mul(bvec_ffted.get(i)));
            }

            var avec_inversed = try fftComplex(allocator, &avec_ffted, Direction.inverse);

            // we must scale as this implementation ommits scaling for inverse fft
            //TODO:  Look into refactoring to have scaling as an option

            for (0..avec_inversed.len) |i| {
                const len = ComplexType.init(@as(T, @floatFromInt(avec_inversed.len)), 0);
                avec_inversed.set(i, avec_inversed.get(i).div(len));
            }

            return avec_inversed;
        }

        //  fft_idx: index to be reversed
        //  width: the number of bits to reverse based on fft levels
        //  e.g. so if in.len = 8, width would be 3 because log2(8) = 3
        fn reverseBits(fft_idx: usize, width: usize) usize {
            // u6 because usize is 64 bits and log2(64) = 6
            return @bitReverse(fft_idx) >> @as(u6, @intCast(@bitSizeOf(usize) - width));
        }

        fn reverseBitsDiscrete(val: usize, width: usize) usize {
            var result: usize = 0;
            var idx: usize = val;
            var i: usize = 0;

            while (i < width) : (i += 1) {
                result = (result << 1) | (idx & 1);
                idx >>= 1;
            }

            return result;
        }

        fn findShiftWidth(n: usize) usize {
            var width: usize = 0;
            var tmp: usize = n;

            while (tmp > 1) : (tmp >>= 1) width += 1;

            return width;
        }

        fn isPowerOfTwo(n: usize) bool {
            return n != 0 and n & (n - 1) == 0;
        }
    };
}

const testing = std.testing;

test "dft simple" {
    const allocator = std.testing.allocator;
    var input_signal = [_]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75, -1.0 };

    const transforms = FourierTransforms(f32);
    var output = try transforms.dft(allocator, &input_signal);
    defer output.deinit(allocator);

    var i: usize = 0;
    for (output.items(.re), output.items(.im)) |re, im| {
        try testing.expectApproxEqRel(test_data.expected_simple_dft[i].re, re, 0.0001);
        try testing.expectApproxEqRel(test_data.expected_simple_dft[i].im, im, 0.0001);
        i += 1;
    }
}

test "dft sine" {
    const allocator = std.testing.allocator;

    const sineGeneration = waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var sine: [128]f32 = undefined;
    sineGeneration.generate(&sine);

    const transforms = FourierTransforms(f32);
    var output = try transforms.dft(allocator, &sine);
    defer output.deinit(allocator);

    try testing.expectEqual(output.len, test_data.expected_sine_dft.len);

    var i: usize = 0;
    for (output.items(.re), output.items(.im)) |re, im| {
        try testing.expectApproxEqAbs(test_data.expected_sine_dft[i].re, re, 0.001);
        try testing.expectApproxEqAbs(test_data.expected_sine_dft[i].im, im, 0.001);
        i += 1;
    }
}

test "fft simple power of 2" {
    const allocator = std.testing.allocator;
    var input_signal = [8]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };

    const transforms = FourierTransforms(f32);
    var fft_out = try transforms.fft(allocator, &input_signal);
    var dft_out = try transforms.dft(allocator, &input_signal);
    defer fft_out.deinit(allocator);
    defer dft_out.deinit(allocator);

    for (0..input_signal.len) |i| {
        const fft = fft_out.get(i);
        const dft = dft_out.get(i);

        try testing.expectApproxEqAbs(fft.re, dft.re, 0.0001);
        try testing.expectApproxEqAbs(fft.im, dft.im, 0.0001);
    }
}

test "fft simple non power of 2" {
    const allocator = std.testing.allocator;
    var input_signal = [9]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75, -1.0 };

    const transforms = FourierTransforms(f32);
    var fft_out = try transforms.fft(allocator, &input_signal);
    var dft_out = try transforms.dft(allocator, &input_signal);
    defer fft_out.deinit(allocator);
    defer dft_out.deinit(allocator);

    for (0..input_signal.len) |i| {
        const fft = fft_out.get(i);
        const dft = dft_out.get(i);

        try testing.expectApproxEqAbs(fft.re, dft.re, 0.0001);
        try testing.expectApproxEqAbs(fft.im, dft.im, 0.0001);
    }
}

test "inverse fft simple power of two" {
    const allocator = std.testing.allocator;
    var input_signal = [8]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, 0.75 };

    const transforms = FourierTransforms(f32);

    var fft_out = try transforms.fft(allocator, &input_signal);
    defer fft_out.deinit(allocator);

    var inversed = try transforms.ifft(allocator, &fft_out);

    for (0..input_signal.len) |i| {
        const inversed_item = inversed.get(i);
        try testing.expectApproxEqAbs(input_signal[i], inversed_item.re, 0.0001);
    }
}

test "inverse fft simple power non power of two" {
    const allocator = std.testing.allocator;
    var input_signal = [9]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, 0.75, -1.0 };

    const transforms = FourierTransforms(f32);

    var fft_out = try transforms.fft(allocator, &input_signal);
    defer fft_out.deinit(allocator);

    var inversed = try transforms.ifft(allocator, &fft_out);

    for (0..input_signal.len) |i| {
        const inversed_item = inversed.get(i);
        try testing.expectApproxEqAbs(input_signal[i], inversed_item.re, 0.0001);
    }
}

test "fft sine multiple of 2" {
    const allocator = std.testing.allocator;

    const sineGeneration = waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var sine: [128]f32 = undefined;
    sineGeneration.generate(&sine);

    const transforms = FourierTransforms(f32);
    var output = try transforms.fft(allocator, &sine);
    defer output.deinit(allocator);

    try testing.expectEqual(output.len, test_data.expected_sine_dft.len);

    var i: usize = 0;
    for (output.items(.re), output.items(.im)) |re, im| {
        try testing.expectApproxEqAbs(test_data.expected_sine_dft[i].re, re, 0.001);
        try testing.expectApproxEqAbs(test_data.expected_sine_dft[i].im, im, 0.001);
        i += 1;
    }
}

test "bit reverse test n = 8" {
    const transform = FourierTransforms(f32);

    const indices = [8]usize{ 0, 1, 2, 3, 4, 5, 6, 7 };
    const expected = [8]usize{ 0, 4, 2, 6, 1, 5, 3, 7 }; // Bit-reversed indices for n = 8
    const width = 3; // log2(8) = 3

    for (indices, 0..indices.len) |idx, i| {
        const result1 = transform.reverseBits(idx, width);
        const result2 = transform.reverseBitsDiscrete(idx, width);
        try testing.expectEqual(expected[i], result1);
        try testing.expectEqual(expected[i], result2);
    }
}

test "bit reverse test for n = 16" {
    const transform = FourierTransforms(f32);

    const indices = [16]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    const expected = [16]usize{ 0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15 }; // Bit-reversed indices for n = 16
    const width = 4; // log2(16) = 4

    for (indices, 0..indices.len) |idx, i| {
        const result1 = transform.reverseBits(idx, width);
        const result2 = transform.reverseBitsDiscrete(idx, width);
        try testing.expectEqual(expected[i], result1);
        try testing.expectEqual(expected[i], result2);
    }
}
