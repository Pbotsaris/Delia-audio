const std = @import("std");

pub fn ComplexVector(comptime T: type) type {
    return struct {
        const Self = @This();
        const ComplexType = std.math.Complex(T);
        const MultiArrayList = std.MultiArrayList(ComplexType);

        vector: MultiArrayList,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var vector = MultiArrayList{};
            try vector.setCapacity(allocator, capacity);

            return Self{
                .vector = vector,
                .allocator = allocator,
            };
        }

        pub inline fn resize(self: *Self, capacity: usize) !void {
            try self.vector.resize(self.allocator, capacity);
        }

        pub inline fn append(self: *Self, value: ComplexType) !void {
            try self.vector.append(self.allocator, value);
        }

        pub inline fn appendScalar(self: *Self, value: T) !void {
            try self.vector.append(self.allocator, ComplexType.init(value, 0));
        }

        pub inline fn set(self: *Self, index: usize, value: ComplexType) void {
            self.vector.set(index, value);
        }

        pub inline fn setScalar(self: *Self, index: usize, value: T) void {
            self.vector.set(index, ComplexType.init(value, 0));
        }

        pub inline fn get(self: *Self, index: usize) ComplexType {
            return self.vector.get(index);
        }

        pub inline fn normalize(self: *Self) void {
            for (0..self.vector.len) |i| {
                const len = ComplexType.init(@as(T, @floatFromInt(self.vector.len)), 0);
                self.vector.set(i, self.vector.get(i).div(len));
            }
        }

        pub fn deinit(self: *Self) void {
            self.vector.deinit(self.allocator);
        }
    };
}
