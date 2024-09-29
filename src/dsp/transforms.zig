const std = @import("std");
const waves = @import("waves.zig");
const test_data = @import("test_data.zig");

// nayuki.io/res/how-to-implement-the-discrete-fourier-transform/

const Direction = enum {
    forward,
    inverse,
};

const FFTSize = enum(usize) {
    fft_2 = 2,
    fft_4 = 4,
    fft_8 = 8,
    fft_16 = 16,
    fft_32 = 32,
    fft_64 = 64,
    fft_128 = 128,
    fft_256 = 256,
    fft_512 = 512,
    fft_1024 = 1024,
    fft_2048 = 2048,
    fft_4096 = 4096,
    fft_8192 = 8192,
    fft_16384 = 16384,
    fft_32768 = 32768,
};

const Error = error{
    invalid_input_size,
    overflow,
} || std.mem.Allocator.Error;

/// `FourierStatic` provides a high-performance API for FFT operations without heap allocation.
/// This is designed for cases where the FFT size is known at compile time.
/// Input vectors are modified in place.
/// For dynamic FFT sizes or non-power-of-two inputs, see `FourierDynamic`.
///
/// - **FFT Size**: Must be known at compile time and specified via the `FFTSize` enum.
/// - **T**: Supported types are `f32` and `f64`.
/// - **Memory Management**: Uses a fixed buffer allocator for stack-based memory allocation, avoiding the overhead of heap operations.
pub fn FourierStatic(comptime T: type, comptime size: FFTSize) type {
    if (T != f32 and T != f64) {
        @compileError("FourierTransforms only supports f32 and f64");
    }

    return struct {
        const ComplexType = std.math.Complex(T);
        const ComplexVector = std.MultiArrayList(ComplexType);

        const fft_size: usize = @intFromEnum(size);
        const levels: usize = std.math.log2(fft_size);

        var internal_buffer: [fft_size * @sizeOf(ComplexType)]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&internal_buffer);
        const allocator = fba.allocator();

        /// A helper function to initialize a `ComplexVector` from an audio signal vector.
        ///
        /// - **Parameters**:
        ///     - `heap_allocator`: Allocator for the `ComplexVector`.
        ///     - `vec`: Input vector containing the audio signal.
        /// - **Returns**: Initialized `ComplexVector`. Throws an error if the input size is invalid.
        pub fn createComplexVector(heap_allocator: std.mem.Allocator, vec: []T) !ComplexVector {
            if (vec.len != fft_size) return Error.invalid_input_size;

            var out = ComplexVector{};
            try out.setCapacity(heap_allocator, fft_size);

            for (vec) |item| try out.append(allocator, ComplexType.init(item, 0));

            return out;
        }

        /// Conveniently reuses an existing `ComplexVector` buffer for another FFT iteration by writing new input data to the vector.
        ///
        /// - **Parameters**:
        ///     - `vec`: The `ComplexVector` to be reused.
        ///     - `input`: The new input signal to be written into the `ComplexVector`.
        /// - **Returns**: Updated `ComplexVector`. Throws an error if input size is invalid.
        pub fn setComplexVector(vec: *ComplexVector, input: []T) Error!ComplexVector {
            if (vec.len != input.len or vec.len != fft_size) return Error.invalid_input_size;

            for (input, 0..input.len) |item, i| {
                vec.set(i, ComplexType.init(item, 0));
            }

            return vec.*;
        }

        ///  Computes the FFT on the input vector in place.
        ///  The input vector must be of size `fft_size`.
        ///
        /// - **Parameters**:
        ///     - `inout`: Input/output vector, modified in place.
        /// - **Returns**: Transformed `ComplexVector`. Throws an error if input size is invalid.
        pub fn fft(inout: *ComplexVector) Error!ComplexVector {
            if (inout.len != fft_size) return Error.invalid_input_size;

            return fftRadix2(inout, .forward);
        }

        /// Computes the inverse FFT on the input vector in place.
        /// The input vector must be of size `fft_size`.
        ///
        /// - **Parameters**:
        ///     - `inout`: Input/output vector, modified in place.
        /// - **Returns**: Transformed `ComplexVector`. Throws an error if input size is invalid.
        pub fn ifft(inout: *ComplexVector) Error!ComplexVector {
            if (inout.len != fft_size) return Error.invalid_input_size;

            var out = try fftRadix2(inout, .inverse);

            for (0..out.len) |i| {
                const len = ComplexType.init(@as(T, @floatFromInt(out.len)), 0);
                out.set(i, out.get(i).div(len));
            }

            return out;
        }

        /// Calculates the magnitude (amplitude) of each element in the `ComplexVector` and writes the result to the output buffer.
        /// Input and output lengths must match.
        ///
        /// - **Parameters**:
        ///     - `vec`: The `ComplexVector` containing complex FFT data.
        ///     - `out`: Output buffer to store magnitudes.
        /// - **Returns**: Filled output buffer. Throws an error if sizes do not match.
        pub fn magnitude(vec: *ComplexVector, out: []T) Error![]T {
            if (vec.len != out.len) return Error.invalid_input_size;

            for (0..vec.len) |i| {
                out[i] = vec.get(i).magnitude();
            }

            return out;
        }

        /// Computes the phase (angle) of each element in the `ComplexVector` and writes the result to the output buffer.
        ///
        /// - **Parameters**:
        ///     - `vec`: The `ComplexVector` containing complex FFT data.
        ///     - `out`: Output buffer to store phase angles.
        /// - **Returns**: Filled output buffer. Throws an error if sizes do not match.
        pub fn phase(vec: *ComplexVector, out: []T) Error![]T {
            if (vec.len != out.len) return Error.invalid_input_size;

            for (0..vec.len) |i| {
                const item = vec.get(i);
                out[i] = std.math.atan2(item.im, item.re);
            }

            return out;
        }

        /// Convolves two complex vectors using FFT and modifies the both inputs in place.
        /// Returns the avec as the result of the convolution.
        ///
        /// - **Parameters**:
        ///     - `avec`, `bvec`: Input vectors to be convolved.
        /// - **Returns**: Convolved `ComplexVector`. Throws an error if input sizes are invalid.
        fn convolve(avec: *ComplexVector, bvec: *ComplexVector) !ComplexVector {
            var avec_ffted = try fft(avec);
            const bvec_ffted = try fft(bvec);

            for (0..avec_ffted.len) |i| {
                avec_ffted.set(i, avec_ffted.get(i).mul(bvec_ffted.get(i)));
            }

            // iff normalizes the output
            return try ifft(&avec_ffted);
        }

        fn fftRadix2(inout: *ComplexVector, direction: Direction) Error!ComplexVector {
            const exp_table_len: usize = @divFloor(fft_size, 2);

            var exp_table = ComplexVector{};
            try exp_table.setCapacity(allocator, exp_table_len);
            defer exp_table.deinit(allocator);

            for (0..exp_table_len) |i| {
                const pi: T = if (direction == .inverse) -2.0 * std.math.pi else 2.0 * std.math.pi;
                const angle: T = pi * @as(T, @floatFromInt(i)) / @as(T, @floatFromInt(inout.len));
                const exp = ComplexType.init(std.math.cos(angle), -std.math.sin(angle));

                try exp_table.append(allocator, exp);
            }

            // bit-reversal permutation
            // https://en.wikipedia.org/wiki/Bit-reversal_permutation
            for (0..fft_size) |idx| {
                const rev_idx = reverseBits(idx, levels);

                if (idx > rev_idx) {
                    const tmp = inout.get(idx);
                    inout.set(idx, inout.get(rev_idx));
                    inout.set(rev_idx, tmp);
                }
            }

            // Cooley-Tukey decimation-in-time radix-2 FFT
            var full_size: usize = 2;

            while (full_size <= fft_size) : (full_size *= 2) {
                const half_size: usize = @divFloor(full_size, 2);
                const table_step: usize = @divFloor(inout.len, full_size);
                var idx: usize = 0;

                while (idx < fft_size) : (idx += full_size) {
                    var inner_idx = idx;
                    var table_idx: usize = 0;

                    while (inner_idx < idx + half_size) : (inner_idx += 1) {
                        const out_idx = inner_idx + half_size;

                        const tmp = inout.get(out_idx).mul(exp_table.get(table_idx));
                        var temp2 = inout.get(inner_idx);

                        inout.set(out_idx, temp2.sub(tmp));
                        inout.set(inner_idx, temp2.add(tmp));

                        table_idx += table_step;
                    }
                }

                // Prevent overflow in 'size *= 2'
                if (full_size == fft_size) break;
            }

            return inout.*;
        }
    };
}

