const std = @import("std");
const buffer = @import("core/buffer");

const ConstAudioBlock = buffer.ConstAudioBlock;
const AudioBlock = buffer.AudioBlock;

pub const SampleFormat = enum {
    s16_le,
    f32_le,
};

pub const ConvertError = error{size_mismatch};

pub fn SampleConverter(comptime fmt: SampleFormat) type {
    return struct {
        pub const format = fmt;
        pub const bytes_per_sample: usize = switch (fmt) {
            .s16_le => 2,
            .f32_le => 4,
        };

        /// Device bytes for `frame_count` frames and `channel_count` channels for either layout
        pub fn byteLength(channel_count: usize, frame_count: usize) usize {

            return frame_count * channel_count * bytes_per_sample;
        }

        /// Encodes a single sample into the destination buffer. The destination buffer must be at least `bytes_per_sample` bytes long.
        pub inline fn encode(dst: *[bytes_per_sample]u8, sample: f32) void {
            switch (fmt) {
                .s16_le => {
                    const clamped = std.math.clamp(sample, -1.0, 1.0);
                    const scaled: i16 = @intFromFloat(@round(clamped * std.math.maxInt(i16)));
                    // little endian write
                    std.mem.writeInt(i16, dst, scaled, .little);
                },
                .f32_le => std.mem.writeInt(u32, dst, @bitCast(sample), .little),
            }
        }

        /// Decodes a single sample from the source buffer. The source buffer must be at least `bytes_per_sample` bytes long.
        pub inline fn decode(src: *const [bytes_per_sample]u8) f32 {
            return switch (fmt) {
                .s16_le => @as(f32, @floatFromInt(std.mem.readInt(i16, src, .little))) / std.math.maxInt(i16),
                .f32_le => @as(f32, @bitCast(std.mem.readInt(u32, src, .little))),
            };
        }

        pub fn writeInterleaved(dst: []u8, src: ConstAudioBlock(f32)) ConvertError!void {
            if (dst.len != byteLength(src.channel_count, src.frame_count)) return ConvertError.size_mismatch;

            const bytes_per_frame = src.channel_count * bytes_per_sample;

            for (0..src.channel_count) |ch| {
                var at = ch * bytes_per_sample;

                for (src.getSamples(ch)) |sample| {
                    encode(dst[at..][0..bytes_per_sample], sample);
                    at += bytes_per_frame;
                }
            }
        }

        pub fn readInterleaved(dst: AudioBlock(f32), src: []const u8) ConvertError!void {
            if (src.len != byteLength(dst.channel_count, dst.frame_count)) return ConvertError.size_mismatch;

            const bytes_per_frame = dst.channel_count * bytes_per_sample;

            for (0..dst.channel_count) |ch| {
                var at = ch * bytes_per_sample;

                for (dst.getSamples(ch)) |*sample| {
                    sample.* = decode(src[at..][0..bytes_per_sample]);
                    at += bytes_per_frame;
                }
            }
        }
    };
}

const testing = std.testing;
const S16 = SampleConverter(.s16_le);

test "s16 encode clamps instead of panicking: 1.5 and -1.5 map to maxInt and -maxInt" {
    var samples = [_]f32{ 1.5, -1.5, 0.0, 1.0 };
    const block = ConstAudioBlock(f32){ .samples = &samples, .channel_count = 1, .frame_count = 4, .channel_stride = 4 };

    var bytes: [8]u8 = undefined;
    try S16.writeInterleaved(&bytes, block);

    try testing.expectEqual(std.math.maxInt(i16), std.mem.readInt(i16, bytes[0..2], .little));
    try testing.expectEqual(-std.math.maxInt(i16), std.mem.readInt(i16, bytes[2..4], .little));
    try testing.expectEqual(0, std.mem.readInt(i16, bytes[4..6], .little));
    try testing.expectEqual(std.math.maxInt(i16), std.mem.readInt(i16, bytes[6..8], .little));
}

test "s16 round trip within 1/32767; wrong byte length rejected, nothing written" {
    var src_samples: [8]f32 = undefined;
    for (&src_samples, 0..) |*s, i| s.* = -0.9 + 0.25 * @as(f32, @floatFromInt(i));
    const src = ConstAudioBlock(f32){ .samples = &src_samples, .channel_count = 2, .frame_count = 4, .channel_stride = 4 };

    var bytes: [16]u8 = undefined;
    try S16.writeInterleaved(&bytes, src);

    var dst_samples = [_]f32{0} ** 8;
    const dst = AudioBlock(f32){ .samples = &dst_samples, .channel_count = 2, .frame_count = 4, .channel_stride = 4 };
    try S16.readInterleaved(dst, &bytes);

    for (src_samples, dst_samples) |a, b| try testing.expectApproxEqAbs(a, b, 1.0 / 32767.0);

    // interleaved order on the wire: frame 0 is (ch0[0], ch1[0])
    try testing.expectEqual(S16.decode(bytes[0..2]), dst.getSamples(0)[0]);
    try testing.expectEqual(S16.decode(bytes[2..4]), dst.getSamples(1)[0]);

    var short: [15]u8 = [_]u8{0x55} ** 15;
    try testing.expectError(error.size_mismatch, S16.writeInterleaved(&short, src));
    for (short) |b| try testing.expectEqual(0x55, b);

    var untouched = [_]f32{7} ** 8;
    const untouched_block = AudioBlock(f32){ .samples = &untouched, .channel_count = 2, .frame_count = 4, .channel_stride = 4 };
    try testing.expectError(error.size_mismatch, S16.readInterleaved(untouched_block, short[0..15]));
    for (untouched) |s| try testing.expectEqual(7, s);
}

test "padding past frame_count is never read or written" {
    // 3 active frames, stride 4: the 4th sample of each channel is padding
    var samples = [_]f32{ 0.1, 0.2, 0.3, 99, -0.1, -0.2, -0.3, 99 };
    const src = ConstAudioBlock(f32){ .samples = &samples, .channel_count = 2, .frame_count = 3, .channel_stride = 4 };

    var bytes: [S16.byteLength(2, 3)]u8 = undefined;
    try S16.writeInterleaved(&bytes, src);

    var out = [_]f32{ 0, 0, 0, 42, 0, 0, 0, 42 };
    const dst = AudioBlock(f32){ .samples = &out, .channel_count = 2, .frame_count = 3, .channel_stride = 4 };
    try S16.readInterleaved(dst, &bytes);

    try testing.expectEqual(42, out[3]);
    try testing.expectEqual(42, out[7]);
}
