const std = @import("std");
const dsp = @import("dsp/dsp.zig");
const graph = @import("graph/graph.zig");
const audio_specs = @import("audio_specs.zig");
const ex = @import("examples.zig");

const backends = @import("backends/backends.zig");

const audio_backend = @import("audio_backend");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

const Client = backends.jack.client.JackClient;
const Hardware = backends.jack.Hardware;

//fn examplePlaybackAndGraph() !void {
//    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//    const allocator = gpa.allocator();
//    var e = try ex.Example.init(allocator, audio_specs.SampleRate.sr_44100);
//
//    try e.prepare();
//    try e.run();
//    try e.deinit();
//}
pub fn main() !void {

    //        log.err("{any}", .{err});
    //    examplePlaybackAndGraph() catch |err| {

    //        return err;
    //    };
    // backends.alsa.examples.printingHardwareInfo();
    //backends.alsa.examples.findAndPrintCardPortInfo("USB");
    //backends.alsa.examples.selectAudioPortCounterpart();
    // backends.alsa.examples.fullDuplexCallback();
    backends.alsa.examples.fullDuplexCallback();
    // backends.alsa.examples.halfDuplexCapture();
    //backends.alsa.examples.playbackSineWave();

    // backends.alsa.examples.usingHardwareToInitDevice();
    // std.debug.print("audio_backend: {any}\n", .{audio_backend.audio_backend});

    //    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //    const allocator = gpa.allocator();
    //
    //    const client = try Client.init(.{ .client_name = "device" });
    //
    //    const hw = try Hardware.init(allocator, client);
    //    defer hw.deinit();
    //
    //    for (hw.playbacks) |port| {
    //        std.debug.print("{any}", .{port});
    //    }
    //
    //    for (hw.captures) |port| {
    //        std.debug.print("{any}", .{port});
    //    }
}

test {
    std.testing.refAllDeclsRecursive(backends);
    std.testing.refAllDeclsRecursive(dsp);
    std.testing.refAllDeclsRecursive(graph);
}