/// `FourierDynamic` provides a flexible FFT API that supports heap allocation and dynamic FFT sizes.
/// It can handle non-power-of-two sizes using the Bluestein algorithm, although with reduced performance compared to radix-2 FFT.
///
/// - **FFT Size**: Dynamic and can vary at runtime. Power-of-two sizes are handled using radix-2 FFT, while non-power-of-two sizes are processed using the Bluestein algorithm.
/// - **T**: Supported types are `f32` and `f64`.
pub fn FourierDynamic(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("FourierTransforms only supports f32 and f64");
    }

    return struct {
        const ComplexType = std.math.Complex(T);
        const ComplexVector = std.MultiArrayList(ComplexType);

        /// A simple Discrete Fourier Transform (DFT) implementation for testing purposes.
        ///
        /// - **Parameters**:
        ///     - `allocator`: Allocator for dynamic memory management.
        ///     - `in`: Input vector with the audio signal.
        /// - **Returns**: DFT-transformed `ComplexVector`.
        pub fn dft(allocator: std.mem.Allocator, in: []T) !ComplexVector {
            var out = ComplexVector{};
            try out.setCapacity(allocator, in.len);

            const n = in.len;

            for (0..n) |k| {
                var sum = ComplexType.init(0.0, 0.0);

                for (0..n) |t| {
                    const angle = 2.0 *
                        std.math.pi *
                        @as(T, @floatFromInt(t)) *
                        @as(T, @floatFromInt(k)) /
                        @as(T, @floatFromInt(n));

                    const exp = ComplexType.init(std.math.cos(angle), -std.math.sin(angle));
                    sum = sum.add(exp.mul(ComplexType.init(in[t], 0)));
                }

                try out.append(allocator, sum);
            }

            return out;
        }

        /// Computes the FFT dynamically, choosing the appropriate algorithm based on input size (radix-2 or Bluestein).
        ///
        /// - **Parameters**:
        ///     - `allocator`: Allocator for dynamic memory management.
        ///     - `in`: Input vector.
        /// - **Returns**: FFT-transformed `ComplexVector`. Throws an error if input size is invalid.
        pub fn fft(allocator: std.mem.Allocator, in: []T) Error!ComplexVector {
            if (in.len == 0) return ComplexVector{};

            var inout = ComplexVector{};
            try inout.setCapacity(allocator, in.len);

            errdefer inout.deinit(allocator);

            for (in) |item| try inout.append(allocator, ComplexType.init(item, 0));

            if (isPowerOfTwo(in.len)) return try fftRadix2(allocator, &inout, .forward)
            // more complex algorithms are used for non power of two sizes
            else return try fftBluestein(allocator, &inout, .forward);
        }

        /// Computes the inverse FFT dynamically, applying either radix-2 or Bluestein as necessary.
        ///
        /// - **Parameters**:
        ///     - `allocator`: Allocator for dynamic memory management.
        ///     - `inout`: Input/output vector, modified in place.
        /// - **Returns**: Inverse FFT-transformed `ComplexVector`. Throws an error if input size is invalid.
        pub fn ifft(allocator: std.mem.Allocator, inout: *ComplexVector) Error!ComplexVector {
            if (inout.len == 0) return inout.*;

            var out = if (isPowerOfTwo(inout.len)) try fftRadix2(allocator, inout, .inverse) else try fftBluestein(allocator, inout, .inverse);

            // Scaling the output
            for (0..out.len) |i| {
                const len = ComplexType.init(@as(T, @floatFromInt(out.len)), 0);
                out.set(i, out.get(i).div(len));
            }

            return out;
        }

        /// Convolves two complex vectors using FFT. This method creates copies of the input vectors to avoid in-place modification.
        ///
        /// - **Parameters**:
        ///     - `allocator`: Allocator for dynamic memory management.
        ///     - `avec`, `bvec`: Input vectors to be convolved.
        /// - **Returns**: Convolved `ComplexVector`. Throws an error if input sizes are invalid.
        pub fn convolve(allocator: std.mem.Allocator, avec: []T, bvec: []T) !ComplexVector {
            var avec_complex = ComplexVector{};
            var bvec_complex = ComplexVector{};

            // avec_complex returns
            defer bvec_complex.deinit(allocator);

            try avec_complex.setCapacity(allocator, avec.len);
            try bvec_complex.setCapacity(allocator, bvec.len);

            for (avec) |item| try avec_complex.append(allocator, ComplexType.init(item, 0));
            for (bvec) |item| try bvec_complex.append(allocator, ComplexType.init(item, 0));

            return convolveInPlace(allocator, &avec_complex, &bvec_complex);
        }

        /// Calculates the magnitude (amplitude) of each element in the `ComplexVector` and allocates an output buffer to store the results.
        /// The input vector contains complex FFT data, and the output buffer will store the magnitudes.
        ///
        /// - **Parameters**:
        ///     - `allocator`: The memory allocator used to allocate the output buffer.
        ///     - `vec`: The `ComplexVector` containing complex FFT data.
        /// - **Returns**: Allocated buffer filled with magnitudes. Throws an error if allocation fails.
        pub fn magnitude(allocator: std.mem.Allocator, vec: *ComplexVector) Error![]T {
            const out = try allocator.alloc(T, vec.len);

            for (0..vec.len) |i| {
                out[i] = vec.get(i).magnitude();
            }

            return out;
        }

        /// Computes the phase (angle) of each element in the `ComplexVector` and allocates an output buffer to store the results.
        /// The input vector contains complex FFT data, and the output buffer will store the phase angles.
        ///
        /// - **Parameters**:
        ///     - `allocator`: The memory allocator used to allocate the output buffer.
        ///     - `vec`: The `ComplexVector` containing complex FFT data.
        /// - **Returns**: Allocated buffer filled with phase angles. Throws an error if allocation fails.
        pub fn phase(allocator: std.mem.Allocator, vec: *ComplexVector) Error![]T {
            const out = try allocator.alloc(T, vec.len);

            for (0..vec.len) |i| {
                const item = vec.get(i);
                out[i] = std.math.atan2(item.im, item.re);
            }

            return out;
        }

        // Private

        fn fftComplex(allocator: std.mem.Allocator, inout: *ComplexVector, direction: Direction) Error!ComplexVector {
            if (inout.len == 0) return ComplexVector{};

            if (isPowerOfTwo(inout.len)) return try fftRadix2(allocator, inout, direction)
            // more complex algorithms are used for non power of two sizes
            else return try fftBluestein(allocator, inout, direction);
        }

        fn fftRadix2(allocator: std.mem.Allocator, inout: *ComplexVector, direction: Direction) Error!ComplexVector {
            // sanity check for power of two
            if (!isPowerOfTwo(inout.len)) return Error.invalid_input_size;

            // calculate "levels" needed to split the input down to a single element
            const n: usize = inout.len;
            const levels: usize = std.math.log2(n);

            var exp_table = ComplexVector{};
            const exp_table_len: usize = @divFloor(inout.len, 2);

            defer exp_table.deinit(allocator);
            try exp_table.setCapacity(allocator, exp_table_len);

            for (0..exp_table_len) |i| {
                const pi: T = if (direction == .inverse) -2.0 * std.math.pi else 2.0 * std.math.pi;
                const angle: T = pi * @as(T, @floatFromInt(i)) / @as(T, @floatFromInt(inout.len));
                const exp = ComplexType.init(std.math.cos(angle), -std.math.sin(angle));

                try exp_table.append(allocator, exp);
            }

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

                if (size == inout.len) break;
            }

            return inout.*;
        }

        fn fftBluestein(allocator: std.mem.Allocator, inout: *ComplexVector, direction: Direction) Error!ComplexVector {
            var conv_len: usize = 1;

            // Find power of 2 conv_len such that -> conv_len  >= in.len * 2 + 1;
            while (conv_len / 2 < inout.len) {
                // sanity check for overflows
                if (conv_len > std.math.maxInt(usize) / 2) return Error.overflow;
                conv_len *= 2;
            }

            var exp_table = ComplexVector{};
            defer exp_table.deinit(allocator);

            var avec = ComplexVector{};
            defer avec.deinit(allocator);

            var bvec = ComplexVector{};
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
                const angle = pi * @as(T, @floatFromInt(idx)) / @as(T, @floatFromInt(inout.len));
                const exp = ComplexType.init(std.math.cos(angle), -std.math.sin(angle));
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
            avec = try convolveInPlace(allocator, &avec, &bvec);

            for (0..inout.len) |i| {
                inout.set(i, avec.get(i).mul(exp_table.get(i)));
            }

            return inout.*;
        }

        fn convolveInPlace(allocator: std.mem.Allocator, avec: *ComplexVector, bvec: *ComplexVector) !ComplexVector {
            var avec_ffted = try fftComplex(allocator, avec, Direction.forward);
            const bvec_ffted = try fftComplex(allocator, bvec, Direction.forward);

            for (0..avec_ffted.len) |i| {
                avec_ffted.set(i, avec_ffted.get(i).mul(bvec_ffted.get(i)));
            }

            var avec_inversed = try fftComplex(allocator, &avec_ffted, Direction.inverse);

            for (0..avec_inversed.len) |i| {
                const len = ComplexType.init(@as(T, @floatFromInt(avec.len)), 0);
                avec_inversed.set(i, avec_inversed.get(i).div(len));
            }

            return avec_inversed;
        }
    };
}

