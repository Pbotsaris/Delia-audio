pub const transforms = @import("transforms.zig");
pub const waves = @import("waves.zig");
pub const utils = @import("utils.zig");
pub const analysis = @import("analysis.zig");
pub const complex_matrix = @import("complex_matrix.zig");
pub const complex_list = @import("complex_list.zig");

test {
    @import("std").testing.refAllDecls(transforms);
    @import("std").testing.refAllDecls(waves);
    @import("std").testing.refAllDecls(utils);
    @import("std").testing.refAllDecls(analysis);
    @import("std").testing.refAllDecls(complex_matrix);
    @import("std").testing.refAllDecls(complex_list);
}
