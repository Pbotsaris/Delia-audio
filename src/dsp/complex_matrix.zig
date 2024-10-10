const std = @import("std");
const utilities = @import("utils.zig");
const complex_list = @import("complex_list.zig");

const log = std.log.scoped(.dsp);

const MatrixError = error{
    out_of_bounds,
    invalid_matrix_dimensions,
    invalid_matrix_direction,
    unsupported_type,
};

const MatrixDirection = enum {
    row_major,
    column_major,
};

const MatrixOptions = struct {
    direction: MatrixDirection = .row_major,
    rows: usize = 0,
    cols: usize = 0,
};

pub fn ComplexMatrix(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("ComplexMatrix only supports f32 and f64 types");
    }

    return struct {
        const Self = @This();

        pub const ComplexType = std.math.Complex(T);
        pub const ComplexList = complex_list.ComplexList(T);
        pub const Error = MatrixError;

        allocator: std.mem.Allocator,
        data: []T,
        rows: usize,
        cols: usize,
        direction: MatrixDirection,

        pub fn init(allocator: std.mem.Allocator, opts: MatrixOptions) !Self {
            return .{
                .allocator = allocator,
                // Allocate twice the space for complex numbers
                .data = try allocator.alloc(T, opts.rows * opts.cols * 2),
                .rows = opts.rows,
                .cols = opts.cols,
                .direction = opts.direction,
            };
        }

        pub fn zeros(self: *Self) !void {
            for (0..self.data.len) |i| {
                self.data[i] = 0.0;
            }
        }

        pub fn get(self: Self, row: usize, col: usize) ?ComplexType {
            if (row >= self.rows or col >= self.cols) return null;

            const re = self.data[self.index(row, col)];
            const im = self.data[self.index(row, col) + 1];

            return ComplexType.init(re, im);
        }

        pub fn getDimensionView(self: Self, i: usize) !ComplexList {
            const data = switch (self.direction) {
                .row_major => row: {
                    if (i >= self.rows) return MatrixError.out_of_bounds;
                    break :row self.data[i * self.cols * 2 .. (i + 1) * self.cols * 2];
                },
                .column_major => col: {
                    if (i >= self.cols) return MatrixError.out_of_bounds;
                    break :col self.data[i * self.rows * 2 .. (i + 1) * self.rows * 2];
                },
            };

            return ComplexList.initUnowned(self.allocator, data);
        }

        pub fn set(self: *Self, row: usize, col: usize, value: ComplexType) !void {
            if (row >= self.rows or col >= self.cols) {
                //log.err("Out of bounds: {d}x{d} matrix, row: {d}, col: {d}", .{ self.rows, self.cols, row, col });
                return MatrixError.out_of_bounds;
            }
            self.data[self.index(row, col)] = value.re;
            self.data[self.index(row, col) + 1] = value.im;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        inline fn index(self: Self, row: usize, col: usize) usize {
            return switch (self.direction) {
                .row_major => (row * self.cols + col) * 2,
                .column_major => (col * self.rows + row) * 2,
            };
        }
    };
}

pub fn Matrix(comptime T: type) type {
    const info = @typeInfo(T);

    if (info != .Int and info != .Float) {
        @compileError("Matrix only supports integer and floating point types");
    }

    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        data: []T,
        rows: usize,
        cols: usize,
        direction: MatrixDirection,

        pub fn init(allocator: std.mem.Allocator, opts: MatrixOptions) !Self {
            return .{
                .allocator = allocator,
                .data = try allocator.alloc(T, opts.rows * opts.cols),
                .rows = opts.rows,
                .cols = opts.cols,
                .direction = opts.direction,
            };
        }

        pub fn zeros(self: *Self) !void {
            const zero = switch (@typeInfo(T)) {
                .Int => 0,
                .Float => 0.0,
                else => MatrixError.unsupported_type,
            };

            for (0..self.data.len) |i| {
                self.data[i] = zero;
            }
        }

        pub fn get(self: Self, row: usize, col: usize) ?T {
            if (row >= self.rows or col >= self.cols) return null;

            return self.data[self.index(row, col)];
        }

        pub fn set(self: *Self, row: usize, col: usize, value: T) !void {
            if (row >= self.rows or col >= self.cols) {
                // log.err("Out of bounds: {d}x{d} matrix, row: {d}, col: {d}", .{ self.rows, self.cols, row, col });
                return MatrixError.out_of_bounds;
            }

            self.data[self.index(row, col)] = value;
        }

        pub fn setRow(self: *Self, row: usize, values: []T) !void {
            if (row >= self.rows or values.len != self.cols) {
                // log.err("Invalid row dimensions: {d}x{d} matrix, row: {d}, values: {d}", .{ self.rows, self.cols, row, values.len });
                return MatrixError.out_of_bounds;
            }

            for (0..self.cols) |col| {
                self.data[row * self.cols + col] = values[col];
            }
        }

        pub fn setCol(self: *Self, col: usize, values: []T) !void {
            if (col >= self.cols or values.len != self.rows) {
                // log.err("Invalid column dimensions: {d}x{d} matrix, col: {d}, values: {d}", .{ self.rows, self.cols, col, values.len });
                return MatrixError.out_of_bounds;
            }

            for (0..self.rows) |row| {
                try self.set(row, col, values[row]);
            }
        }

        pub fn mul(self: Self, allocator: std.mem.Allocator, other: Self) !Self {
            if (self.cols != other.rows) {
                // log.err("Invalid matrix dimensions: {d}x{d} * {d}x{d}", .{ self.rows, self.cols, other.rows, other.cols });
                return MatrixError.invalid_matrix_dimensions;
            }

            var result = try Self.init(allocator, .{ .rows = self.rows, .cols = other.cols });

            for (0..self.rows) |row| {
                for (0..other.cols) |col| {
                    var sum: T = 0;
                    for (0..self.cols) |i| {
                        const col_value = other.get(i, col) orelse return MatrixError.out_of_bounds;
                        const row_value = self.get(row, i) orelse return MatrixError.out_of_bounds;

                        sum += row_value * col_value;
                    }

                    try result.set(row, col, sum);
                }
            }

            return result;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        inline fn index(self: Self, row: usize, col: usize) usize {
            return switch (self.direction) {
                .row_major => row * self.cols + col,
                .column_major => col * self.rows + row,
            };
        }
    };
}

