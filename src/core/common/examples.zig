
//! A shared data structure that is used to run module examples using `zig build example -- <module> <example> <args...>`.
const std = @import("std");

pub const Command = struct {
    /// The name of the example, which is used to invoke it from the command line.
    name: []const u8,
    /// A short description of what the example does
    usage: []const u8,
    /// The function to run when the example is invoked.
    run: *const fn (args: []const [:0]const u8) anyerror!void,
};
