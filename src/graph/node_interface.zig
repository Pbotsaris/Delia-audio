const std = @import("std");

pub fn GenericNode(comptime T: type) type {
    if (T != f64 and T != f32) {
        @compileError("Graph Nodes only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,
        allocator: std.mem.Allocator,

        pub const VTable = struct {
            process: *const fn (*anyopaque, []T, []T) void,
            destroy: *const fn (*anyopaque, std.mem.Allocator) void,
        };

        pub fn createNode(allocator: std.mem.Allocator, node: anytype) !Self {
            const ptr = try allocator.create(@TypeOf(node));
            ptr.* = node;

            return init(allocator, ptr);
        }

        pub fn init(allocator: std.mem.Allocator, ptr: anytype) Self {
            const PtrType = @TypeOf(ptr);
            const ptr_info = @typeInfo(PtrType);

            if (ptr_info != .Pointer) {
                @compileError("Node init requires a pointer type.");
            }

            if (ptr_info.Pointer.size != .One) {
                @compileError("When initializing a GenericNode pointer must be to a single item/struct");
            }

            const StructType = @TypeOf(ptr.*);

            if (!@hasDecl(StructType, "process")) {
                @compileError("Graph nodes type must implement a 'process(input, output)' method");
            }

            const gen = struct {
                fn processFn(ctx: *anyopaque, input: []T, output: []T) void {
                    const self = @as(PtrType, @ptrCast(@alignCast(ctx)));
                    self.process(input, output);
                }

                fn destroyFn(ctx: *anyopaque, alloc: std.mem.Allocator) void {
                    const self = @as(PtrType, @ptrCast(@alignCast(ctx)));
                    alloc.destroy(self);
                }

                const vtable: VTable = .{
                    .process = processFn,
                    .destroy = destroyFn,
                };
            };

            return .{
                .ptr = ptr,
                .vtable = &gen.vtable,
                .allocator = allocator,
            };
        }

        pub inline fn process(self: Self, input: []T, output: []T) void {
            self.vtable.process(self.ptr, input, output);
        }

        pub inline fn destroy(self: *Self) void {
            self.vtable.destroy(self.ptr, self.allocator);
        }
    };
}

test "Audio Node Interface" {
    const allocator = std.testing.allocator;

    const GainNode = struct {
        gain: f64,

        const Self = @This();

        pub fn process(self: *Self, input: []f64, output: []f64) void {
            for (input, 0..) |value, i| {
                output[i] = value * self.gain;
            }
        }
    };

    const GenNode = GenericNode(f64);
    var node = try GenNode.createNode(allocator, GainNode{ .gain = 2.0 });

    var input = [_]f64{ 1.0, 2.0, 3.0 };
    var output = [_]f64{ 0.0, 0.0, 0.0 };

    node.process(&input, &output);

    try std.testing.expectEqual(output[0], 2.0);
    try std.testing.expectEqual(output[1], 4.0);
    try std.testing.expectEqual(output[2], 6.0);

    node.destroy();
}