// Utility function t

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

const testing = std.testing;

test "FourierDynamic: dft simple" {
    const allocator = std.testing.allocator;
    var input_signal = [_]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75, -1.0 };

    const transforms = FourierDynamic(f32);
    var output = try transforms.dft(allocator, &input_signal);
    defer output.deinit(allocator);

    var i: usize = 0;
    for (output.items(.re), output.items(.im)) |re, im| {
        try testing.expectApproxEqRel(test_data.expected_simple_dft[i].re, re, 0.0001);
        try testing.expectApproxEqRel(test_data.expected_simple_dft[i].im, im, 0.0001);
        i += 1;
    }
}

test "FourierDynamic: dft sine" {
    const allocator = std.testing.allocator;

    const sineGeneration = waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var sine: [128]f32 = undefined;
    sineGeneration.generate(&sine);

    const transforms = FourierDynamic(f32);
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

test "FourierDynamic: fft simple power of 2" {
    const allocator = std.testing.allocator;
    var input_signal = [8]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };

    const transforms = FourierDynamic(f32);
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

test "FourierDynamic: fft simple non power of 2" {
    const allocator = std.testing.allocator;
    var input_signal = [9]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75, -1.0 };

    const transforms = FourierDynamic(f32);
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

test "FourierDynamic: inverse fft simple power of two" {
    const allocator = std.testing.allocator;
    var input_signal = [8]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, 0.75 };

    const transforms = FourierDynamic(f32);

    var fft_out = try transforms.fft(allocator, &input_signal);
    defer fft_out.deinit(allocator);

    var inversed = try transforms.ifft(allocator, &fft_out);

    for (0..input_signal.len) |i| {
        const inversed_item = inversed.get(i);
        try testing.expectApproxEqAbs(input_signal[i], inversed_item.re, 0.0001);
    }
}

