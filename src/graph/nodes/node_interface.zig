const std = @import("std");
const audio_buffer = @import("../audio_buffer.zig");
const specs = @import("../../audio_specs.zig");

pub const NodeStatus = enum(u8) {
    init,
    ready,
    processed,
};

pub const NodeError = error{
    allocation_error,
};

pub fn GenericNode(comptime T: type) type {
    if (T != f64 and T != f32) {
        @compileError("Graph Nodes only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        pub const PrepareContext = struct {
            block_size: specs.BlockSize,
            n_channels: usize,
            sample_rate: T,
            access_pattern: audio_buffer.AccessPattern,
        };

        // ProcessContext does not own the buffer
        pub const ProcessContext = struct {
            buffer: *audio_buffer.ChannelView(T),
        };

        pub const VTable = struct {
            prepare: *const fn (*anyopaque, PrepareContext) NodeError!void,
            process: *const fn (*anyopaque, ProcessContext) void,
            destroy: *const fn (*anyopaque, std.mem.Allocator) void,
        };

        ptr: *anyopaque,
        vtable: *const VTable,
        allocator: std.mem.Allocator,
        status: std.atomic.Value(NodeStatus),

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
                fn prepareFn(ctx: *anyopaque, prepare_ctx: PrepareContext) NodeError!void {
                    const self = @as(PtrType, @ptrCast(@alignCast(ctx)));
                    try self.prepare(prepare_ctx);
                }

                fn processFn(ctx: *anyopaque, process_ctx: ProcessContext) void {
                    const self = @as(PtrType, @ptrCast(@alignCast(ctx)));
                    self.process(process_ctx);
                }

                fn destroyFn(ctx: *anyopaque, alloc: std.mem.Allocator) void {
                    const self = @as(PtrType, @ptrCast(@alignCast(ctx)));
                    alloc.destroy(self);
                }

                const vtable: VTable = .{
                    .process = processFn,
                    .destroy = destroyFn,
                    .prepare = prepareFn,
                };
            };

            return .{
                .ptr = ptr,
                .vtable = &gen.vtable,
                .allocator = allocator,
                .status = std.atomic.Value(NodeStatus).init(.init),
            };
        }

        pub inline fn prepare(self: *Self, ctx: PrepareContext) NodeError!void {
            try self.vtable.prepare(self.ptr, ctx);

            self.setStatus(.ready);
        }

        pub inline fn process(self: *Self, ctx: ProcessContext) void {
            self.vtable.process(self.ptr, ctx);

            self.setStatus(.processed);
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
    const PrepareContext = GenNode.PrepareContext;
    const ProcessContext = GenNode.ProcessContext;

    pub fn process(self: *Self, ctx: ProcessContext) void {
        for (0..ctx.buffer.n_frames) |frame_index| {
            const sample = ctx.buffer.readSample(0, frame_index);
            ctx.buffer.writeSample(0, frame_index, sample * self.gain);
        }
    }

    pub fn prepare(_: *Self, _: PrepareContext) NodeError!void {}
};

test "Test Node Initialization" {
    const allocator = std.testing.allocator;

    var node = try GenNode.createNode(allocator, GainNode{ .gain = 1.0 });
    defer node.destroy();

    try std.testing.expectEqual(node.nodeStatus(), .init);
}

test "Test Processing Functionality" {
    const allocator = std.testing.allocator;

    var node = try GenNode.createNode(allocator, GainNode{ .gain = 2.0 });
    defer node.destroy();
    const input = [_]f64{ 1.0, 2.0, 3.0 };

    var buffer = try audio_buffer.ChannelView(f64).init(allocator, 1, .blk_64, .interleaved);
    defer buffer.deinit();

    buffer.writeSample(0, 0, input[0]);
    buffer.writeSample(0, 1, input[1]);
    buffer.writeSample(0, 2, input[2]);

    const ctx = GenNode.ProcessContext{
        .buffer = &buffer,
    };

    node.process(ctx);

    try std.testing.expectEqual(2.0, buffer.readSample(0, 0));
    try std.testing.expectEqual(4.0, buffer.readSample(0, 1));
    try std.testing.expectEqual(6.0, buffer.readSample(0, 2));
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
