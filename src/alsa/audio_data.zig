const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

const FormatType = @import("settings.zig").FormatType;
const Format = @import("format.zig").Format;

pub const AudioDataError = error{
    invalid_type,
    invalid_size,
    out_of_bounds,
    unexpected_buffer_size,
};

pub fn AudioData(format_type: FormatType) type {
    const T = format_type.ToType();
    return struct {
        const Self = @This();
        format: Format(T),
        channels: u32,
        data: []u8,
        position: usize,

        pub fn init(data: []u8, channels: u32, format: Format(T)) Self {
            return Self{
                .format = format,
                .channels = channels,
                .data = data,
                .position = 0,
            };
        }

        pub fn writeSample(self: *Self, sample: T) AudioDataError!void {
            const sample_size = @sizeOf(T);

            if (sample_size != self.format.byte_rate) {
                return AudioDataError.invalid_size;
            }

            if (!self.hasSpace(sample_size)) return AudioDataError.out_of_bounds;

            var bytes: [sample_size]u8 = undefined;
            const endianness: std.builtin.Endian = if (self.format.byte_order == .big_endian) .big else .little;

            switch (T) {
                f32, f64 => writeFloat(&bytes, sample, endianness),
                else => std.mem.writeInt(T, &bytes, sample, endianness),
            }

            @memcpy(self.data[self.position .. self.position + sample_size], &bytes);
            self.position += sample_size;
        }

        pub fn write(self: *Self, samples: []T) AudioDataError!void {
            for (samples) |sample| {
                try writeSample(self, sample);
            }
        }

        pub fn readSample(self: *Self) ?T {
            if (self.data.len == 0) return null;
            if (self.position >= self.data.len) return null;

            const sample_size: usize = @sizeOf(T);

            var sample_buffer: [sample_size]u8 = undefined;
            @memcpy(&sample_buffer, self.data[self.position .. self.position + sample_size]);

            const endianness: std.builtin.Endian = if (self.format.byte_order == .big_endian) .big else .little;

            const sample: T = switch (T) {
                f32, f64 => readFloat(&sample_buffer, endianness),
                else => std.mem.readInt(T, &sample_buffer, endianness),
            };

            self.position += sample_size;

            return sample;
        }

        pub fn readAllAlloc(self: Self, allocator: std.mem.Allocator) AudioDataError!?[]T {
            if (self.data.len == 0) return null;
            if (self.position >= self.data.len) return null;

            const sample_size = @sizeOf(T);

            // if the sample size is not a multiple of the data length, there is a bug. It should never happen
            if (self.data.len % sample_size != 0) {
                return AudioDataError.unexpected_buffer_size;
            }

            const samples_len = @divFloor(self.data.len, sample_size);
            const samples = try allocator.alloc(T, samples_len);

            for (0..samples_len) |sample_index| {
                const sample: T = self.readSample() orelse return samples;
                samples[sample_index] = sample;
            }

            return samples;
        }

        pub fn rewind(self: *Self) void {
            self.position = 0;
        }

        pub fn seek(self: *Self, sample_position: usize) !void {
            const sample_size = @sizeOf(T);
            const new_position = sample_position * sample_size;

            if (new_position >= self.data.len) {
                return AudioDataError.out_of_bounds;
            }

            self.position = new_position;
        }

        fn hasSpace(self: Self, sample_size: i32) bool {
            // cast to signed to prevent wrapping when negative
            const len: i32 = @intCast(self.data.len);
            const position: i32 = @intCast(self.position);
            const remaning: i32 = len - position;

            if (remaning < 0) return false; // this will never happen but....

            return remaning >= sample_size;
        }

        fn readFloat(sample_buffer: *[@sizeOf(T)]u8, endianness: std.builtin.Endian) T {
            const FT = switch (@sizeOf(T)) {
                1 => u8,
                2 => u16,
                4 => u32,
                8 => u64,
                else => u64,
            };

            const sample = std.mem.readInt(FT, sample_buffer, endianness);
            return @bitCast(sample);
        }

        fn writeFloat(buffer: *[@sizeOf(T)]u8, sample: T, endianness: std.builtin.Endian) void {
            const FT = switch (@sizeOf(T)) {
                1 => u8,
                2 => u16,
                4 => u32,
                8 => u64,
                else => u64,
            };

            std.mem.writeInt(FT, buffer, @bitCast(sample), endianness);
        }
    };
}

const testing = std.testing;

test "AudioData.init initializes correctly" {
    var buffer: [128]u8 = undefined;
    const channels = 2;
    const format_type = FormatType.signed_16bits_little_endian;
    const mockFormat = Format(format_type.ToType()){
        .format_type = format_type,
        .signedness = .signed,
        .byte_order = .little_endian,
        .bit_depth = 16,
        .byte_rate = 2,
        .physical_width = 16,
        .physical_byte_rate = 2,
        .sample_type = 0,
    };

    const data = AudioData(format_type).init(&buffer, channels, mockFormat);

    try testing.expectEqual(mockFormat, data.format);
    try testing.expectEqual(channels, data.channels);
    try testing.expectEqualSlices(u8, buffer[0..], data.data);
    try testing.expectEqual(0, data.position);
}

