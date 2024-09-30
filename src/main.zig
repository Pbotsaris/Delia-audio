const std = @import("std");
const alsa = @import("alsa/alsa.zig");
const dsp = @import("dsp/dsp.zig");
const examples = @import("alsa/examples/examples.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};
const log = std.log.scoped(.main);

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const transform = dsp.transforms.FourierDynamic(f32);

    for (0..50) |_| {
        const sineGeneration = dsp.waves.Sine(f32).init(400.0, 1.0, 44100.0);

        var buffer: [4099]f32 = undefined;
        const sine = sineGeneration.generate(&buffer);

        var out = transform.fft(allocator, sine) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            return;
        };

        out.deinit(allocator);
    }
}

test {
    std.testing.refAllDeclsRecursive(alsa);
    std.testing.refAllDeclsRecursive(dsp);
}
