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
        len: usize,

        pub fn bytesRequired(len: usize) usize {
            return len * 2 * @sizeOf(T);
        }

        pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
            return .{
                // twice the length for both real and imaginary parts
                .data = try allocator.alloc(T, len * 2),
                .allocator = allocator,
                .len = len,
            };
        }

        pub fn initFrom(allocator: std.mem.Allocator, data: []T) !Self {
            const complex_data = try allocator.alloc(T, data.len * 2);

            for (data, 0..data.len) |value, index| {
                complex_data[index * 2] = value;
                complex_data[index * 2 + 1] = 0;
            }

            return .{
                .data = complex_data,
                .allocator = allocator,
                .len = data.len,
            };
        }

        pub fn set(self: *Self, index: usize, value: ComplexType) !void {
            if (index * 2 >= self.data.len) {
                return Error.out_of_bounds;
            }

            self.data[index * 2] = value.re;
            self.data[index * 2 + 1] = value.im;
        }

        pub fn get(self: Self, index: usize) ?ComplexType {
            if (index * 2 >= self.data.len) {
                return null;
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
    const value0 = list.get(0) orelse unreachable;
    try testing.expectEqual(@as(f64, 1.0), value0.re);
    try testing.expectEqual(@as(f64, 2.0), value0.im);

    const value1 = list.get(1) orelse unreachable;
    try testing.expectEqual(@as(f64, 3.0), value1.re);
    try testing.expectEqual(@as(f64, 4.0), value1.im);

    const value2 = list.get(2) orelse unreachable;
    try testing.expectEqual(@as(f64, 5.0), value2.re);
    try testing.expectEqual(@as(f64, 6.0), value2.im);

    try list.resize(5);
    try list.set(3, Complex(f64){ .re = 7.0, .im = 8.0 });
    try list.set(4, Complex(f64){ .re = 9.0, .im = 10.0 });

    const value3 = list.get(3) orelse unreachable;
    try testing.expectEqual(@as(f64, 7.0), value3.re);
    try testing.expectEqual(@as(f64, 8.0), value3.im);

    const value4 = list.get(4) orelse unreachable;
    try testing.expectEqual(@as(f64, 9.0), value4.re);
    try testing.expectEqual(@as(f64, 10.0), value4.im);

    try testing.expectEqual(null, list.get(6));

    try list.resize(2);

    const value4_after = list.get(4) orelse unreachable;
    try testing.expectEqual(@as(f64, 9.0), value4_after.re);
    try testing.expectEqual(@as(f64, 10.0), value4_after.im);
}
test "ComplexList handles bad indexing and bad resize" {
    const allocator = std.testing.allocator;
    const Complex = std.math.Complex;

    var list = try ComplexList(f32).init(allocator, 2);
    defer list.deinit();

    try testing.expectError(Error.out_of_bounds, list.set(4, Complex(f32){ .re = 1.0, .im = 1.0 }));
    try testing.expectEqual(null, list.get(3));

    try list.resize(10);
    try list.set(9, Complex(f32){ .re = 100.0, .im = 101.0 });

    const value9 = list.get(9) orelse unreachable;
    try testing.expectEqual(@as(f32, 100.0), value9.re);
    try testing.expectEqual(@as(f32, 101.0), value9.im);
}

test "ComplexList initFrom data slice" {
    const allocator = std.testing.allocator;
    const T = f64;

    var a = [_]T{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 };

    var list = try ComplexList(T).initFrom(allocator, &a);
    defer list.deinit();

    for (0..a.len) |i| {
        const value = list.get(i) orelse unreachable;
        try testing.expectEqual(a[i], value.re);
        try testing.expectEqual(0.0, value.im);
    }
}
