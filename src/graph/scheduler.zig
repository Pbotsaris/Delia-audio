const std = @import("std");
const graph = @import("graph.zig");
const specs = @import("../audio_specs.zig");
const audio_buffer = @import("audio_buffer.zig");

const log = std.log.scoped(.graph);

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
        topology_queue: ?graph.TopologyQueue = null,
        buffers: ?audio_buffer.UniformChannelViews(T) = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .audio_graph = graph.Graph(T).init(allocator, .{}),
                .allocator = allocator,
            };
        }

        pub fn build_graph(self: *Self, sample_rate: specs.SampleRate) !void {
            var sine_node = try self.audio_graph.addNode(SineNode.init(540.0, 1.0, sample_rate.toFloat(T)));

            const gain_node = try self.audio_graph.addNode(GainNode{ .gain = 0.5 });
            try sine_node.connect(gain_node);
        }

        pub fn prepare(self: *Self, ctx: PrepareContext) !void {
            for (self.audio_graph.nodes.items) |*node| {
                try node.prepare(ctx);
            }

            var queue = try self.audio_graph.topologicalSortAlloc(self.allocator);

            if (self.topology_queue) |*q| {
                q.deinit();
            }

            self.topology_queue = queue;

            // assigns buffer index to each node and returns the number of buffers required
            const n_views = try queue.analyzeBufferRequirementsAlloc();

            if (self.buffers) |*buffers| {
                // we already have enough buffers
                if (buffers.opts.n_views >= n_views) buffers.deinit()
                // we have enough buffers
                else return;
            }

            self.buffers = try audio_buffer.UniformChannelViews(T).init(self.allocator, .{
                .n_views = n_views,
                .n_channels = ctx.n_channels,
                .block_size = ctx.block_size,
                .access = ctx.access_pattern,
            });
        }

        pub fn process(self: *Self) !void {
            // WORK IN PROGRESS NOT READY TODO
            const queue = self.topology_queue orelse return;
            var buffers = self.buffers orelse return;

            var processed_count: usize = 0;
            const total_nodes = queue.nodes.len;

            while (processed_count < total_nodes) {
                const queue_items = queue.nodes.slice();

                for (0..queue_items.len) |idx| {
                    // queue_item has information about the index of nodes in the graph
                    // the inputs/dependencies of the node
                    // which buffer to use when processing the node
                    const queue_item = queue_items.get(idx);
                    var graph_node = self.audio_graph.nodes.items[queue_item.graph_index];

                    if (graph_node.nodeStatus() == .processed) continue;

                    const all_inputs_ready: bool = blk: {
                        for (queue_item.inputs) |input_index| {
                            const input_node = self.audio_graph.nodes.items[input_index];
                            if (input_node.nodeStatus() != .processed) break :blk false;
                        }

                        break :blk true;
                    };

                    if (!all_inputs_ready) continue;

                    for (queue_item.inputs) |input_index| {
                        const parent_queue_item = queue.getFromGraphIndex(input_index);
                        const parent_buffer_index = parent_queue_item.buffer_index;

                        if (parent_buffer_index != queue_item.buffer_index) {
                            // todo check for nulls here
                            var parent_view = buffers.getView(parent_buffer_index.?);
                            var child_view = buffers.getView(queue_item.buffer_index.?);

                            try child_view.copyFrom(parent_view);
                            parent_view.zero();
                        }
                    }

                    const node_buffer_view = buffers.getView(queue_item.buffer_index.?);

                    // when to copy and when to share?
                    const ctx = ProcessContext{ .buffer = node_buffer_view };
                    graph_node.process(ctx);

                    self.audio_graph.updateNodeStatus(queue_item.graph_index, .processed);
                    processed_count += 1;
                }
            }
        }

        pub fn getOutputBuffer(self: Self) ?audio_buffer.UnmanagedChannelView(T) {
            const queue = self.topology_queue orelse return null;

            const queue_last = queue.getLast();
            const buffer_index = queue_last.buffer_index orelse return null;
            var buffers = self.buffers orelse return null;

            for (self.audio_graph.nodes.items) |*node| {
                node.setStatus(.ready);
            }

            return buffers.getView(buffer_index);
        }

        pub fn blockSize(self: *Self) usize {
            return @intFromEnum(self.buffers.?.opts.block_size);
        }

        // pub fn process(self: *Self) !void {
        //     const queue = self.topology_queue orelse return;
        //     var buffers = self.buffers orelse return;
        //     var buffer = buffers.getView(0);

        //     const ctx = ProcessContext{ .buffer = &buffer };

        //     outer: for (queue.nodes.items(.graph_index), queue.nodes.items(.inputs)) |node_index, inputs| {
        //         for (inputs) |input_index| {
        //             const input_node = self.audio_graph.nodes.items[input_index];
        //             if (input_node.nodeStatus() != .processed) {
        //                 continue :outer;
        //             }
        //         }

        //         var node = self.audio_graph.nodes.items[node_index];
        //         self.audio_graph.updateNodeStatus(node_index, .ready);
        //         node.process(ctx);

        //         self.audio_graph.updateNodeStatus(node_index, .processed);
        //     }
        // }

        pub fn deinit(self: *Self) void {
            self.audio_graph.deinit();

            if (self.buffers) |*buffer| {
                buffer.deinit();
            }

            if (self.topology_queue) |*queue| {
                queue.deinit();
            }
        }
    };
}
