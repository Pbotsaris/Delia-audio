const std = @import("std");

pub fn GenericNode(comptime T: type) type {
    if (T != f64 and T != f32) {
        @compileError("Graph Nodes only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            process: *const fn (*anyopaque, []T, []T) void,
        };

        pub fn init(ptr: anytype) Self {
            const PtrType = @TypeOf(ptr);
            const ptr_info = @typeInfo(PtrType);

            if (ptr_info != .Pointer) {
                @compileError("Node init requires a pointer type");
            }

            if (ptr_info.Pointer.size != .One) {
                @compileError("Node must be a single item pointer");
            }

            const StructType = @TypeOf(ptr.*);

            if (!@hasDecl(StructType, "process")) {
                @compileError("Node type must have a process method");
            }

            const gen = struct {
                fn processFn(ctx: *anyopaque, input: []T, output: []T) void {
                    const self = @as(PtrType, @ptrCast(@alignCast(ctx)));
                    self.process(input, output);
                }

                const vtable: VTable = .{
                    .process = processFn,
                };
            };

            return .{
                .ptr = ptr,
                .vtable = &gen.vtable,
            };
        }

        pub inline fn process(self: Self, input: []T, output: []T) void {
            self.vtable.process(self.ptr, input, output);
        }
    };
}

test "Audio Node Interface" {
    const GainNode = struct {
        gain: f64,

        const Self = @This();

        pub fn process(self: *Self, input: []f64, output: []f64) void {
            for (input, 0..) |value, i| {
                output[i] = value * self.gain;
            }
        }
    };

    var gain_node = GainNode{ .gain = 2.0 };
    const node = GenericNode(f64).init(&gain_node);

    var input = [_]f64{ 1.0, 2.0, 3.0 };
    var output = [_]f64{ 0.0, 0.0, 0.0 };

    node.process(&input, &output);

    try std.testing.expectEqual(output[0], 2.0);
    try std.testing.expectEqual(output[1], 4.0);
    try std.testing.expectEqual(output[2], 6.0);
}
