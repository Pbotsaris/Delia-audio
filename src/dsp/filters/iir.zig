const std = @import("std");

pub const BufferSize = enum(usize) {
    bz_128 = 128,
    bz_256 = 256,
    bz_512 = 512,
    bz_1024 = 1024,
    bz_2048 = 2048,
    bz_4096 = 4096,
    bz_8192 = 8192,

    pub fn fromInt(int: usize) ?BufferSize {
        switch (int) {
            128 => return .bz_128,
            256 => return .bz_256,
            512 => return .bz_512,
            1024 => return .bz_1024,
            2048 => return .bz_2048,
            4096 => return .bz_4096,
            8192 => return .bz_8192,
            else => return null,
        }
    }
};

pub const FirstOrderFilterType = enum {
    lowpass,
    highpass,
    allpass,
};

pub const FilterInitOptions = struct {
    cutoff: u32 = 100,
    q: u32 = 0.707,
};

pub fn CannonicalFirstOrder(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("CannonicalFirstOrder only supports f32 and f64");
    }
    const Self = @This();

    return struct {
        cutoff: T,
        q: T,
        sample_rate: T,
        // coefficients
        b0: T = 0,
        b1: T = 0,
        a1: T = 0,
        type: FirstOrderFilterType,

        pub fn init(sample_rate: u32, filter_type: FirstOrderFilterType, opts: FilterInitOptions) Self {
            return .{
                .cutoff = @floatFromInt(opts.cutoff),
                .q = @floatFromInt(opts.q),
                .sample_rate = @floatFromInt(sample_rate),
                .type = filter_type,
            };
        }

        fn calcCoeffs(self: *Self) Self {
            const k = calcK(self.cutoff, self.sample_rate);
            switch (self.filter_type) {
                .lowpass => {
                    self.b0 = k / (k + 1);
                    self.b1 = k / (k - 1);
                    self.a1 = (k - 1) / (k + 1);
                },
                .highpass => {
                    self.b0 = 1 * (k + 1);
                    self.b1 = -1 / (k + 1);
                    self.a1 = (k - 1) * (k + 1);
                },
                .allpass => {
                    self.b0 = (k - 1) / (k + 1);
                    self.b1 = 1;
                    self.a1 = (k - 1) / (k + 1);
                },
            }
        }

        fn calcK(cutoff: T, sample_rate: T) T {
            return std.math.tan(std.math.pi * cutoff / sample_rate);
        }
    };
}

const testing = std.testing;

test "CannonicalFirstOrder" {}
