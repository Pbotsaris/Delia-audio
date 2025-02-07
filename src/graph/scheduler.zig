const std = @import("std");
const graph = @import("graph.zig");
const specs = @import("../audio_specs.zig");
const audio_buffer = @import("audio_buffer.zig");

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
        const ProcessContext = GenericNode.ProcessContext;

        audio_graph: graph.Graph(T),
        allocator: std.mem.Allocator,
        execution_queue: ?graph.ExecutionQueue = null,
        buffer: ?audio_buffer.ChannelView(T) = null,

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

        pub fn prepare(self: *Self, ctx: PrepareContext) !void {
            if (self.buffer) |*buffer| {
                buffer.deinit();
            }

            self.buffer = try audio_buffer.ChannelView(T).init(
                self.allocator,
                ctx.n_channels,
                ctx.block_size,
                ctx.access_pattern,
            );

            for (self.audio_graph.nodes.items) |*node| {
                try node.prepare(ctx);
            }

            const queue = try self.audio_graph.topologicalSortAlloc(self.allocator);

            if (self.execution_queue) |*q| {
                q.deinit();
            }

            self.execution_queue = queue;
        }

        pub fn process(self: *Self) !void {
            const queue = self.execution_queue orelse return;
            const buffer = self.buffer orelse return;

            const ctx = ProcessContext{ .buffer = &buffer };

            outer: for (queue.nodes.items(.index), queue.nodes.items(.inputs)) |node_index, inputs| {
                for (inputs.items) |input_index| {
                    const input_node = self.audio_graph.nodes.items[input_index];
                    if (input_node.nodeStatus() != .ready) continue :outer;
                }

                const node = self.audio_graph.nodes.items[node_index];
                try node.process(ctx);

                node.setStatus(.ready);
            }
        }

        pub fn deinit(self: *Self) void {
            self.audio_graph.deinit();

            if (self.buffer) |*buffer| {
                buffer.deinit();
            }

            if (self.execution_queue) |*queue| {
                queue.deinit();
            }
        }
    };
}
