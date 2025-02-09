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
        execution_queue: ?graph.ExecutionQueue = null,
        buffers: ?audio_buffer.UniformChannelViews(T) = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .audio_graph = graph.Graph(T).init(allocator, .{}),
                .allocator = allocator,
            };
        }

        pub fn build_graph(self: *Self, sample_rate: specs.SampleRate) !void {
            var sine_node = try self.audio_graph.addNode(SineNode.init(540.0, 1.0, sample_rate.toFloat(T)));

            const gain_node = try self.audio_graph.addNode(GainNode{ .gain = 0.01 });
            try sine_node.connect(gain_node);
        }

        pub fn prepare(self: *Self, ctx: PrepareContext) !void {
            for (self.audio_graph.nodes.items) |*node| {
                try node.prepare(ctx);
            }

            const queue = try self.audio_graph.topologicalSortAlloc(self.allocator);

            if (self.execution_queue) |*q| {
                q.deinit();
            }

            self.execution_queue = queue;

            const max_inputs: usize = blk: {
                var max: usize = 0;
                for (queue.nodes.items(.inputs)) |inputs| {
                    if (inputs.len > max) max = @max(max, inputs.len);
                }

                break :blk max;
            };

            if (self.buffers) |*buffers| {
                // we need more buffers, so we deinit the current ones. maybe could optimize this
                if (buffers.opts.n_views < max_inputs) buffers.deinit()
                // we have enough buffers
                else return;
            }

            self.buffers = try audio_buffer.UniformChannelViews(T).init(self.allocator, .{
                .n_views = max_inputs,
                .n_channels = ctx.n_channels,
                .block_size = ctx.block_size,
                .access = ctx.access_pattern,
            });
        }

        //        pub fn process(self: *Self) !void {
        //            // WORK IN PROGRESS NOT READY TODO
        //            const queue = self.execution_queue orelse return;
        //            var buffers = self.buffers orelse return;
        //
        //            var input_views: [buffers.n_views]audio_buffer.UnmanagedChannelView(T) = undefined;
        //
        //            var processed_count: usize = 0;
        //            const total_nodes = queue.nodes.len;
        //
        //            while (processed_count < total_nodes) {
        //                for (queue.nodes.items(.index), queue.nodes.items(.inputs)) |node_index, inputs| {
        //                    var exec_node = self.audio_graph.nodes.items[node_index];
        //
        //                    if (exec_node.nodeStatus() == .processed) continue;
        //
        //                    const all_inputs_ready: bool = blk: {
        //                        for (inputs) |input_index| {
        //                            const input_node = self.audio_graph.nodes.items[input_index];
        //                            if (input_node.nodeStatus() != .proccessed) break :blk false;
        //                        }
        //
        //                        break :blk true;
        //                    };
        //
        //                    if (!all_inputs_ready) continue;
        //
        //                    const node_view = buffers.getView(exec_node.buffer_index);
        //
        //                    for (inputs, 0..) |input_index, i| {
        //                        input_views[i] = self.buffers.getView(input_index);
        //                    }
        //                }
        //            }
        //        }
        //
        pub fn process(self: *Self) !void {
            const queue = self.execution_queue orelse return;
            var buffers = self.buffers orelse return;
            var buffer = buffers.getView(0);

            const ctx = ProcessContext{ .buffer = &buffer };

            outer: for (queue.nodes.items(.index), queue.nodes.items(.inputs)) |node_index, inputs| {
                for (inputs) |input_index| {
                    const input_node = self.audio_graph.nodes.items[input_index];
                    if (input_node.nodeStatus() != .processed) {
                        continue :outer;
                    }
                }

                var node = self.audio_graph.nodes.items[node_index];
                self.audio_graph.updateNodeStatus(node_index, .ready);
                node.process(ctx);

                self.audio_graph.updateNodeStatus(node_index, .processed);
            }
        }

        pub fn blockSize(self: Self) usize {
            if (self.buffers) |buffer| {
                return buffer.block_size;
            }

            return 0;
        }

        pub fn deinit(self: *Self) void {
            self.audio_graph.deinit();

            if (self.buffers) |*buffer| {
                buffer.deinit();
            }

            if (self.execution_queue) |*queue| {
                queue.deinit();
            }
        }
    };
}
