const std = @import("std");
const transforms = @import("transforms.zig");
const data_structures = @import("data_structures.zig");
const utils = @import("utils.zig");
const waves = @import("waves.zig");
const test_data = @import("test_data.zig");

const Windowfunction = enum {
    hann,
    blackman,
};

pub fn ShortTimeFourierTransform(comptime T: type, comptime window_size: transforms.WindowSize) type {
    const transform = transforms.FourierStatic(T, window_size);
    const Matrix = data_structures.Matrix(T);
    const win_size: usize = @intFromEnum(window_size);

    const Window = WindowTable(T, win_size);

    return struct {
        const Self = @This();

        hop_size: usize,
        win_table: Window,

        pub fn init(hop_size: usize, comptime window: Windowfunction) Self {
            return .{
                .hop_size = hop_size,
                // we precompute the window table and and sum
                .win_table = Window.init(window),
            };
        }

        pub fn stft(self: Self, allocator: std.mem.Allocator, input: []T) !Matrix {
            const n_windows: usize = @divFloor((input.len - win_size), self.hop_size) + 1;

            std.debug.print("n_windows: {}\n", .{n_windows});

            var output = try Matrix.init(allocator, @divFloor(win_size, 2) + 1, n_windows);
            var magnitude_buffer: [win_size]T = undefined;

            // complex_inout is allocated on the stack and reused for each window
            var complex_buffer: [win_size * @sizeOf(transform.ComplexVector)]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&complex_buffer);
            const static_allocator = fba.allocator();
            var complex_inout = try transform.createUninitializedComplexVector(static_allocator);

            for (0..n_windows) |win_index| {
                const start = win_index * self.hop_size;
                const segment = input[start .. start + win_size];

                for (0..win_size) |i| {
                    segment[i] *= self.win_table.table[i] / self.win_table.sum;
                }

                // TODO: don't return magnitudes, return the complex vector
                complex_inout = try transform.fillComplexVector(&complex_inout, segment);
                complex_inout = try transform.fft(&complex_inout);
                const magnitudes = try transform.magnitude(complex_inout, .decibel, &magnitude_buffer);

                // we only needs the first half of the magnitudes under the Nyquist limit
                try output.setCol(win_index, magnitudes[0 .. @divFloor(win_size, 2) + 1]);
            }

            return output;
        }
    };
}

fn WindowTable(comptime T: type, comptime window_size: usize) type {
    return struct {
        const Self = @This();
        const util = utils.Utils(T);

        sum: T,
        table: [window_size]T,

        fn init(comptime win_func: Windowfunction) Self {
            var s = Self{
                .sum = 0,
                .table = undefined,
            };

            for (0..window_size) |i| {
                const wf = switch (win_func) {
                    .hann => util.hanning(i, window_size),
                    .blackman => util.blackman(i, window_size),
                };

                s.sum += wf;
                s.table[i] = wf;
            }

            return s;
        }
    };
}

//test "Short Time Fourier Transform" {
//    const allocator = std.testing.allocator;
//
//    const stft = ShortTimeFourierTransform(f32, .wz_1024).init(512, .hann);
//
//    var input: [4096]f32 = undefined;
//    const sine = waves.Sine(f32).init(400.0, 1.0, 44100.0);
//
//    const sine_input = sine.generate(&input);
//    var mat = try stft.stft(allocator, sine_input);
//
//    try std.testing.expectEqual(mat.rows, test_data.stft_expected.len);
//    try std.testing.expectEqual(mat.cols, test_data.stft_expected[0].len);
//
//    for (0..mat.rows) |row| {
//        for (0..mat.cols) |col| {
//            const expected = test_data.stft_expected[row][col];
//            try std.testing.expectApproxEqAbs(expected, mat.get(row, col).?, 0.0001);
//        }
//    }
//
//    defer mat.deinit();
//}