test "matrix initialization and basic operations" {
    const allocator = std.testing.allocator;

    // Test matrix initialization
    var mat = try Matrix(f32).init(allocator, .{ .rows = 2, .cols = 3 });
    defer mat.deinit();

    try std.testing.expect(mat.rows == 2);
    try std.testing.expect(mat.cols == 3);

    // Test setting and getting elements
    try mat.set(0, 0, 1.0);
    try mat.set(0, 1, 2.0);
    try mat.set(0, 2, 3.0);
    try mat.set(1, 0, 4.0);
    try mat.set(1, 1, 5.0);
    try mat.set(1, 2, 6.0);

    try std.testing.expect(mat.get(0, 0).? == 1.0);
    try std.testing.expect(mat.get(0, 1).? == 2.0);
    try std.testing.expect(mat.get(0, 2).? == 3.0);
    try std.testing.expect(mat.get(1, 0).? == 4.0);
    try std.testing.expect(mat.get(1, 1).? == 5.0);
    try std.testing.expect(mat.get(1, 2).? == 6.0);

    // Test out-of-bounds access
    try std.testing.expect(mat.get(2, 0) == null);
    try std.testing.expect(mat.get(0, 3) == null);

    // Test invalid set (out-of-bounds)
    try std.testing.expectError(MatrixError.out_of_bounds, mat.set(3, 3, 7.0));
}

test "matrix multiplication" {
    const allocator = std.testing.allocator;

    // Matrix A: 2x3
    var matA = try Matrix(f32).init(allocator, .{ .rows = 2, .cols = 3 });
    defer matA.deinit();
    try matA.set(0, 0, 1.0);
    try matA.set(0, 1, 2.0);
    try matA.set(0, 2, 3.0);
    try matA.set(1, 0, 4.0);
    try matA.set(1, 1, 5.0);
    try matA.set(1, 2, 6.0);

    // Matrix B: 3x2
    var matB = try Matrix(f32).init(allocator, .{ .rows = 3, .cols = 2 });
    defer matB.deinit();
    try matB.set(0, 0, 7.0);
    try matB.set(0, 1, 8.0);
    try matB.set(1, 0, 9.0);
    try matB.set(1, 1, 10.0);
    try matB.set(2, 0, 11.0);
    try matB.set(2, 1, 12.0);

    // Perform matrix multiplication: C = A * B
    var result = try matA.mul(allocator, matB);
    defer result.deinit();

    try std.testing.expect(result.rows == 2);
    try std.testing.expect(result.cols == 2);

    // Verify matrix multiplication results
    try std.testing.expect(result.get(0, 0) == 58.0); // (1*7 + 2*9 + 3*11)
    try std.testing.expect(result.get(0, 1) == 64.0); // (1*8 + 2*10 + 3*12)
    try std.testing.expect(result.get(1, 0) == 139.0); // (4*7 + 5*9 + 6*11)
    try std.testing.expect(result.get(1, 1) == 154.0); // (4*8 + 5*10 + 6*12)
}

test "matrix multiplication invalid dimensions" {
    const allocator = std.testing.allocator;

    // Matrix A: 2x3
    var matA = try Matrix(f32).init(allocator, .{ .rows = 2, .cols = 3 });
    defer matA.deinit();

    // Matrix B: 4x2 (incompatible dimensions for multiplication)
    var matB = try Matrix(f32).init(allocator, .{ .rows = 4, .cols = 2 });
    defer matB.deinit();

    // Attempting to multiply A * B should return an error
    const mul_result = matA.mul(allocator, matB);
    try std.testing.expect(mul_result == MatrixError.invalid_matrix_dimensions);
}

