const std = @import("std");
const specs = @import("../audio_specs.zig");

pub const AccessPattern = enum {
    interleaved,
    non_interleaved,
};

pub fn ChannelView(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("ChannelView only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        buffer: []T,
        n_channels: usize,
        block_size: usize,
        access: AccessPattern,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, n_channels: usize, block_size: specs.BlockSize, access: AccessPattern) !Self {
            const buffer_len = @as(usize, @intFromEnum(block_size) * n_channels);

            return Self{
                .buffer = try allocator.alloc(T, buffer_len),
                .block_size = @intFromEnum(block_size),
                .n_channels = n_channels,
                .access = access,
                .allocator = allocator,
            };
        }

        // note there is no bounds checking here. program will just crash if you try to read out of bounds
        pub inline fn readSample(self: Self, at_channel: usize, at_frame: usize) T {
            return switch (self.access) {
                .interleaved => self.buffer[at_frame * self.n_channels + at_channel],
                .non_interleaved => self.buffer[at_channel * self.block_size + at_frame],
            };
        }

        pub inline fn writeSample(self: *Self, at_channel: usize, at_frame: usize, sample: T) void {
            switch (self.access) {
                .interleaved => self.buffer[at_frame * self.n_channels + at_channel] = sample,
                .non_interleaved => self.buffer[at_channel * self.block_size + at_frame] = sample,
            }
        }

        pub inline fn totalSampleCount(self: Self) usize {
            return self.buffer.len;
        }

        pub inline fn zero(self: *Self) void {
            @memset(self.buffer, 0);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
        }
    };
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

test "ChannelView - initialization with valid parameters" {
    const allocator = std.testing.allocator;

    var view = try ChannelView(f32).init(allocator, 2, .blk_128, .interleaved);
    defer view.deinit();

    try expectEqual(view.n_channels, 2);
    try expectEqual(view.block_size, 128);
    try expectEqual(view.access, .interleaved);
    try expectEqual(view.buffer.len, 256);
}

test "ChannelView - interleaved read/write f32" {
    const allocator = std.testing.allocator;

    var view = try ChannelView(f32).init(allocator, 2, .blk_256, .interleaved);
    defer view.deinit();

    try expectEqual(view.buffer.len, 512);

    // Initialize samples
    view.writeSample(0, 0, 1.0);
    view.writeSample(1, 0, 2.0);
    view.writeSample(0, 1, 3.0);
    view.writeSample(1, 1, 4.0);

    // Verify values
    try expectEqual(view.readSample(0, 0), 1.0);
    try expectEqual(view.readSample(1, 0), 2.0);
    try expectEqual(view.readSample(0, 1), 3.0);
    try expectEqual(view.readSample(1, 1), 4.0);
}

test "ChannelView - non-interleaved read/write f32" {
    const allocator = std.testing.allocator;

    var view = try ChannelView(f32).init(allocator, 2, .blk_1024, .non_interleaved);
    defer view.deinit();

    try expectEqual(view.buffer.len, 2048);

    view.writeSample(0, 0, 1.0);
    view.writeSample(1, 0, 2.0);
    view.writeSample(0, 1, 3.0);
    view.writeSample(1, 1, 4.0);

    try expectEqual(view.readSample(0, 0), 1.0);
    try expectEqual(view.readSample(1, 0), 2.0);
    try expectEqual(view.readSample(0, 1), 3.0);
    try expectEqual(view.readSample(1, 1), 4.0);
}

test "ChannelView - f64 support" {
    const allocator = std.testing.allocator;

    var view = try ChannelView(f64).init(allocator, 2, .blk_2048, .interleaved);
    defer view.deinit();

    view.writeSample(0, 0, 1.0);
    try expectEqual(view.readSample(0, 0), 1.0);

    view.writeSample(0, 0, 5.0);
    try expectEqual(view.readSample(0, 0), 5.0);
}

test "ChannelView - single channel" {
    const allocator = std.testing.allocator;

    var view = try ChannelView(f32).init(allocator, 1, .blk_256, .interleaved);
    defer view.deinit();

    view.writeSample(0, 0, 1.0);
    view.writeSample(0, 1, 2.0);
    view.writeSample(0, 2, 3.0);

    try expectEqual(view.readSample(0, 1), 2.0);
}

test "ChannelView - large buffer operations" {
    const allocator = std.testing.allocator;

    var view = try ChannelView(f32).init(allocator, 4, .blk_256, .interleaved);
    defer view.deinit();

    try expectEqual(view.block_size, 256);

    // Initialize the buffer
    for (0..view.buffer.len) |i| {
        view.buffer[i] = @as(f32, @floatFromInt(i));
    }

    // Test read/write
    try expectEqual(view.readSample(0, 0), 0.0);
    try expectEqual(view.readSample(3, 0), 3.0);
    try expectEqual(view.readSample(0, 1), 4.0);

    view.writeSample(0, 0, 100.0);
    view.writeSample(3, 255, 999.0);

    try expectEqual(view.buffer[0], 100.0);
    try expectEqual(view.buffer[1023], 999.0);
}

test "ChannelView - non-interleaved large buffer" {
    const allocator = std.testing.allocator;

    var view = try ChannelView(f32).init(allocator, 4, .blk_256, .non_interleaved);
    defer view.deinit();

    // Write test pattern
    for (0..4) |channel| {
        for (0..256) |frame| {
            view.writeSample(channel, frame, @as(f32, @floatFromInt(channel * 256 + frame)));
        }
    }

    // Verify the pattern
    for (0..4) |channel| {
        for (0..256) |frame| {
            const expected = @as(f32, @floatFromInt(channel * 256 + frame));
            try expectEqual(view.readSample(channel, frame), expected);
        }
    }
}
