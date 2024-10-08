const std = @import("std");

pub const Error = error{
    out_of_bounds,
};

pub fn ComplexList(comptime T: type) type {
    return struct {
        const Self = @This();
        const ComplexType = std.math.Complex(T);

        data: []T,
        allocator: std.mem.Allocator,

        pub fn bytesRequired(len: usize) usize {
            return len * 2 * @sizeOf(T);
        }

        pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
            return .{
                // twice the length for both real and imaginary parts
                .data = try allocator.alloc(T, len * 2),
                .allocator = allocator,
            };
        }

        pub fn set(self: *Self, index: usize, value: ComplexType) !void {
            if (index * 2 >= self.data.len) {
                return Error.out_of_bounds;
            }

            self.data[index * 2] = value.re;
            self.data[index * 2 + 1] = value.im;
        }

        pub fn get(self: Self, index: usize) !ComplexType {
            if (index * 2 >= self.data.len) {
                return Error.out_of_bounds;
            }

            return ComplexType{ .re = self.data[index * 2], .im = self.data[index * 2 + 1] };
        }

        pub fn resize(self: *Self, new_len: usize) !void {
            if (new_len * 2 <= self.data.len) return;

            self.data = try self.allocator.realloc(self.data, new_len * 2);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }
    };
}

const testing = std.testing;

test "ComplexList init, set, get, resize, and deinit" {
    const allocator = std.testing.allocator;
    const Complex = std.math.Complex;

    // Test Initialization
    var list = try ComplexList(f64).init(allocator, 3);
    defer list.deinit();

    // Test Setting values
    try list.set(0, Complex(f64){ .re = 1.0, .im = 2.0 });
    try list.set(1, Complex(f64){ .re = 3.0, .im = 4.0 });
    try list.set(2, Complex(f64){ .re = 5.0, .im = 6.0 });

    // Test Getting values and comparing individual elements
    const value0 = try list.get(0);
    try testing.expectEqual(@as(f64, 1.0), value0.re);
    try testing.expectEqual(@as(f64, 2.0), value0.im);

    const value1 = try list.get(1);
    try testing.expectEqual(@as(f64, 3.0), value1.re);
    try testing.expectEqual(@as(f64, 4.0), value1.im);

    const value2 = try list.get(2);
    try testing.expectEqual(@as(f64, 5.0), value2.re);
    try testing.expectEqual(@as(f64, 6.0), value2.im);

    try list.resize(5);
    try list.set(3, Complex(f64){ .re = 7.0, .im = 8.0 });
    try list.set(4, Complex(f64){ .re = 9.0, .im = 10.0 });

    const value3 = try list.get(3);
    try testing.expectEqual(@as(f64, 7.0), value3.re);
    try testing.expectEqual(@as(f64, 8.0), value3.im);

    const value4 = try list.get(4);
    try testing.expectEqual(@as(f64, 9.0), value4.re);
    try testing.expectEqual(@as(f64, 10.0), value4.im);

    try testing.expectError(Error.out_of_bounds, list.get(6));

    try list.resize(2);

    const value4_after = try list.get(4);
    try testing.expectEqual(@as(f64, 9.0), value4_after.re);
    try testing.expectEqual(@as(f64, 10.0), value4_after.im);
}

test "ComplexList handles bad indexing and bad resize" {
    const allocator = std.testing.allocator;
    const Complex = std.math.Complex;

    var list = try ComplexList(f32).init(allocator, 2);
    defer list.deinit();

    try testing.expectError(Error.out_of_bounds, list.set(4, Complex(f32){ .re = 1.0, .im = 1.0 }));
    try testing.expectError(Error.out_of_bounds, list.get(3));

    try list.resize(10);
    try list.set(9, Complex(f32){ .re = 100.0, .im = 101.0 });

    const value9 = try list.get(9);
    try testing.expectEqual(@as(f32, 100.0), value9.re);
    try testing.expectEqual(@as(f32, 101.0), value9.im);
}
