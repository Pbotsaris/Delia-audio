//const std = @import("std");
//const fomrat = @import("Format.zig").Format;
//
//const AudioData = @This();
//format: Format,
//channels: u32,
//data: []u8,
//position: usize,
//
//pub const AudioDataError = error{
//    invalid_type,
//    invalid_size,
//    out_of_space,
//    empty_slice,
//};
//
//pub fn init(data: []u8, channels: u32, format: Format) AudioData {
//    return AudioData{
//        .format = format,
//        .channels = channels,
//        .data = data,
//        .position = 0,
//    };
//}
//
//pub fn write(self: *AudioData, samples: anytype) AudioDataError!void {
//    const T = @TypeOf(samples);
//
//    if (isSlice(T)) {
//        if (samples.len == 0) {
//            return AudioDataError.empty_slice;
//        }
//
//        const R = @TypeOf(samples[0]);
//
//        if (self.format.sample_type.isValidType(R)) {
//            return AudioDataError.invalid_type;
//        }
//
//        for (samples) |s| try writeOne(self, s);
//        return;
//    }
//
//    if (self.format.sample_type.isValidType(T)) {
//        return AudioDataError.invalid_type;
//    }
//
//    try writeOne(self, samples);
//}
//
//pub fn hasSpaceFor(self: AudioData, samples: anytype) !bool {
//    const T = @TypeOf(samples);
//
//    if (isSlice(T)) {
//        if (samples.len == 0) {
//            return AudioDataError.empty_slice;
//        }
//
//        const R = @TypeOf(samples[0]);
//
//        if (self.format.sample_type.isValidType(R)) {
//            return AudioDataError.invalid_type;
//        }
//
//        const sample_size = @sizeOf(R);
//
//        // being a bit paranoid here
//        if (sample_size != self.format.byte_rate) {
//            return AudioDataError.invalid_size;
//        }
//
//        const total_size = sample_size * samples.len;
//        return self.hasSpace(total_size);
//    }
//
//    if (self.format.sample_type.isValidType(T)) {
//        return AudioDataError.invalid_type;
//    }
//
//    const sample_size = @sizeOf(samples);
//
//    if (sample_size != self.format.byte_rate) {
//        return AudioDataError.invalid_size;
//    }
//
//    return self.hasSpace(sample_size);
//}
//
//fn writeOne(self: *AudioData, sample: anytype) AudioDataError!void {
//    const sample_size = @sizeOf(sample);
//    const byte_offset = self.position * sample_size;
//
//    if (sample_size != self.format.byte_rate) {
//        return AudioDataError.invalid_size;
//    }
//
//    if (!self.hasSpace(sample_size)) return AudioDataError.out_of_space;
//
//    const bytes: []u8 = @as([*]u8, @ptrCast(&sample))[0..sample_size];
//    @memcpy(self.buffer[byte_offset .. byte_offset + sample_size], bytes);
//}
//
//fn hasSpace(self: AudioData, sample_size: anytype) bool {
//    const remaning = self.buffer.len - (self.position * sample_size);
//    return remaning >= sample_size;
//}
//
//inline fn isSlice(T: type) bool {
//    return switch (@typeInfo(T)) {
//        .slice => true,
//        else => false,
//    };
//}
//
//const testing = std.testing;
//
//test "AudioData.init initializes correctly" {
//    var buffer: [128]u8 = undefined;
//    const channels = 2;
//    const mockFormat = Format{
//        .format_type = .signed_16bits_little_endian,
//        .signedness = .signed,
//        .byte_order = .little_endian,
//        .bit_depth = 16,
//        .byte_rate = 2,
//        .sample_type = .t_i16,
//        .physical_width = 16,
//        .physical_byte_rate = 2,
//    };
//
//    const audio_data = AudioData.init(&buffer, channels, mockFormat);
//
//    try testing.expectEqual(mockFormat, audio_data.format);
//    try testing.expectEqual(channels, audio_data.channels);
//    try testing.expectEqualSlices(u8, buffer[0..], audio_data.data);
//    try testing.expectEqual(0, audio_data.position);
//}
//
//test "AudioData.write writes single sample correctly" {
//    var buffer: [128]u8 = undefined;
//
//    const slice = &buffer;
//
//    //    std.debug.print("slice: {any}\n", .{@typeInfo(@TypeOf(slice))});
//    //    std.debug.print("buffer: {any}\n", .{@typeInfo(@TypeOf(buffer))});
//    //    std.debug.print("{any}\n", .{@TypeOf(slice)});
//    //
//    switch (@typeInfo(@TypeOf(slice))) {
//        .Pointer => |ptr| std.debug.print("child: {any} \n", .{ptr.child}),
//        else => std.debug.print("is not pointer\n", .{}),
//    }
//
//    //    const channels = 2;
//    //    const mockFormat = Format{
//    //        .format_type = .signed_16bits_little_endian,
//    //        .signedness = .signed,
//    //        .byte_order = .little_endian,
//    //        .bit_depth = 16,
//    //        .byte_rate = 2,
//    //        .sample_type = .t_i16,
//    //        .physical_width = 16,
//    //        .physical_byte_rate = 2,
//    //    };
//    //
//    //    var audio_data = AudioData.init(&buffer, channels, mockFormat);
//    //
//    //    const sample: i16 = 1234;
//    //    try audio_data.write(sample);
//    //
//    //    try testing.expectEqualSlices(u8, @as([*]u8, &sample)[0..2], buffer[0..2]);
//    //    try testing.expectEqual(1, audio_data.position);
//}
