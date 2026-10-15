//! Root of the `core/common` module: the audio_specs enums (BufferSize, BlockSize, SampleRate).
pub const audio_specs = @import("audio_specs.zig");

test {
    @import("std").testing.refAllDecls(audio_specs);
}
