const std = @import("std");
const alsa = @import("alsa/alsa.zig");
const dsp = @import("dsp/dsp.zig");
const alsa_examples = @import("alsa/examples/examples.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

pub fn main() !void {
    alsa_examples.playbackSineWave();
    //alsa_examples.printingHardwareInfo();
}

test {
    std.testing.refAllDeclsRecursive(alsa);
    std.testing.refAllDeclsRecursive(dsp);
}
