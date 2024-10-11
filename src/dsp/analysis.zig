const std = @import("std");
const transforms = @import("transforms.zig");
const ComplexMatrix = @import("complex_matrix.zig").ComplexMatrix;
const ComplexList = @import("complex_list.zig").ComplexList;
const utils = @import("utils.zig");
const waves = @import("waves.zig");
const test_data = @import("test_data.zig");

const log = std.log.scoped(.stft);

pub const Windowfunction = enum {
    hann,
    blackman,
};

pub const Error = error{
    invalid_hop_size,
    invalid_input_size,
};

pub const HopSize = enum(usize) {
    eighth_window = 8,
    quarter_window = 4,
    half_window = 2,
    three_quarter_window = 34,

    const Self = @This();

    pub fn toInt(self: Self) usize {
        return if (self == .three_quarter_window) 4 else @intFromEnum(self);
    }

    pub fn calcSize(self: Self, win_size: usize) usize {
        return @divFloor(win_size, self.toInt());
    }
};

pub fn ShortTimeFourierStatic(comptime T: type, comptime window_size: transforms.WindowSize) type {
    if (T != f32 and T != f64) {
        @compileError("Short Time Fourier Transform only supports f32 and f64 types");
    }

    return struct {
        const Self = @This();
        const Matrix = ComplexMatrix(T);
        const List = ComplexList(T);
        const Window = WindowTable();

        pub const Options = struct {
            comptime window_function: Windowfunction = .hann,
            hop_size: HopSize = .half_window,
            normalize: bool = true,
        };

        const transform = transforms.FourierStatic(T, window_size);
        const win_size: usize = @intFromEnum(window_size);

        hop_size: usize,
        win_table: Window,
        normalize: bool,

        pub fn init(opts: Options) !Self {
            if (opts.hop_size.toInt() > win_size) {
                log.err("Hop size {d} is greater than window size {d}\n", .{ opts.hop_size.toInt(), win_size });
                return Error.invalid_hop_size;
            }

            return .{
                .hop_size = opts.hop_size.calcSize(win_size),
                // we precompute the window table and and sum
                .win_table = Window.init(opts.window_function),
                .normalize = opts.normalize,
            };
        }

        pub fn stft(self: Self, allocator: std.mem.Allocator, input: []T) !Matrix {
            if (input.len < win_size) {
                log.err("Input size {d} is less than window size {d}\n", .{ input.len, win_size });
                return Error.invalid_input_size;
            }

            const n_windows: usize = @divFloor((input.len - win_size), self.hop_size) + 1;

            // Rows are the number of windows / time slices
            // Columns are the number of frequencies & complex numbers
            var output = try Matrix.init(allocator, .{
                .rows = n_windows,
                .cols = @divFloor(win_size, 2) + 1,
                .direction = .column_major,
            });

            try output.zeros();

            // inout is allocated on the stack and reused for each window
            var list_buf: [win_size * @sizeOf(List.ComplexType) + 1]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&list_buf);
            const static_allocator = fba.allocator();

            var inout = try List.init(static_allocator, win_size);

            for (0..n_windows) |win_index| {
                const start = win_index * self.hop_size;
                const segment = input[start .. start + win_size];

                for (0..win_size) |i| {
                    segment[i] *= self.win_table.table[i];
                    if (self.normalize) segment[i] /= self.win_table.sum;
                }

                inout = try transform.fillComplexVector(&inout, segment);
                inout = try transform.fft(&inout);

                // the matrix is sized to the Nyquist limit
                // so the negative frequencies in inout are discarded
                try output.setRowOrColumn(win_index, inout);
            }

            return output;
        }

        fn WindowTable() type {
            return struct {
                const WinTable = @This();
                const util = utils.Utils(T);
                const wz: usize = @intFromEnum(window_size);

                sum: T,
                table: [wz]T,

                fn init(comptime win_func: Windowfunction) WinTable {
                    var s = WinTable{
                        .sum = 0,
                        .table = undefined,
                    };

                    for (0..wz) |i| {
                        const window_func = switch (win_func) {
                            .hann => util.hanning(i, wz),
                            .blackman => util.blackman(i, wz),
                        };

                        s.sum += window_func;
                        s.table[i] = window_func;
                    }

                    return s;
                }
            };
        }
    };
}

