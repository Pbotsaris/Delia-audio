const std = @import("std");
const transforms = @import("transforms.zig");
const utils = @import("utils.zig");
const waves = @import("waves.zig");

// using f32 across the board
const T: type = f32;
const sr: T = 44100;

const sineGen = waves.Sine(T).init(1000, 0.9, sr);

pub fn fftSineWave() !void {}
