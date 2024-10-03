const std = @import("std");
const transforms = @import("transforms.zig");
const utilities = @import("utils.zig");
const waves = @import("waves.zig");

// no heap allocations

// using f32 across the board
const T: type = f32;
const sr: T = 44100;
const bz: usize = @intFromEnum(transforms.FFTSize.fft_512);

const sineGen = waves.Sine(T).init(1000, 0.9, sr);
const utils = utilities.Utils(T);
const fft = transforms.FourierStatic(T, .fft_512);

var alloc_buf: [fft.complexVectorSize()]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&alloc_buf);
const allocator = fba.allocator();

var mags_buf: [bz]T = undefined;
var phases_buf: [bz]T = undefined;
var freqs_buf: [fft.maxBinCount()]T = undefined;

const Data = struct {
    freqs: []T = undefined,
    mags: []T = undefined,
    phases: []T = undefined,
};

pub fn fftSineWave() !void {
    // 5 in seconds
    const size: usize = 5 * @as(usize, @intFromFloat(sr));
    var sine_buffer: [size]T = undefined;

    const sine = sineGen.generate(&sine_buffer);

    var complex_vec = try fft.createComplexVectorFrom(allocator, sine[0..bz]);
    var remaining: usize = size - bz;
    var current: usize = bz;

    while (remaining > bz) : (remaining -= bz) {
        complex_vec = try fft.fft(&complex_vec);

        const data = try writeData(complex_vec);
        _ = data;
        complex_vec = try fft.fillComplexVector(&complex_vec, sine[current .. current + bz]);

        current += bz;
    }

    complex_vec = try fft.fillComplexVectorWithPadding(&complex_vec, sine[current .. current + remaining]);
    complex_vec = try fft.fft(&complex_vec);

    const data = try writeData(complex_vec);

    try writeToDisk("sine_wave.txt", data);

    std.debug.print("done: remaining: {d}, current: {d}\n", .{ remaining, current });
}

fn writeData(vec: fft.ComplexVector) !Data {
    const mags = try fft.magnitude(vec, &mags_buf);
    const phases = try fft.phase(vec, &phases_buf);
    const freqs = utils.frequencyBins(bz, sr, &freqs_buf);

    return Data{ .freqs = freqs, .mags = mags, .phases = phases };
}

fn writeToDisk(filename: []const u8, data: Data) !void {
    const dir = std.fs.cwd();

    var buffer: [100]u8 = undefined;
    const path = try std.fmt.bufPrint(&buffer, "{s}", .{filename});

    var file = try dir.createFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    try file.seekTo(stat.size);

    var r_size: usize = 0;

    r_size = try file.write("freqs = [ ");
    try file.seekBy(@as(i64, @intCast(r_size)));

    for (data.mags) |mag| {
        var buf: [100]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{d},", .{mag});
        r_size = try file.write(line);
        try file.seekBy(@as(i64, @intCast(r_size)));
    }

    r_size = try file.write("]\n\n");
    try file.seekBy(@as(i64, @intCast(r_size)));
}
