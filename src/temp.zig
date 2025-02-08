pub const ExecutionNode = struct {
    index: usize,
    inputs: []usize,
    // Add buffer management
    output_buffer: ?audio_buffer.ChannelView(T) = null,
    status: std.atomic.Value(NodeStatus) = std.atomic.Value(NodeStatus).init(.initialized),
};

pub fn process(self: *Self) !void {
    const queue = self.execution_queue orelse return;
    var processed_count: usize = 0;
    const total_nodes = queue.nodes.len;

    // Reset all nodes
    for (queue.nodes.items(.index)) |node_index| {
        self.audio_graph.updateNodeStatus(node_index, .ready);
    }

    // Process until all nodes are done
    while (processed_count < total_nodes) {
        for (queue.nodes.items(.index), queue.nodes.items(.inputs)) |node_index, inputs| {
            var node = &self.audio_graph.nodes.items[node_index];
            
            // Skip if already processed
            if (node.nodeStatus() == .processed) {
                continue;
            }

            // Check if all inputs are processed
            var all_inputs_ready = true;
            for (inputs) |input_index| {
                const input_node = self.audio_graph.nodes.items[input_index];
                if (input_node.nodeStatus() != .processed) {
                    all_inputs_ready = false;
                    break;
                }
            }

            if (all_inputs_ready) {
                // Process node with its inputs
                var input_buffers = try self.allocator.alloc(audio_buffer.ChannelView(T), inputs.len);
                defer self.allocator.free(input_buffers);
                
                // Collect input buffers
                for (inputs, 0..) |input_index, i| {
                    const input_node = self.audio_graph.nodes.items[input_index];
                    input_buffers[i] = input_node.getOutputBuffer();
                }

                // Process with multiple inputs
                try node.process(.{
                    .inputs = input_buffers,
                    .output = self.buffer,
                    .block_size = self.block_size,
                });

                self.audio_graph.updateNodeStatus(node_index, .processed);
                processed_count += 1;
            }
        }
    }
}
