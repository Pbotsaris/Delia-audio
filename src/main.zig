const std = @import("std");
const alsa = @import("alsa/alsa.zig");
const dsp = @import("dsp/dsp.zig");
const graph = @import("graph/graph.zig");

// const graph @import("graph.zig");
const alsa_examples = @import("alsa/examples/examples.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

fn spinMe() void {
    var count: usize = 0;
    while (true) {
        if (count == 10) break;

        log.info("Spinning", .{});
        count += 10;
    }
}

pub fn main() !void {
    // alsa_examples.playbackSineWave();
    //alsa_examples.printingHardwareInfo();

    var audio_thread = try std.Thread.spawn(.{}, spinMe, .{});
    audio_thread.join();
}

test {
    std.testing.refAllDeclsRecursive(alsa);
    std.testing.refAllDeclsRecursive(dsp);
    //  std.testing.refAllDeclsRecursive()
}