test "FourierDynamic: inverse fft simple power non power of two" {
    const allocator = std.testing.allocator;
    var input_signal = [9]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, 0.75, -1.0 };

    const transforms = FourierDynamic(f32);

    var fft_out = try transforms.fft(allocator, &input_signal);
    defer fft_out.deinit(allocator);

    var inversed = try transforms.ifft(allocator, &fft_out);

    for (0..input_signal.len) |i| {
        const inversed_item = inversed.get(i);
        try testing.expectApproxEqAbs(input_signal[i], inversed_item.re, 0.0001);
    }
}

test "FourierDynamic: fft sine power of two" {
    const allocator = std.testing.allocator;

    const sineGeneration = waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var sine: [128]f32 = undefined;
    sineGeneration.generate(&sine);

    const transforms = FourierDynamic(f32);
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

test "FourierDynamic: inverse fft sine wave power non power of two" {
    const allocator = std.testing.allocator;

    const sineGeneration = waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var sine: [128]f32 = undefined;
    sineGeneration.generate(&sine);

    const transforms = FourierDynamic(f32);
    var output = try transforms.fft(allocator, &sine);
    defer output.deinit(allocator);

    var fft_out = try transforms.fft(allocator, &sine);
    defer fft_out.deinit(allocator);

    var inversed = try transforms.ifft(allocator, &fft_out);

    for (0..sine.len) |i| {
        const inversed_item = inversed.get(i);
        try testing.expectApproxEqAbs(sine[i], inversed_item.re, 0.0001);
    }
}

test "FourierDynamic: magnitude calculation" {
    const allocator = std.testing.allocator;
    const len = 8;

    const transform = FourierDynamic(f32);

    var input = [len]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };

    var complex_vector = try transform.fft(allocator, &input);
    defer complex_vector.deinit(allocator);

    const magnitudes = try transform.magnitude(allocator, &complex_vector);
    defer allocator.free(magnitudes);

    const expected = [len]f32{ 1.0, 2.613125929752753, 1.4142135623730951, 1.082392200292394, 1.0, 1.082392200292394, 1.4142135623730951, 2.613125929752753 };

    for (magnitudes, 0..magnitudes.len) |item, i| {
        try testing.expectApproxEqAbs(expected[i], item, 0.0001);
    }
}

