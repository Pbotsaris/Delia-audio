const std = @import("std");

const log = std.log.scoped(.dsp);

const Error = error{
    out_of_bounds,
    invalid_matrix_dimensions,
    invalid_matrix_direction,
    unsupported_type,
};

const MatrixDirection = enum {
    row_major,
    column_major,
};

//pub fn ComplexMatrix(comptime T: type) type {
//
//}
//

pub fn Matrix(comptime T: type) type {
    return struct {
        const Self = @This();

        const Options = struct {
            direction: MatrixDirection = .row_major,
            rows: usize = 0,
            cols: usize = 0,
        };

        allocator: std.mem.Allocator,
        data: []T,
        rows: usize,
        cols: usize,
        direction: MatrixDirection,

        pub fn init(allocator: std.mem.Allocator, opts: Options) !Self {
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
                .Struct => return std.mem.zeroes(T),
                else => Error.unsupported_type,
            };

            for (0..self.rows) |row| {
                for (0..self.cols) |col| {
                    try self.set(row, col, zero);
                }
            }
        }

        pub fn get(self: Self, row: usize, col: usize) ?T {
            if (row >= self.rows or col >= self.cols) return null;

            return self.data[self.index(row, col)];
        }

        pub fn getRow(self: Self, row: usize) ?[]T {
            if (row >= self.rows) return null;

            return self.data[row * self.cols .. (row + 1) * self.cols];
        }

        // to get a column we must allocate because our data is stored in row-major order
        pub fn getCol(self: Self, allocator: std.mem.Allocator, col: usize) !?[]T {
            if (col >= self.cols) return null;

            const column = try allocator.alloc(T, self.rows);

            for (0..self.rows) |row| {
                column[row] = self.get(row, col) orelse {
                    allocator.free(column);
                    return null;
                };
            }

            return column;
        }

        pub fn set(self: *Self, row: usize, col: usize, value: T) !void {
            if (row >= self.rows or col >= self.cols) {
                // log.err("Out of bounds: {d}x{d} matrix, row: {d}, col: {d}", .{ self.rows, self.cols, row, col });
                return Error.out_of_bounds;
            }

            self.data[self.index(row, col)] = value;
        }

        pub fn setRow(self: *Self, row: usize, values: []T) !void {
            if (row >= self.rows or values.len != self.cols) {
                // log.err("Invalid row dimensions: {d}x{d} matrix, row: {d}, values: {d}", .{ self.rows, self.cols, row, values.len });
                return Error.out_of_bounds;
            }

            for (0..self.cols) |col| {
                self.data[row * self.cols + col] = values[col];
            }
        }

        pub fn setCol(self: *Self, col: usize, values: []T) !void {
            if (col >= self.cols or values.len != self.rows) {
                // log.err("Invalid column dimensions: {d}x{d} matrix, col: {d}, values: {d}", .{ self.rows, self.cols, col, values.len });
                return Error.out_of_bounds;
            }

            for (0..self.rows) |row| {
                try self.set(row, col, values[row]);
            }
        }

        pub fn mul(self: Self, allocator: std.mem.Allocator, other: Self) !Self {
            if (self.cols != other.rows) {
                // log.err("Invalid matrix dimensions: {d}x{d} * {d}x{d}", .{ self.rows, self.cols, other.rows, other.cols });
                return Error.invalid_matrix_dimensions;
            }

            var result = try Self.init(allocator, .{ .rows = self.rows, .cols = other.cols });

            for (0..self.rows) |row| {
                for (0..other.cols) |col| {
                    var sum: T = 0;
                    for (0..self.cols) |i| {
                        const col_value = other.get(i, col) orelse return Error.out_of_bounds;
                        const row_value = self.get(row, i) orelse return Error.out_of_bounds;

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
    try std.testing.expectError(Error.out_of_bounds, mat.set(3, 3, 7.0));
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
    try std.testing.expect(mul_result == Error.invalid_matrix_dimensions);
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

test "matrix set and get row" {
    const allocator = std.testing.allocator;

    // Initialize a 3x3 matrix
    var mat = try Matrix(f32).init(allocator, .{ .rows = 3, .cols = 3 });
    defer mat.deinit();

    try mat.zeros();

    // Set a row
    var row_values = [_]f32{ 1.0, 2.0, 3.0 };
    try mat.setRow(1, &row_values);

    // Verify the row has been set correctly
    const result_row = mat.getRow(1) orelse unreachable;

    for (0..mat.cols) |col| {
        try std.testing.expectEqual(result_row[col], row_values[col]);
    }

    try std.testing.expectEqual(mat.get(0, 0).?, 0.0);
    try std.testing.expectEqual(mat.get(2, 2).?, 0.0);
    //
    var invalid_row_values = [_]f32{ 7.0, 8.0, 9.0 };
    try std.testing.expectError(Error.out_of_bounds, mat.setRow(3, &invalid_row_values));

    var invalid_size_row = [_]f32{ 1.0, 2.0 }; // Not enough values for the row
    try std.testing.expectError(Error.out_of_bounds, mat.setRow(1, &invalid_size_row));
}

test "matrix set and get column" {
    const allocator = std.testing.allocator;

    var mat = try Matrix(f32).init(allocator, .{ .rows = 3, .cols = 3 });
    defer mat.deinit();

    try mat.zeros();

    var col_values = [_]f32{ 4.0, 5.0, 6.0 };
    try mat.setCol(2, &col_values);

    // note that to get a column we must allocate because our data is stored in row-major order
    const result_col = try mat.getCol(allocator, 2) orelse unreachable;
    defer allocator.free(result_col);

    for (0..mat.rows) |row| {
        try std.testing.expectEqual(mat.get(row, 2).?, col_values[row]);
    }

    try std.testing.expectEqual(mat.get(0, 0).?, 0.0);
    try std.testing.expectEqual(mat.get(1, 1).?, 0.0);

    var invalid_col_values = [_]f32{ 7.0, 8.0, 9.0 };
    try std.testing.expectError(Error.out_of_bounds, mat.setCol(3, &invalid_col_values));

    var invalid_size_col = [_]f32{ 4.0, 5.0 }; // Not enough values for the column
    try std.testing.expectError(Error.out_of_bounds, mat.setCol(2, &invalid_size_col));
}

test "get row and column out of bounds" {
    const allocator = std.testing.allocator;

    var mat = try Matrix(f32).init(allocator, .{ .rows = 3, .cols = 3 });
    defer mat.deinit();

    try std.testing.expect(mat.getRow(3) == null);

    try std.testing.expect(try mat.getCol(allocator, 3) == null);
}
