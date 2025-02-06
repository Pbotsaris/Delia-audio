const node_interface = @import("node_interface.zig");
const dsp = @import("../../dsp/dsp.zig");

pub fn OscillatorNode(comptime T: type) type {
    const GenericNode = node_interface.GenericNode(T);

    return struct {
        wave: dsp.waves.Wave(T),
        osc_type: OscType = .sine,

        const OscType = enum {
            sine,
            sawtooth,
        };

        const Self = @This();
        const PrepareContext = GenericNode.PrepareContext;
        const ProcessContext = GenericNode.ProcessContext;

        pub fn init(osc_type: OscType, freq: T, amp: T, sr: T) Self {
            return .{
                .wave = dsp.waves.Wave(T).init(freq, amp, sr),
                .osc_type = osc_type,
            };
        }

        pub fn process(self: *Self, ctx: ProcessContext) void {


        }

        pub fn prepare(self: *Self, ctx: PrepareContext) void {
            self.wave.setSampleRate(ctx.sample_rate);
        }
    };
}
