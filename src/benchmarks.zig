const std = @import("std");
const dsp = @import("dsp/dsp.zig");
const zbench = @import("zbench");

fn fftPowerOfTwo(allocator: std.mem.Allocator) void {
    //
    const transform = dsp.transforms.FourierTransforms(f32);

    const sineGeneration = dsp.waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var sine: [4096]f32 = undefined;
    sineGeneration.generate(&sine);

    var out = transform.fft(allocator, &sine) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    out.deinit(allocator);
}

fn fftNonPowerOfTwo(allocator: std.mem.Allocator) void {
    const transform = dsp.transforms.FourierTransforms(f32);
    const sineGeneration = dsp.waves.Sine(f32).init(400.0, 1.0, 44100.0);

    var sine: [4099]f32 = undefined;
    sineGeneration.generate(&sine);

    var out = transform.fft(allocator, &sine) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    out.deinit(allocator);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    try bench.add("fft power-of-2", fftPowerOfTwo, .{});
    try bench.add("fft non power-of-2", fftNonPowerOfTwo, .{});
    try bench.run(stdout);
}
