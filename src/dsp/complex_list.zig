const std = @import("std");

pub fn ComplexList(comptime T: type) type {
    return struct {
        const Error = error{
            invalid_capacity,
        };

        const Self = @This();
        const ComplexType = std.math.Complex(T);

        data: []T,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
            return .{
                // twice the length for both real and imaginary parts
                .data = try allocator.alloc(T, len * 2),
                .allocator = allocator,
            };
        }
    };
}
