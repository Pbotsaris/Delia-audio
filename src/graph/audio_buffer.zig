const std = @import("std");

const AccessPattern = enum {
    interleaved,
    non_interleaved,
};

pub fn ChannelView(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("ChannelView only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        const ChannelViewError = error{
            invalid_channel_count,
            empty_buffer,
        };

        buffer: []T,
        n_channels: usize,
        n_frames: usize,
        access: AccessPattern,

        pub fn init(buffer: []T, n_channels: usize, access: AccessPattern) !Self {
            // empty buffers are not allowed
            if (buffer.len == 0) {
                return ChannelViewError.empty_buffer;
            }

            if (buffer.len % n_channels != 0) {
                return ChannelViewError.invalid_channel_count;
            }

            const n_frames = @divFloor(buffer.len, n_channels);

            return Self{
                .buffer = buffer,
                .n_frames = n_frames,
                .n_channels = n_channels,
                .access = access,
            };
        }

        // note there is no bounds checking here. program will just crash if you try to read out of bounds
        pub inline fn readSample(self: Self, at_channel: usize, at_frame: usize) T {
            return switch (self.access) {
                .interleaved => self.buffer[at_frame * self.n_channels + at_channel],
                .non_interleaved => self.buffer[at_channel * self.n_frames + at_frame],
            };
        }

        pub inline fn writeSample(self: *Self, at_channel: usize, at_frame: usize, sample: T) void {
            switch (self.access) {
                .interleaved => self.buffer[at_frame * self.n_channels + at_channel] = sample,
                .non_interleaved => self.buffer[at_channel * self.n_frames + at_frame] = sample,
            }
        }
    };
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "ChannelView - initialization with valid parameters" {
    var buffer = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const view = try ChannelView(f32).init(&buffer, 2, .interleaved);
    try expectEqual(view.n_channels, 2);
    try expectEqual(view.n_frames, 2);
    try expectEqual(view.access, .interleaved);
}

test "ChannelView - initialization with invalid channel count" {
    var buffer = [_]f32{ 1.0, 2.0, 3.0 }; // 3 samples can't be evenly divided into 2 channels
    try expectError(ChannelView(f32).ChannelViewError.invalid_channel_count, ChannelView(f32).init(&buffer, 2, .interleaved));
}

test "ChannelView - initialization with Empty buffer" {
    var buffer = [_]f32{};
    try expectError(ChannelView(f32).ChannelViewError.empty_buffer, ChannelView(f32).init(&buffer, 0, .interleaved));
}

test "ChannelView - interleaved read/write f32" {
    var buffer = [_]f32{ 1.0, 2.0, 3.0, 4.0 }; // [ch1, ch2, ch1, ch2]
    var view = try ChannelView(f32).init(&buffer, 2, .interleaved);

    // Test reading
    try expectEqual(view.readSample(0, 0), 1.0); // First sample, first channel
    try expectEqual(view.readSample(1, 0), 2.0); // First sample, second channel
    try expectEqual(view.readSample(0, 1), 3.0); // Second sample, first channel
    try expectEqual(view.readSample(1, 1), 4.0); // Second sample, second channel

    // Test writing
    view.writeSample(0, 0, 5.0);
    view.writeSample(1, 1, 6.0);
    try expectEqual(buffer[0], 5.0);
    try expectEqual(buffer[3], 6.0);
}

test "ChannelView - non-interleaved read/write f32" {
    var buffer = [_]f32{ 1.0, 2.0, 3.0, 4.0 }; // [ch1_frame1, ch1_frame2, ch2_frame1, ch2_frame2]
    var view = try ChannelView(f32).init(&buffer, 2, .non_interleaved);

    // Test reading
    try expectEqual(view.readSample(0, 0), 1.0); // First channel, first frame
    try expectEqual(view.readSample(0, 1), 2.0); // First channel, second frame
    try expectEqual(view.readSample(1, 0), 3.0); // Second channel, first frame
    try expectEqual(view.readSample(1, 1), 4.0); // Second channel, second frame

    // Test writing
    view.writeSample(0, 0, 5.0);
    view.writeSample(1, 1, 6.0);
    try expectEqual(buffer[0], 5.0);
    try expectEqual(buffer[3], 6.0);
}
test "ChannelView - f64 support" {
    var buffer = [_]f64{ 1.0, 2.0, 3.0, 4.0 };
    var view = try ChannelView(f64).init(&buffer, 2, .interleaved);

    try expectEqual(view.readSample(0, 0), 1.0);
    view.writeSample(0, 0, 5.0);
    try expectEqual(buffer[0], 5.0);
}

test "ChannelView - single channel" {
    var buffer = [_]f32{ 1.0, 2.0, 3.0 };
    var view = try ChannelView(f32).init(&buffer, 1, .interleaved);

    try expectEqual(view.n_channels, 1);
    try expectEqual(view.n_frames, 3);
    try expectEqual(view.readSample(0, 1), 2.0);
}

test "ChannelView - large buffer operations" {
    var buffer: [1024]f32 = undefined;

    for (0..buffer.len) |i| {
        buffer[i] = @as(f32, @floatFromInt(i));
    }

    var view = try ChannelView(f32).init(&buffer, 4, .interleaved);
    try expectEqual(view.n_frames, 256);

    try expectEqual(view.readSample(0, 0), 0.0);
    try expectEqual(view.readSample(3, 0), 3.0);
    try expectEqual(view.readSample(0, 1), 4.0);

    view.writeSample(0, 0, 100.0);
    view.writeSample(3, 255, 999.0);
    try expectEqual(buffer[0], 100.0);
    try expectEqual(buffer[1023], 999.0);
}

test "ChannelView - non-interleaved large buffer" {
    var buffer: [1024]f32 = undefined;
    var view = try ChannelView(f32).init(&buffer, 4, .non_interleaved);

    // Write test pattern
    for (0..4) |channel| {
        for (0..256) |frame| {
            view.writeSample(channel, frame, @as(f32, @floatFromInt(channel * 256 + frame)));
        }
    }

    // Verify pattern
    for (0..4) |channel| {
        for (0..256) |frame| {
            const expected = @as(f32, @floatFromInt(channel * 256 + frame));
            try expectEqual(view.readSample(channel, frame), expected);
        }
    }
}