test "matrix intializes to zero" {
    const allocator = std.testing.allocator;

    var mat = try Matrix(f32).init(allocator, .{ .rows = 3, .cols = 3 });
    defer mat.deinit();

    try mat.zeros();

    for (0..3) |row| {
        for (0..3) |col| try std.testing.expectEqual(mat.get(row, col).?, 0.0);
    }
}
// Complex

test "ComplexMatrix initialization and basic operations" {
    const allocator = std.testing.allocator;

    // Test matrix initialization
    var mat = try ComplexMatrix(f32).init(allocator, .{ .rows = 2, .cols = 3, .direction = .row_major });
    defer mat.deinit();

    try std.testing.expect(mat.rows == 2);
    try std.testing.expect(mat.cols == 3);

    // Test setting and getting elements
    try mat.set(0, 0, std.math.Complex(f32).init(1.0, 0.0));
    try mat.set(0, 1, std.math.Complex(f32).init(2.0, 0.0));
    try mat.set(0, 2, std.math.Complex(f32).init(3.0, 0.0));
    try mat.set(1, 0, std.math.Complex(f32).init(4.0, 0.0));
    try mat.set(1, 1, std.math.Complex(f32).init(5.0, 0.0));
    try mat.set(1, 2, std.math.Complex(f32).init(6.0, 0.0));

    try std.testing.expectEqualDeep(mat.get(0, 0).?, std.math.Complex(f32).init(1.0, 0.0));
    try std.testing.expectEqualDeep(mat.get(0, 1).?, std.math.Complex(f32).init(2.0, 0.0));
    try std.testing.expectEqualDeep(mat.get(0, 2).?, std.math.Complex(f32).init(3.0, 0.0));
    try std.testing.expectEqualDeep(mat.get(1, 0).?, std.math.Complex(f32).init(4.0, 0.0));
    try std.testing.expectEqualDeep(mat.get(1, 1).?, std.math.Complex(f32).init(5.0, 0.0));
    try std.testing.expectEqualDeep(mat.get(1, 2).?, std.math.Complex(f32).init(6.0, 0.0));

    // Test out-of-bounds access
    try std.testing.expectEqual(mat.get(2, 0), null);
    try std.testing.expectEqual(mat.get(0, 3), null);

    // Test invalid set (out-of-bounds)
    try std.testing.expectError(MatrixError.out_of_bounds, mat.set(3, 3, std.math.Complex(f32).init(7.0, 0.0)));
}

test "ComplexMatrix initializes to zero" {
    const allocator = std.testing.allocator;

    var mat = try ComplexMatrix(f32).init(allocator, .{ .rows = 3, .cols = 3, .direction = .row_major });
    defer mat.deinit();

    try mat.zeros();

    for (0..3) |row| {
        for (0..3) |col| {
            const value = mat.get(row, col) orelse unreachable;
            try std.testing.expect(value.re == 0.0 and value.im == 0.0);
        }
    }
}

test "ComplexMatrix set and get row or column based on direction" {
    const allocator = std.testing.allocator;

    // Initialize a 3x3 matrix
    var mat_row = try ComplexMatrix(f32).init(allocator, .{ .rows = 3, .cols = 3, .direction = .row_major });
    defer mat_row.deinit();

    try mat_row.zeros();

    // Set row-major direction and test row
    const row_values = [_]f32{ 1.0, 2.0, 3.0 };
    const complex_values: [3]std.math.Complex(f32) = .{
        std.math.Complex(f32).init(row_values[0], 0.0),
        std.math.Complex(f32).init(row_values[1], 0.0),
        std.math.Complex(f32).init(row_values[2], 0.0),
    };

    for (0..3) |col| {
        try mat_row.set(1, col, complex_values[col]);
    }

    const result_row = try mat_row.getDimensionView(1);

    for (0..3) |col| {
        try std.testing.expectEqualDeep(result_row.get(col).?, complex_values[col]);
    }

    // Set column-major direction and test column

    var mat_col = try ComplexMatrix(f32).init(allocator, .{ .rows = 3, .cols = 3, .direction = .column_major });
    defer mat_col.deinit();

    const col_values = [_]f32{ 4.0, 5.0, 6.0 };
    const complex_col_values: [3]std.math.Complex(f32) = .{
        std.math.Complex(f32).init(col_values[0], 0.0),
        std.math.Complex(f32).init(col_values[1], 0.0),
        std.math.Complex(f32).init(col_values[2], 0.0),
    };

    for (0..3) |col| {
        try mat_col.set(col, 2, complex_col_values[col]);
    }

    const result_col = try mat_col.getDimensionView(2);
    for (0..3) |row| {
        try std.testing.expectEqualDeep(result_col.get(row).?, complex_col_values[row]);
    }
}

test "ComplexMatrix out-of-bounds access for row or column" {
    const allocator = std.testing.allocator;

    var mat = try ComplexMatrix(f32).init(allocator, .{ .rows = 3, .cols = 3, .direction = .row_major });
    defer mat.deinit();

    try std.testing.expectError(MatrixError.out_of_bounds, mat.getDimensionView(3));
}