test "FourierDynamic: phases calculation" {
    const allocator = std.testing.allocator;
    const len = 8;

    const transform = FourierDynamic(f32);

    var input = [len]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };

    var complex_vector = try transform.fft(allocator, &input);
    defer complex_vector.deinit(allocator);

    const phases = try transform.phase(allocator, &complex_vector);
    defer allocator.free(phases);
    const expected = [len]f32{ 0.0, -1.1780972450961724, -0.7853981633974483, -0.39269908169872425, 0.0, 0.39269908169872425, 0.7853981633974483, 1.1780972450961724 };

    for (phases, 0..phases.len) |item, i| {
        try testing.expectApproxEqAbs(expected[i], item, 0.0001);
    }
}

test "FourierDynamic: convolution" {
    const allocator = std.testing.allocator;

    var input_a = [_]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };
    var input_b = [_]f32{ 0.5, -0.5, 0.25, -0.25, 0.0, 0.75, -0.75, 1.0 };

    const transform = FourierDynamic(f32);

    var result = try transform.convolve(allocator, &input_a, &input_b);
    defer result.deinit(allocator);

    const expected = [8]f32{ 1.375, 0.12499999999999994, 0.375, -0.375, -0.625, 0.625, -1.125, 0.625 };

    for (0..result.len) |i| {
        try testing.expectApproxEqAbs(expected[i], result.get(i).re, 0.0001);
    }
}

