//! ALSA backend on docs/backend-contract.md. M4a: playback, MMAP interleaved, S16_LE.
pub const loop = @import("loop.zig");
pub const convert = @import("convert.zig");
pub const pcm = @import("pcm.zig");
pub const device = @import("device.zig");
pub const examples = @import("examples.zig");

test {
    @import("std").testing.refAllDecls(loop);
    @import("std").testing.refAllDecls(convert);
    @import("std").testing.refAllDecls(pcm);
    @import("std").testing.refAllDecls(device);
    @import("std").testing.refAllDecls(examples);
}
