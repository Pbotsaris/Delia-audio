const builtin = @import("builtin");
const std = @import("std");

pub const log = if (builtin.is_test)
    struct {
        pub const base = std.log.scoped(.dsp);
        pub const warn = base.warn;
        pub const err = warn;
        pub const info = base.info;
        pub const debug = base.debug;
    }
else
    std.log.scoped(.dsp);