test "FourierStatic: fft multiple simple input" {
    const allocator = std.testing.allocator;
    const fft_size: FFTSize = FFTSize.fft_8;
    var input_signal = [3][@intFromEnum(fft_size)]f32{
        .{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, 0.75 },
        .{ 0.3, 0.4, 0.9, 0.8, 0.4, 0.1, 0.0, 0.75 },
        .{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 },
    };

    // static fourier the fft_size is known at compile time
    // it does no interal heap allocator
    const transform = FourierStatic(f32, fft_size);

    // we need a complex vector to process the input
    // but the allocation can be done before the fft calculation
    // and it can be reused for multiple fft
    var complex_vec = try transform.createComplexVector(allocator, &input_signal[0]);
    defer complex_vec.deinit(allocator);

    // transform 3 times. we always modify the same complex vector
    for (0..input_signal.len) |i| {
        complex_vec = try transform.fft(&complex_vec);
        complex_vec = try transform.ifft(&complex_vec);

        // run 3 times reset the complex vector
        for (0..complex_vec.len) |j| {
            const item = complex_vec.get(j);
            try testing.expectApproxEqAbs(input_signal[i][j], item.re, 0.0001);
        }

        // reset the input signal
        if (i + 1 < input_signal.len) {
            complex_vec = try transform.setComplexVector(&complex_vec, &input_signal[i + 1]);
        }
    }
}

