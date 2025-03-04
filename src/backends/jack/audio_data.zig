const std = @import("std");

const c_jack = @cImport({
    @cInclude("jack/jack.h");
});

const log = std.log.scoped(.jack);
const default_audio_type = c_jack.JACK_DEFAULT_AUDIO_TYPE;

pub fn AudioData(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T,
        sample_rate: usize,
        channels: usize,

        pub fn init(buffer: []T, channels: usize, sample_rate: usize) Self {
            return .{
                .buffer = buffer,
                .sample_rate = sample_rate,
                .channels = channels,
            };
        }

        pub fn totalSampleCount(self: Self) usize {
            return self.buffer.len;
        }

        pub fn totalFrameCount(self: Self) usize {
            return @divFloor(self.buffet.len, self.channels);
        }
    };
}
