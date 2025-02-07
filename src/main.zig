const std = @import("std");
const alsa = @import("alsa/alsa.zig");
const dsp = @import("dsp/dsp.zig");
const graph = @import("graph/graph.zig");
const audio_specs = @import("audio_specs.zig");

// const graph @import("graph.zig");
const alsa_examples = @import("alsa/examples/examples.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

pub fn main() !void {
    // alsa_examples.playbackSineWave();
    //alsa_examples.printingHardwareInfo();

    //   var audio_thread = try std.Thread.spawn(.{}, spinMe, .{});
    //  audio_thread.join();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) log.err("Memory leak detected", .{});

    const allocator = gpa.allocator();

    var scheduler = graph.scheduler.Scheduler(f32).init(allocator);
    defer scheduler.deinit();

    const sr: audio_specs.SampleRate = .sr_44100;

    scheduler.build_graph(sr) catch |err| {
        log.err("Failed to build graph: {any}", .{err});
        return;
    };

    scheduler.prepare(.{
        .n_channels = 2,
        .block_size = .blk_256,
        .sample_rate = sr.toFloat(f32),
        .access_pattern = .interleaved,
    }) catch |err| {
        log.err("Failed to prepare scheduler: {any}", .{err});
        return;
    };
}

test {
    std.testing.refAllDeclsRecursive(alsa);
    std.testing.refAllDeclsRecursive(dsp);
    std.testing.refAllDeclsRecursive(graph);
}
