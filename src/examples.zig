const std = @import("std");
const dsp = @import("dsp/dsp.zig");
const graph = @import("graph/graph.zig");
const specs = @import("common/audio_specs.zig");
const alsa = @import("backends/backends.zig").alsa;

pub const std_options = .{
    .log_level = .debug,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.main);

// Pick the hardware device format
const format = alsa.driver.FormatType.signed_16bits_little_endian;

// Create a device time for this given format and struct that will server as the context
// for the callback
const Device = alsa.driver.HalfDuplexDevice(Example, .{
    .format = format,
});

const AudioDataType = Device.AudioDataType();

// get the float for the given audio format
const T = alsa.audio_data.GenericAudioData(format).FloatType();

pub const Example = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    scheduler: graph.scheduler.Scheduler(T),
    sample_rate: specs.SampleRate,
    device: Device,

    pub fn init(allocator: std.mem.Allocator, sample_rate: specs.SampleRate) !Example {
        const dev = try Device.init(allocator, .{
            .sample_rate = sample_rate,
            .channels = .stereo,
            .stream_type = .playback,
            .buffer_size = .buf_512,
            .ident = "hw:3,0",
        });

        return Example{
            .allocator = allocator,
            .scheduler = graph.scheduler.Scheduler(T).init(allocator),
            .device = dev,
            .sample_rate = sample_rate,
        };
    }

    pub fn prepare(self: *Self) !void {
        self.scheduler.build_graph(self.sample_rate) catch |err| {
            log.err("Failed to build graph: {any}", .{err});
            return;
        };

        try self.scheduler.prepare(.{
            .n_channels = 2,
            .block_size = .blk_256,
            .sample_rate = self.sample_rate.toFloat(T),
            .access_pattern = .interleaved,
        });

        try self.device.prepare();
    }

    pub fn callback(ctx: *Self, data: AudioDataType) void {
        const buffer_size = data.bufferSizeInFrames();
        const process_block_size = ctx.scheduler.blockSize();

        // could do extra checks between buffer size and process block size
        const iterations = @divFloor(buffer_size, process_block_size);

        for (iterations) |_| {
            ctx.scheduler.processGraph() catch |err| {
                log.err("Failed to process data: {!}", .{err});
                return;
            };

            // could ignore this check
            var audio_buffer = ctx.scheduler.getOutputBuffer() orelse {
                log.err("Buffer is null", .{});
                return;
            };

            data.write(audio_buffer.buffer) catch |err| {
                log.err("Failed to write data: {!}", .{err});
                return;
            };

            audio_buffer.zero();
        }
    }

    pub fn run(self: *Self) !void {
        try self.device.start(self, @field(Self, "callback"));
    }

    pub fn deinit(self: *Self) !void {
        try self.device.deinit();
        self.scheduler.deinit();
        try self.device.deinit();
    }
};