// Mock FormatTypes
const signed_int_le = FormatType.signed_16bits_little_endian;
const signed_int_be = FormatType.signed_16bits_big_endian;
const unsigned_int_le = FormatType.unsigned_32bits_little_endian;
const unsigned_int_be = FormatType.unsigned_32bits_big_endian;
const float_le = FormatType.float64_little_endian;
const float_be = FormatType.float64_big_endian;

// Mock Formats for Signed Integers (Little-Endian and Big-Endian)
const signed_int_format_le = Format(signed_int_le.ToType()){
    .format_type = signed_int_le,
    .signedness = .signed,
    .byte_order = .little_endian,
    .bit_depth = 16,
    .byte_rate = 2,
    .physical_width = 16,
    .physical_byte_rate = 2,
    .sample_type = 0,
};

const signed_int_format_be = Format(signed_int_be.ToType()){
    .format_type = signed_int_be,
    .signedness = .signed,
    .byte_order = .big_endian,
    .bit_depth = 16,
    .byte_rate = 2,
    .physical_width = 16,
    .physical_byte_rate = 2,
    .sample_type = 0,
};

// Mock Formats for Unsigned Integers (Little-Endian and Big-Endian)
const unsigned_int_format_le = Format(unsigned_int_le.ToType()){
    .format_type = unsigned_int_le,
    .signedness = .unsigned,
    .byte_order = .little_endian,
    .bit_depth = 32,
    .byte_rate = 4,
    .physical_width = 32,
    .physical_byte_rate = 4,
    .sample_type = 0,
};

const unsigned_int_format_be = Format(unsigned_int_be.ToType()){
    .format_type = unsigned_int_be,
    .signedness = .unsigned,
    .byte_order = .big_endian,
    .bit_depth = 32,
    .byte_rate = 4,
    .physical_width = 32,
    .physical_byte_rate = 4,
    .sample_type = 0,
};

// Mock Formats for Float (Little-Endian and Big-Endian)
const float_format_le = Format(float_le.ToType()){
    .format_type = float_le,
    .signedness = .signed, // floats are always signed
    .byte_order = .little_endian,
    .bit_depth = 64,
    .byte_rate = 8,
    .physical_width = 64,
    .physical_byte_rate = 8,
    .sample_type = 0,
};

const float_format_be = Format(float_be.ToType()){
    .format_type = float_be,
    .signedness = .signed, // floats are always signed
    .byte_order = .big_endian,
    .bit_depth = 64,
    .byte_rate = 8,
    .physical_width = 64,
    .physical_byte_rate = 8,
    .sample_type = 0,
};

test "AudioData.write writes a single sample correctly" {
    var signed_buffer: [128]u8 = undefined;
    var unsigned_buffer: [128]u8 = undefined;
    var float_buffer: [128]u8 = undefined;

    const channels = 2;

    const signed_int = if (native_endian == .little) signed_int_le else signed_int_be;
    const unsigned_int = if (native_endian == .little) unsigned_int_le else unsigned_int_be;
    const float = if (native_endian == .little) float_le else float_be;

    const signed_int_format = if (native_endian == .little) signed_int_format_le else signed_int_format_be;
    const unsigned_int_format = if (native_endian == .little) unsigned_int_format_le else unsigned_int_format_be;
    const float_format = if (native_endian == .little) float_format_le else float_format_be;

    var signed_int_data = AudioData(signed_int).init(&signed_buffer, channels, signed_int_format);
    var unsigned_int_data = AudioData(unsigned_int).init(&unsigned_buffer, channels, unsigned_int_format);
    var float_data = AudioData(float).init(&float_buffer, channels, float_format);

    const signed_sample: i16 = -12345;
    const unsigned_sample: u32 = 123456;
    const float_sample: f64 = 123456.789;

    try signed_int_data.writeSample(signed_sample);

    signed_int_data.rewind();

    try unsigned_int_data.writeSample(unsigned_sample);
    unsigned_int_data.rewind();

    try float_data.writeSample(float_sample);
    float_data.rewind();

    const signed_written_sample: i16 = signed_int_data.readSample() orelse 0;
    try testing.expectEqual(signed_sample, signed_written_sample);

    const unsigned_written_sample: u32 = unsigned_int_data.readSample() orelse 0;
    try testing.expectEqual(unsigned_sample, unsigned_written_sample);

    const float_written_sample: f64 = float_data.readSample() orelse 0;
    try testing.expectEqual(float_sample, float_written_sample);
}

