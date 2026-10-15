pub const Oscillator = @import("oscillator.zig").Oscillator;
pub const Gain = @import("gain.zig").Gain;

test {
    @import("std").testing.refAllDecls(@import("oscillator.zig"));
    @import("std").testing.refAllDecls(@import("gain.zig"));
}
