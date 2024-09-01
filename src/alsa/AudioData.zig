const std = @import("std");
const Format = @import("Format.zig");

const Self = @This();
format: Format,
channels: u32,
data: []u8,
position: usize,

pub const AudioDataError = error{
    invalid_type,
    invalid_size,
    out_of_space,
    empty_slice,
};

pub fn init(data: []u8, channels: u32, format: Format) Self {
    return Self{
        .format = format,
        .channels = channels,
        .data = data,
        .position = 0,
    };
}

pub fn write(self: *Self, samples: anytype) AudioDataError!void {
    const T = @TypeOf(samples);

    if (isSlice(T)) {
        if (samples.len == 0) {
            return AudioDataError.empty_slice;
        }

        const R = @TypeOf(samples[0]);

        if (self.format.sample_type.isValidType(R)) {
            return AudioDataError.invalid_type;
        }

        for (samples) |s| try writeOne(self, s);
        return;
    }

    if (self.format.sample_type.isValidType(T)) {
        return AudioDataError.invalid_type;
    }

    try writeOne(self, samples);
}

pub fn hasSpaceFor(self: Self, samples: anytype) !bool {
    const T = @TypeOf(samples);

    if (isSlice(T)) {
        if (samples.len == 0) {
            return AudioDataError.empty_slice;
        }

        const R = @TypeOf(samples[0]);

        if (self.format.sample_type.isValidType(R)) {
            return AudioDataError.invalid_type;
        }

        const sample_size = @sizeOf(R);

        // being a bit paranoid here
        if (sample_size != self.format.byte_rate) {
            return AudioDataError.invalid_size;
        }

        const total_size = sample_size * samples.len;
        return self.hasSpace(total_size);
    }

    if (self.format.sample_type.isValidType(T)) {
        return AudioDataError.invalid_type;
    }

    const sample_size = @sizeOf(samples);

    if (sample_size != self.format.byte_rate) {
        return AudioDataError.invalid_size;
    }

    return self.hasSpace(sample_size);
}

fn writeOne(self: *Self, sample: anytype) AudioDataError!void {
    const sample_size = @sizeOf(sample);
    const byte_offset = self.position * sample_size;

    if (sample_size != self.format.byte_rate) {
        return AudioDataError.invalid_size;
    }

    if (!self.hasSpace(sample_size)) return AudioDataError.out_of_space;

    const bytes: []u8 = @as([*]u8, @ptrCast(&sample))[0..sample_size];
    @memcpy(self.buffer[byte_offset .. byte_offset + sample_size], bytes);
}

fn hasSpace(self: Self, sample_size: anytype) bool {
    const remaning = self.buffer.len - (self.position * sample_size);
    return remaning >= sample_size;
}

inline fn isSlice(T: type) bool {
    return switch (@typeInfo(T)) {
        .slice => true,
        else => false,
    };
}
