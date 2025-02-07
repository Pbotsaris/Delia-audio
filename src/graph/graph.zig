const std = @import("std");
const bitmap = @import("bitmap.zig");
pub const nodes = @import("nodes/nodes.zig");
pub const scheduler = @import("scheduler.zig");

pub const ExecutionNode = struct {
    index: usize,
    inputs: []usize,
};

pub const ExecutionQueue = struct {
    nodes: std.MultiArrayList(ExecutionNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ExecutionQueue {
        var nds = std.MultiArrayList(ExecutionNode){};
        try nds.ensureTotalCapacity(allocator, capacity);

        return .{
            .allocator = allocator,
            .nodes = nds,
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
        const GenericNode = nodes.interface.GenericNode(T);

        nodes: std.ArrayList(GenericNode),
        edges: std.ArrayList(Edges),
        allocator: std.mem.Allocator,
        options: GraphOptions,

        pub const GraphOptions = struct {
            comptime max_static_size: usize = 1024,
        };

        const GraphError = error{
            invalid_node,
            cycle_detected,
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

        pub fn topologicalSortAlloc(self: Self, allocator: std.mem.Allocator) !ExecutionQueue {
            const node_count = self.nodes.items.len;

            var results = try ExecutionQueue.init(allocator, node_count);
            errdefer results.deinit();

            if (node_count <= self.options.max_static_size) {
                try self.topologicalStatic(&results);
            }

            // TODO, dynamic version for very long graphs

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
                if (edge.to >= node_count) return GraphError.invalid_node;
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
                return GraphError.cycle_detected;
            }
        }

        // for debugging purposes
        fn exportDot(self: Self, writer: anytype) !void {
            try writer.writeAll("digraph AudioGraph {\n");
            try writer.writeAll("    rankdir=LR;\n");
            try writer.writeAll("    node [shape=box];\n\n");

            for (self.nodes.items, 0..) |node, i| {
                const node_type = @typeName(@TypeOf(node));
                try writer.print("    node{d} [label=\"{s}\"];\n", .{ i, node_type });
            }

            try writer.writeAll("\n");

            for (self.edges.items) |edge| {
                try writer.print("    node{d} -> node{d};\n", .{ edge.from, edge.to });
            }

            try writer.writeAll("}\n");
        }
    };
}

// just an example to use in the graph
const GainNode = struct {
    gain: f64,

    const Self = @This();
    const PrepareContext = nodes.interface.GenericNode(f64).PrepareContext;
    const ProcessContext = nodes.interface.GenericNode(f64).ProcessContext;
    const Error = nodes.interface.NodeError;

    // for testing, no need to implement
    pub fn process(_: *Self, _: ProcessContext) void {}
    pub fn prepare(_: *Self, _: PrepareContext) Error!void {}
};

test "Graph: connect nodes validation" {
    const allocator = std.testing.allocator;
    var graph = Graph(f64).init(allocator, .{});
    defer graph.deinit();

    const node_a = try graph.addNode(GainNode{ .gain = 0.2 });
    const node_b = try graph.addNode(GainNode{ .gain = 0.5 });
    try node_a.connect(node_b);

    try std.testing.expectEqual(graph.edges.items.len, 1);
    try std.testing.expectEqual(graph.edges.items[0].from, node_a.index);
    try std.testing.expectEqual(graph.edges.items[0].to, node_b.index);
}

test "Graph: topological sort validation" {
    const allocator = std.testing.allocator;
    var graph = Graph(f64).init(allocator, .{});
    defer graph.deinit();

    const node_a = try graph.addNode(GainNode{ .gain = 0.2 });
    const node_b = try graph.addNode(GainNode{ .gain = 0.5 });
    const node_c = try graph.addNode(GainNode{ .gain = 0.3 });

    try node_a.connect(node_b);
    try node_b.connect(node_c);

    var result = try graph.topologicalSortAlloc(allocator);
    defer result.deinit();

    // Verify correct order
    try std.testing.expectEqual(result.nodes.items(.index)[0], node_a.index);
    try std.testing.expectEqual(result.nodes.items(.index)[1], node_b.index);
    try std.testing.expectEqual(result.nodes.items(.index)[2], node_c.index);
}

test "Graph: detect cycles" {
    const allocator = std.testing.allocator;
    var graph = Graph(f64).init(allocator, .{});
    defer graph.deinit();

    const node_a = try graph.addNode(GainNode{ .gain = 0.2 });
    const node_b = try graph.addNode(GainNode{ .gain = 0.5 });

    try node_a.connect(node_b);
    try node_b.connect(node_a);

    try std.testing.expectError(Graph(f64).GraphError.cycle_detected, graph.topologicalSortAlloc(allocator));
}

test "Graph: complex DAG" {
    const allocator = std.testing.allocator;
    var graph = Graph(f64).init(allocator, .{});
    defer graph.deinit();

    const nds = [_]Graph(f64).NodeHandle{
        try graph.addNode(GainNode{ .gain = 0.1 }),
        try graph.addNode(GainNode{ .gain = 0.2 }),
        try graph.addNode(GainNode{ .gain = 0.3 }),
        try graph.addNode(GainNode{ .gain = 0.4 }),
    };

    try nds[0].connect(nds[1]);
    try nds[0].connect(nds[2]);
    try nds[1].connect(nds[3]);
    try nds[2].connect(nds[3]);

    var result = try graph.topologicalSortAlloc(allocator);
    defer result.deinit();

    // Verify node 0 comes first and node 3 comes last
    try std.testing.expectEqual(result.nodes.items(.index)[0], nds[0].index);
    try std.testing.expectEqual(result.nodes.items(.index)[3], nds[3].index);
}