test "AudioData.writeSample handles endianness correctly" {
    var buffer: [128]u8 = undefined;
    const channels = 1;

    const signed_int = if (native_endian == .little) signed_int_le else signed_int_be;
    const format = if (native_endian == .little) signed_int_format_le else signed_int_format_be;

    // Change to big-endian format for testing
    var data_big_endian = AudioData(signed_int).init(&buffer, channels, format);
    const sample: i16 = -123;

    // we are swaping to simulate we have a format that is not native to our system
    const swapped_sample: i16 = @byteSwap(sample);

    try data_big_endian.writeSample(swapped_sample);
    data_big_endian.rewind();

    //  When we read the sample, it will return in the swapped form, as the data is not native to our system
    const read_sample: i16 = data_big_endian.readSample() orelse 0;
    try testing.expectEqual(swapped_sample, read_sample);
}

test "AudioData.write and read multiple samples" {
    var signed_buffer: [128]u8 = undefined;
    var float_buffer: [128]u8 = undefined;
    const channels = 2;

    const signed_int = if (native_endian == .little) signed_int_le else signed_int_be;
    const float = if (native_endian == .little) float_le else float_be;

    const signed_int_format = if (native_endian == .little) signed_int_format_le else signed_int_format_be;
    const float_format = if (native_endian == .little) float_format_le else float_format_be;

    var signed_int_data = AudioData(signed_int).init(&signed_buffer, channels, signed_int_format);
    var float_data = AudioData(float).init(&float_buffer, channels, float_format);

    var signed_samples = [_]i16{ -12345, 23456, -32768 };
    var float_samples = [_]f64{ 123456.789, -987654.321, 456789.123 };

    // Write multiple samples
    try signed_int_data.write(&signed_samples);
    try float_data.write(&float_samples);

    signed_int_data.rewind();
    float_data.rewind();

    // Read and check multiple samples
    for (signed_samples) |expected| {
        const sample: i16 = signed_int_data.readSample() orelse 0;
        try testing.expectEqual(expected, sample);
    }

    for (float_samples) |expected| {
        const sample: f64 = float_data.readSample() orelse 0;
        try testing.expectEqual(expected, sample);
    }
}

test "AudioData.writeSample returns out_of_bounds when writing out of buffer space" {
    const channels = 2;
    const format_type = if (native_endian == .little) signed_int_le else signed_int_be;
    const mock_format = if (native_endian == .little) signed_int_format_le else signed_int_format_be;

    const nb_samples = 2;
    var buffer: [nb_samples * @sizeOf(i16)]u8 = undefined;

    var data = AudioData(format_type).init(&buffer, channels, mock_format);
    var samples = [_]i16{ -12345, 23456 };

    try data.write(&samples);

    try testing.expectError(AudioDataError.out_of_bounds, data.writeSample(32767));
}

test "AudioData.readSample returns null when reading out of bounds" {
    const channels = 2;
    const format_type = if (native_endian == .little) signed_int_le else signed_int_be;
    const mock_format = if (native_endian == .little) signed_int_format_le else signed_int_format_be;

    const nb_samples = 2;
    var buffer: [nb_samples * @sizeOf(i16)]u8 = undefined;

    var data = AudioData(format_type).init(&buffer, channels, mock_format);
    var samples = [_]i16{ -12345, 23456 };

    try data.write(&samples);
    data.rewind();

    // Read two samples, should succeed
    const sample1: i16 = data.readSample() orelse unreachable;
    try testing.expectEqual(samples[0], sample1);

    const sample2: i16 = data.readSample() orelse unreachable;
    try testing.expectEqual(samples[1], sample2);

    // Attempt to read beyond available samples, should return null
    const out_of_bounds_sample: ?i16 = data.readSample();
    try testing.expectEqual(null, out_of_bounds_sample);
}

test "AudioData.seek positions correctly" {
    const channels = 2;
    const format_type = if (native_endian == .little) signed_int_le else signed_int_be;
    const mock_format = if (native_endian == .little) signed_int_format_le else signed_int_format_be;

    const nb_samples = 4;
    var buffer: [nb_samples * @sizeOf(i16)]u8 = undefined;

    var data = AudioData(format_type).init(&buffer, channels, mock_format);
    var samples = [nb_samples]i16{ -12345, 23456, -32768, 32767 };
    try data.write(&samples);

    // Seek to the second sample
    try data.seek(1);
    const second_sample: i16 = data.readSample() orelse unreachable;
    try testing.expectEqual(samples[1], second_sample);

    // Seek to the last sample
    try data.seek(3);
    const last_sample: i16 = data.readSample() orelse unreachable;
    try testing.expectEqual(samples[3], last_sample);

    // Seek out of bounds should return an error
    try testing.expectError(AudioDataError.out_of_bounds, data.seek(4));
}
