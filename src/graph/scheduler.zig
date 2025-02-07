const std = @import("std");
const graph = @import("graph.zig");
const specs = @import("../audio_specs.zig");

pub fn Scheduler(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("Scheduler only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        const GenericNode = graph.nodes.interface.GenericNode(T);
        const GainNode = graph.nodes.utils.GainNode(T);
        const SineNode = graph.nodes.wave.SineNode(T);

        const PrepareContext = GenericNode.PrepareContext;
        const ProcessContext = GenericNode.PrepareContext;

        audio_graph: graph.Graph(T),
        allocator: std.mem.Allocator,
        execution_queue: ?graph.ExecutionQueue = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .audio_graph = graph.Graph(T).init(allocator, .{}),
                .allocator = allocator,
            };
        }

        pub fn build_graph(self: *Self, sample_rate: specs.SampleRate) !void {
            var sine_node = try self.audio_graph.addNode(SineNode.init(440.0, 1.0, sample_rate.toFloat(T)));

            const gain_node = try self.audio_graph.addNode(GainNode{ .gain = 0.5 });
            try sine_node.connect(gain_node);
        }

        pub fn prepare(self: *Self, sample_rate: specs.SampleRate, block_size: specs.BlockSize) !void {
            for (self.audio_graph.nodes.items) |*node| {
                const ctx = PrepareContext{ .sample_rate = sample_rate.toFloat(T), .block_size = block_size };
                try node.prepare(ctx);
            }

            const queue = try self.audio_graph.topologicalSortAlloc(self.allocator);

            if (self.execution_queue) |*q| {
                q.deinit();
            }

            self.execution_queue = queue;
        }

        pub fn deinit(self: *Self) void {
            self.audio_graph.deinit();

            if (self.execution_queue) |*queue| {
                queue.deinit();
            }
        }
    };
}
