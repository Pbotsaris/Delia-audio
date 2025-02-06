const node_interface = @import("node_interface.zig");

pub fn GainNode(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("GainNode operates on f32 or f64");
    }

    const GenericNode = node_interface.GenericNode(T);
    return struct {
        gain: T,

        const Self = @This();
        const PrepareContext = GenericNode.PrepareContext;
        const ProcessContext = GenericNode.ProcessContext;

        pub fn process(self: *Self, ctx: ProcessContext) void {
            for (0..ctx.buffer.n_frames) |frame_index| {
                const sample = ctx.buffer.readSample(0, frame_index);
                ctx.buffer.writeSample(0, frame_index, sample * self.gain);
            }
        }

        pub fn prepare(_: *Self, _: PrepareContext) void {}
    };
}
