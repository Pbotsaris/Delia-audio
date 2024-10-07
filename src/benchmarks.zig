const std = @import("std");
const dsp = @import("dsp/dsp.zig");
const zbench = @import("zbench");

fn fftPowerOfTwo(allocator: std.mem.Allocator) void {
    const transform = dsp.transforms.FourierDynamic(f32);

    const sineGeneration = dsp.waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var buffer: [4096]f32 = undefined;
    const sine = sineGeneration.generate(&buffer);

    var out = transform.fft(allocator, sine) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    out.deinit(allocator);
}

fn fftNonPowerOfTwo(allocator: std.mem.Allocator) void {
    const transform = dsp.transforms.FourierDynamic(f32);
    const sineGeneration = dsp.waves.Sine(f32).init(400.0, 1.0, 44100.0);

    var buffer: [4099]f32 = undefined;
    const sine = sineGeneration.generate(&buffer);

    var out = transform.fft(allocator, sine) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    out.deinit(allocator);
}

fn fftStatic(allocator: std.mem.Allocator) void {
    const transform = dsp.transforms.FourierStatic(f32, .wz_4096);

    const sineGeneration = dsp.waves.Sine(f32).init(400.0, 1.0, 44100.0);
    var buffer: [4096]f32 = undefined;
    const sine = sineGeneration.generate(&buffer);

    // this could easily be a fixed-size allocator and would improve performance
    // as complex vector is always modified in place
    var complex_vec = transform.createComplexVectorFrom(allocator, sine) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    defer complex_vec.deinit(allocator);

    complex_vec = transform.fft(&complex_vec) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    try bench.add("fft power-of-2", fftPowerOfTwo, .{});
    try bench.add("fft non power-of-2", fftNonPowerOfTwo, .{});
    try bench.add("fft static", fftStatic, .{});
    try bench.run(stdout);
}
