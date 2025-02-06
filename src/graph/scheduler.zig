const std = @import("std");
const graph = @import("graph.zig");
const linux = std.os.linux;

pub fn Scheduler(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("Scheduler only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        audio_graph: graph.Graph(T),
        audio_thread: std.Thread,

        pub fn init() Self {}
    };
}