fn ShortTimeFourierDynamic(comptime T: type) type {
    return struct {
        const Self = @This();
        const transform = transforms.FourierDynamic(T);
        const Matrix = ComplexMatrix(T);
        const List = ComplexList(T);

        const Options = struct {
            window_size: transforms.WindowSize,
            hop_size: HopSize,
            window_function: Windowfunction = .hann,
            normalize: bool = false,
        };

        const WindowTable = struct {
            const util = utils.Utils(T);

            sum: T,
            table: []T,
            allocator: std.mem.Allocator,

            pub fn init(allocator: std.mem.Allocator, win_func: Windowfunction, window_size: usize) !WindowTable {
                var table = try allocator.alloc(T, window_size);
                var sum: T = 0.0;

                for (0..window_size) |i| {
                    const window_func: T = switch (win_func) {
                        .hann => util.hanning(i, window_size),
                        .blackman => util.blackman(i, window_size),
                    };

                    sum += window_func;
                    table[i] = window_func;
                }

                return .{
                    .sum = sum,
                    .table = table,
                    .allocator = allocator,
                };
            }

            pub fn deinit(self: WindowTable) void {
                self.allocator.free(self.table);
            }
        };

        window_size: usize,
        hop_size: usize,
        normalize: bool,
        win_table: WindowTable,
        window: Windowfunction,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, opts: Options) !Self {
            if (opts.hop_size.toInt() > @intFromEnum(opts.window_size)) {
                log.err("Hop size {d} is greater than window size {d}\n", .{ opts.hop_size.toInt(), @intFromEnum(opts.window_size) });
                return Error.invalid_hop_size;
            }
            return .{
                .window_size = @intFromEnum(opts.window_size),
                .hop_size = opts.hop_size.calcSize(@intFromEnum(opts.window_size)),
                .normalize = opts.normalize,
                .win_table = try WindowTable.init(allocator, opts.window_function, @intFromEnum(opts.window_size)),
                .window = opts.window_function,
                .allocator = allocator,
            };
        }

        pub fn stftAlloc(self: Self, input: []T) !Matrix {
            if (input.len < self.window_size) {
                log.err("Input size {d} is less than window size {d}\n", .{ input.len, self.window_size });
                return Error.invalid_input_size;
            }

            const n_windows: usize = @divFloor((input.len - self.window_size), self.hop_size) + 1;

            const output = try Matrix.init(self.allocator, .{
                .rows = n_windows,
                .cols = @divFloor(self.window_size, 2) + 1,
                .direction = .column_major,
            });

            try output.zeros();

            for (0..n_windows) |win_index| {
                const start = win_index * self.hop_size;
                const segment = input[start .. start + self.window_size];

                for (0..self.window_size) |i| {
                    segment[i] *= self.win_table.table[i];
                    if (self.normalize) segment[i] /= self.win_table.sum;
                }

                var inout = try transform.fft(self.allocator, segment);
                defer inout.deinit();

                // the matrix is sized to the Nyquist limit
                // so the negative frequencies in inout are discarded
                try output.setRowOrColumn(win_index, inout);
            }

            return output;
        }

        pub fn deinit(self: Self) void {
            self.win_table.deinit();
        }
    };
}

test "ShortTimeFourierStatic: Initialization" {
    var stft = try ShortTimeFourierStatic(f32, .wz_64).init(.{
        .window_function = .hann,
        .hop_size = .quarter_window,
    });
    try std.testing.expectEqual(stft.hop_size, 16);

    stft = try ShortTimeFourierStatic(f32, .wz_64).init(.{
        .window_function = .hann,
        .hop_size = .eighth_window,
    });
    try std.testing.expectEqual(stft.hop_size, 8);

    stft = try ShortTimeFourierStatic(f32, .wz_64).init(.{
        .window_function = .hann,
        .hop_size = .half_window,
    });

    try std.testing.expectEqual(stft.hop_size, 32);

    const err = ShortTimeFourierStatic(f32, .wz_2).init(.{
        .window_function = .hann,
        .hop_size = .quarter_window,
    });

    try std.testing.expectError(Error.invalid_hop_size, err);
}

test "ShortTimeFourierStatic: STFT" {
    const allocator = std.testing.allocator;

    const stft = try ShortTimeFourierStatic(f32, .wz_64).init(.{
        .window_function = .hann,
        .hop_size = .quarter_window,
        .normalize = false,
    });

    try std.testing.expectEqual(stft.hop_size, 16);

    var input: [128]f32 = undefined;
    const sine = waves.Sine(f32).init(400.0, 1.0, 44100.0);

    const sine_input = sine.generate(&input);

    var mat = try stft.stft(allocator, sine_input);
    defer mat.deinit();

    try std.testing.expectEqual(mat.rows, test_data.stft_expected[0].len);
    try std.testing.expectEqual(mat.cols, test_data.stft_expected.len);

    for (0..mat.rows) |row| {
        for (0..mat.cols) |col| {
            const expected = test_data.stft_expected[col][row];
            const actual = mat.get(row, col).?;

            _ = expected;
            _ = actual;

            //   std.debug.print("Expected ({d}x{d}): re: {d:.4}, im: {d:.4}\n", .{ row, col, expected.re, expected.im });
            //  std.debug.print("Actual   ({d}x{d}): re: {d:.4}, im: {d:.4}\n", .{ row, col, actual.re, actual.im });
            //  try std.testing.expectApproxEqAbs(expected.re, actual.re, 0.1);
            //  try std.testing.expectApproxEqAbs(expected.im, actual.im, 0.1);
        }
    }
}

test "ShortTimeFourierStatic: returns an error when input size is less than window size" {
    const allocator = std.testing.allocator;
    const short_time = try ShortTimeFourierStatic(f64, .wz_512).init(.{});

    var input: [128]f64 = undefined;
    const sine = waves.Sine(f64).init(400.0, 1.0, 44100.0);

    const sine_input = sine.generate(&input);
    const err = short_time.stft(allocator, sine_input);

    try std.testing.expectError(Error.invalid_input_size, err);
}

test "ShortTimeFourierDynamic: Initialization" {
    const allocator = std.testing.allocator;

    const stft = try ShortTimeFourierDynamic(f32).init(allocator, .{
        .window_size = .wz_64,
        .hop_size = .quarter_window,
        .window_function = .hann,
        .normalize = false,
    });

    defer stft.deinit();

    try std.testing.expectEqual(stft.hop_size, 16);
    try std.testing.expectEqual(stft.window_size, 64);
    try std.testing.expectEqual(stft.normalize, false);
    try std.testing.expectEqual(stft.window, .hann);
}
