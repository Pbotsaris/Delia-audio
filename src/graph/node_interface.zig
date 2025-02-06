const std = @import("std");

pub const NodeStatus = enum(u8) {
    init,
    ready,
    processed,
};

pub fn GenericNode(comptime T: type) type {
    if (T != f64 and T != f32) {
        @compileError("Graph Nodes only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,
        allocator: std.mem.Allocator,
        status: std.atomic.Value(NodeStatus),

        pub const VTable = struct {
            process: *const fn (*anyopaque, []T, []T) void,
            destroy: *const fn (*anyopaque, std.mem.Allocator) void,
        };

        pub const PrepareContext = struct {
            block_size: usize,
            sample_rate: T,
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
                .status = std.atomic.Value(NodeStatus).init(.init),
            };
        }

        pub inline fn process(self: Self, input: []T, output: []T) void {
            self.vtable.process(self.ptr, input, output);
        }

        pub inline fn destroy(self: *Self) void {
            self.vtable.destroy(self.ptr, self.allocator);
        }

        pub inline fn nodeStatus(self: Self) NodeStatus {
            return self.status.load(.seq_cst);
        }

        pub inline fn setStatus(self: *Self, status: NodeStatus) void {
            self.status.store(status, .seq_cst);
        }
    };
}

const GenNode = GenericNode(f64);

const GainNode = struct {
    gain: f64,

    const Self = @This();

    pub fn process(self: *Self, input: []f64, output: []f64) void {
        for (input, 0..) |value, i| {
            output[i] = value * self.gain;
        }
    }
};

test "Test Node Initialization" {
    const allocator = std.testing.allocator;

    var node = try GenNode.createNode(allocator, GainNode{ .gain = 1.0 });
    defer node.destroy();

    // Ensure initial status is set correctly
    try std.testing.expectEqual(node.nodeStatus(), .init);
}

test "Test Processing Functionality" {
    const allocator = std.testing.allocator;

    var node = try GenNode.createNode(allocator, GainNode{ .gain = 2.0 });
    defer node.destroy();

    var input = [_]f64{ 1.0, 2.0, 3.0 };
    var output = [_]f64{ 0.0, 0.0, 0.0 };

    node.process(&input, &output);

    try std.testing.expectEqual(output[0], 2.0);
    try std.testing.expectEqual(output[1], 4.0);
    try std.testing.expectEqual(output[2], 6.0);
}

test "Test Atomic Node Status Transitions" {
    const allocator = std.testing.allocator;

    var node = try GenNode.createNode(allocator, GainNode{ .gain = 1.5 });
    defer node.destroy();

    try std.testing.expectEqual(node.nodeStatus(), .init);

    node.setStatus(.ready);
    try std.testing.expectEqual(node.nodeStatus(), .ready);

    node.setStatus(.processed);
    try std.testing.expectEqual(node.nodeStatus(), .processed);
}

test "Test Edge Case: Zero-Length Arrays" {
    const allocator = std.testing.allocator;

    var node = try GenNode.createNode(allocator, GainNode{ .gain = 3.0 });
    defer node.destroy();

    const empty_input: []f64 = &[_]f64{};
    const empty_output: []f64 = &[_]f64{};

    node.process(empty_input, empty_output);
    try std.testing.expectEqual(empty_output.len, 0);
}

test "Test Memory Management" {
    const allocator = std.testing.allocator;

    var node = try GenNode.createNode(allocator, GainNode{ .gain = 1.0 });

    defer node.destroy();
}
