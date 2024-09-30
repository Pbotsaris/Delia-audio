const std = @import("std");
const alsa = @import("alsa/alsa.zig");
const dsp = @import("dsp/dsp.zig");
const alsa_examples = @import("alsa/examples/examples.zig");
const dsp_example = @import("dsp/examples.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};
const log = std.log.scoped(.main);

pub fn main() !void {
    try dsp_example.fftSineWave();
}

test {
    std.testing.refAllDeclsRecursive(alsa);
    std.testing.refAllDeclsRecursive(dsp);
}
