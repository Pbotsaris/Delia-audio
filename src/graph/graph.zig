const std = @import("std");
const node_interface = @import("node_interface.zig");
const bitmap = @import("bitmap.zig");
const BoxChars = @import("box_chars.zig");

pub const ExecutionNode = struct {
    index: usize,
    inputs: []usize,
};

pub const ExecutionQueue = struct {
    nodes: std.MultiArrayList(ExecutionNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ExecutionQueue {
        var nodes = std.MultiArrayList(ExecutionNode){};
        try nodes.ensureTotalCapacity(allocator, capacity);

        return .{
            .allocator = allocator,
            .nodes = nodes,
        };
    }

    // we want execution queue to own the node_inputs memory
    pub fn append(self: *ExecutionQueue, index: usize, inputs: []usize) !void {
        const node_inputs = try self.allocator.alloc(usize, inputs.len);
        @memcpy(node_inputs, inputs);

        self.nodes.appendAssumeCapacity(.{
            .index = index,
            .inputs = node_inputs,
        });
    }

    pub fn deinit(self: *ExecutionQueue) void {
        for (self.nodes.items(.inputs)) |inputs| {
            self.allocator.free(inputs);
        }

        self.nodes.deinit(self.allocator);
    }
};

pub fn Graph(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("AudioGraph only supports f32 and f64");
    }

    return struct {
        const Self = @This();
        const GenericNode = node_interface.GenericNode(T);

        nodes: std.ArrayList(GenericNode),
        edges: std.ArrayList(Edges),
        allocator: std.mem.Allocator,
        options: GraphOptions,

        pub const GraphOptions = struct {
            comptime max_static_size: usize = 1024,
        };

        const GraphError = error{
            InvalidNode,
            CycleDetected,
        };

        const Edges = struct {
            from: usize,
            to: usize,
        };

        const NodeHandle = struct {
            index: usize,
            graph: *Self,

            pub fn connect(self: NodeHandle, to: NodeHandle) !void {
                try self.graph.connect(self, to);
            }
        };

        pub fn init(allocator: std.mem.Allocator, opts: GraphOptions) Self {
            return .{
                .nodes = std.ArrayList(GenericNode).init(allocator),
                .edges = std.ArrayList(Edges).init(allocator),
                .allocator = allocator,
                .options = opts,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.nodes.items) |*node| {
                node.destroy();
            }

            self.nodes.deinit();
            self.edges.deinit();
        }

        pub fn connect(self: *Self, from: NodeHandle, to: NodeHandle) !void {
            try self.edges.append(.{ .from = from.index, .to = to.index });
        }

        pub fn addNode(self: *Self, node: anytype) !NodeHandle {
            const generic_node = try GenericNode.createNode(self.allocator, node);
            const index = self.nodes.items.len;
            try self.nodes.append(generic_node);

            return .{ .index = index, .graph = self };
        }

        pub fn debugGraph(self: Self, path: []const u8) !void {
            var file = try std.fs.cwd().createFile(path, .{});
            defer file.close();

            const writer = file.writer();
            try self.exportDot(writer);
        }

        fn topologicalSortAlloc(self: Self, allocator: std.mem.Allocator) !ExecutionQueue {
            const node_count = self.nodes.items.len;

            var results = try ExecutionQueue.init(allocator, node_count);
            errdefer results.deinit();

            if (node_count <= self.options.max_static_size) {
                try self.topologicalStatic(&results);
            }

            return results;
        }

        fn topologicalStatic(self: Self, results: *ExecutionQueue) !void {
            var in_degrees: [self.options.max_static_size]u32 = .{0} ** self.options.max_static_size;
            var visited = bitmap.StaticBitMap(self.options.max_static_size).init();
            var queue: [self.options.max_static_size]usize = undefined;

            var queue_len: usize = 0;
            var queue_start: usize = 0;

            const node_count = self.nodes.items.len;

            var inputs: [self.options.max_static_size]usize = undefined;
            var inputs_count: usize = 0;

            for (self.edges.items) |edge| {
                if (edge.to >= node_count) return GraphError.InvalidNode;
                in_degrees[edge.to] += 1;
            }

            for (in_degrees[0..node_count], 0..) |deg, i| {
                if (deg != 0) continue;

                queue[queue_len] = i;
                queue_len += 1;
            }

            while (queue_start < queue_len) {
                const node_index = queue[queue_start];
                queue_start += 1;

                if (visited.isSet(node_index)) continue;
                try visited.set(node_index);

                inputs_count = 0;

                for (self.edges.items) |edge| {
                    if (edge.to == node_index) {
                        inputs[inputs_count] = edge.from;
                        inputs_count += 1;
                    }
                }

                try results.append(node_index, inputs[0..inputs_count]);

                for (self.edges.items) |edge| {
                    if (edge.from == node_index) {
                        in_degrees[edge.to] -= 1;
                        queue[queue_len] = edge.to;
                        queue_len += 1;
                    }
                }
            }

            if (results.nodes.len != node_count) {
                return GraphError.CycleDetected;
            }
        }

        fn exportDot(self: Self, writer: anytype) !void {
            try writer.writeAll("digraph AudioGraph {\n");
            try writer.writeAll("    rankdir=LR;\n");
            try writer.writeAll("    node [shape=box];\n\n");

            // Write nodes
            for (self.nodes.items, 0..) |node, i| {
                const node_type = @typeName(@TypeOf(node));
                try writer.print("    node{d} [label=\"{s}\"];\n", .{ i, node_type });
            }

            try writer.writeAll("\n");

            // Write edges
            for (self.edges.items) |edge| {
                try writer.print("    node{d} -> node{d};\n", .{ edge.from, edge.to });
            }

            try writer.writeAll("}\n");
        }
    };
}

// just an example to use in the graph
const GainNode = struct {
    // must be same float as graph
    gain: f64,

    const Self = @This();

    pub fn process(self: *Self, input: []f64, output: []f64) void {
        for (input, 0..) |value, i| {
            output[i] = value * self.gain;
        }
    }
};

test "toplogical test" {
    const allocator = std.testing.allocator;
    var graph = Graph(f64).init(allocator, .{});

    const node_a = try graph.addNode(GainNode{ .gain = 0.2 });
    const node_b = try graph.addNode(GainNode{ .gain = 0.5 });
    const node_c = try graph.addNode(GainNode{ .gain = 0.89 });
    const node_d = try graph.addNode(GainNode{ .gain = 0.90 });
    const node_e = try graph.addNode(GainNode{ .gain = 0.92 });

    try node_a.connect(node_b);
    try node_b.connect(node_c);

    try node_a.connect(node_d);
    try node_d.connect(node_e);

    var res = try graph.topologicalSortAlloc(allocator);

    try graph.debugGraph("graph.dot");

    res.deinit();
    graph.deinit();
}

test "Graph: Create nodes" {
    const allocator = std.testing.allocator;
    var graph = Graph(f64).init(allocator, .{});

    var node_a = try graph.addNode(GainNode{ .gain = 0.2 });
    const node_b = try graph.addNode(GainNode{ .gain = 0.5 });
    const node_c = try graph.addNode(GainNode{ .gain = 0.89 });

    try node_a.connect(node_b);
    try node_b.connect(node_c);

    graph.deinit();
}
