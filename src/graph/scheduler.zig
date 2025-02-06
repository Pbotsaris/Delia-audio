const std = @import("std");

const graph = @import("graph.zig");

pub fn Scheduler(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("Scheduler only supports f32 and f64");
    }

    return struct {
        audio_graph: graph.Graph(T),
    };
}