test "FourierStatic: magnitude calculation" {
    const allocator = std.testing.allocator;
    const len = 8;

    const transform = FourierStatic(f32, .fft_8);

    var input = [len]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };
    var complex_vector = try transform.createComplexVector(allocator, &input);
    defer complex_vector.deinit(allocator);

    complex_vector = try transform.fft(&complex_vector);

    var buffer: [len]f32 = undefined;

    const magnitudes = try transform.magnitude(&complex_vector, &buffer);
    const expected = [len]f32{ 1.0, 2.613125929752753, 1.4142135623730951, 1.082392200292394, 1.0, 1.082392200292394, 1.4142135623730951, 2.613125929752753 };

    for (magnitudes, 0..magnitudes.len) |item, i| {
        try testing.expectApproxEqAbs(expected[i], item, 0.0001);
    }
}

test "FourierStatic: phase calculation" {
    const allocator = std.testing.allocator;
    const len = 8;

    const transform = FourierStatic(f32, .fft_8);

    var input = [len]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };
    var complex_vector = try transform.createComplexVector(allocator, &input);
    defer complex_vector.deinit(allocator);

    complex_vector = try transform.fft(&complex_vector);

    var buffer: [len]f32 = undefined;

    const phases = try transform.phase(&complex_vector, &buffer);
    const expected = [len]f32{ 0.0, -1.1780972450961724, -0.7853981633974483, -0.39269908169872425, 0.0, 0.39269908169872425, 0.7853981633974483, 1.1780972450961724 };

    for (phases, 0..phases.len) |item, i| {
        try testing.expectApproxEqAbs(expected[i], item, 0.0001);
    }
}

test "FourierStatic: convolution" {
    const allocator = std.testing.allocator;

    var input_a = [_]f32{ 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75 };
    var input_b = [_]f32{ 0.5, -0.5, 0.25, -0.25, 0.0, 0.75, -0.75, 1.0 };

    const transform = FourierStatic(f32, .fft_8);

    var complex_a = try transform.createComplexVector(allocator, &input_a);
    defer complex_a.deinit(allocator);

    var complex_b = try transform.createComplexVector(allocator, &input_b);
    defer complex_b.deinit(allocator);

    var result = try transform.convolve(&complex_a, &complex_b);

    const expected = [8]f32{ 1.375, 0.12499999999999994, 0.375, -0.375, -0.625, 0.625, -1.125, 0.625 };

    for (0..result.len) |i| {
        try testing.expectApproxEqAbs(expected[i], result.get(i).re, 0.0001);
    }
}

test "bit reverse test n = 8" {
    const indices = [8]usize{ 0, 1, 2, 3, 4, 5, 6, 7 };
    const expected = [8]usize{ 0, 4, 2, 6, 1, 5, 3, 7 }; // Bit-reversed indices for n = 8
    const width = 3; // log2(8) = 3

    for (indices, 0..indices.len) |idx, i| {
        const result1 = reverseBits(idx, width);
        const result2 = reverseBitsDiscrete(idx, width);
        try testing.expectEqual(expected[i], result1);
        try testing.expectEqual(expected[i], result2);
    }
}

test "bit reverse test for n = 16" {
    const indices = [16]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    const expected = [16]usize{ 0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15 }; // Bit-reversed indices for n = 16
    const width = 4; // log2(16) = 4

    for (indices, 0..indices.len) |idx, i| {
        const result1 = reverseBits(idx, width);
        const result2 = reverseBitsDiscrete(idx, width);
        try testing.expectEqual(expected[i], result1);
        try testing.expectEqual(expected[i], result2);
    }
}
