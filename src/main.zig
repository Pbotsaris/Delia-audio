const std = @import("std");
const alsa = @import("alsa/alsa.zig");
const dsp = @import("dsp/dsp.zig");
const graph = @import("graph/graph.zig");
const audio_specs = @import("audio_specs.zig");

// const graph @import("graph.zig");
const alsa_examples = @import("alsa/examples/examples.zig");
const ex = @import("examples.zig");

const audio_backend = @import("audio_backend");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

fn examplePlaybackAndGraph() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var e = try ex.Example.init(allocator, audio_specs.SampleRate.sr_44100);

    try e.prepare();
    try e.run();
    try e.deinit();
}

pub fn main() !void {
    // examplePlaybackAndGraph() catch |err| {
    //     log.err("{s}", .{err});
    //     return err;
    // };

    //   alsa_examples.usingHardwareToInitDevice();
    std.debug.print("audio_backend: {any}\n", .{audio_backend.audio_backend});
}

test {
    std.testing.refAllDeclsRecursive(alsa);
    std.testing.refAllDeclsRecursive(dsp);
    std.testing.refAllDeclsRecursive(graph);
}
