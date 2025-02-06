const node_interface = @import("node_interface.zig");
const dsp = @import("../../dsp/dsp.zig");

pub fn SineNode(comptime T: type) type {
    const GenericNode = node_interface.GenericNode(T);

    return struct {
        wave: dsp.waves.Wave(T),

        const Self = @This();
        const PrepareContext = GenericNode.PrepareContext;
        const ProcessContext = GenericNode.ProcessContext;

        pub fn init(freq: T, amp: T, sr: T) Self {
            return .{
                .wave = dsp.waves.Wave(T).init(freq, amp, sr),
            };
        }

        pub fn process(self: *Self, ctx: ProcessContext) void {
            for (0..ctx.buffer.n_frames) |frame_index| {
                const sample = self.wave.sineSample();

                for (0..ctx.buffer.n_channels) |ch_index| {
                    ctx.buffer.writeSample(ch_index, frame_index, sample);
                }
            }
        }

        pub fn prepare(self: *Self, ctx: PrepareContext) void {
            self.wave.setSampleRate(ctx.sample_rate);
        }
    };
}
