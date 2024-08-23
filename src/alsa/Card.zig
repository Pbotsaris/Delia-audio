const std = @import("std");
const log = std.log.scoped(.alsa);

const AlsaError = @import("error.zig").AlsaError;
const Card = @This();

pub const INTERNAL_BUFFER_SIZE: usize = 1048;
pub const MAX_PLAYBACKS: usize = 20;
pub const MAX_CAPTURES: usize = 20;

pub const Details = struct {
    index: u32,
    id: []u8 = undefined,
    name: []u8 = undefined,
    allocator: std.mem.Allocator,

    // inits from alsa C types
    pub fn init(allocator: std.mem.Allocator, index: c_int, id: [*c]const u8, name: [*c]const u8) !Details {
        var details = Details{
            .index = @as(u32, @intCast(index)),
            .allocator = allocator,
        };

        const spanned_id = std.mem.span(id);
        const spanned_name = std.mem.span(name);

        details.id = try details.allocator.alloc(u8, spanned_id.len);
        details.name = try details.allocator.alloc(u8, spanned_name.len);

        @memcpy(details.id, spanned_id);
        @memcpy(details.name, spanned_name);

        return details;
    }

    pub fn format(self: Details, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("index: {d}\n", .{self.index});
        try writer.print("id:    {s}\n", .{self.id});
        try writer.print("name:  {s}\n", .{self.name});
        // try writer.writeAll("");
    }

    pub fn deinit(self: Details) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
    }
};

details: Details,
captures: std.ArrayList(Details),
playbacks: std.ArrayList(Details),

allocator: std.mem.Allocator,
pub fn init(allocator: std.mem.Allocator, details: Details) !Card {
    return Card{ //
        .allocator = allocator,
        .details = details,
        .captures = std.ArrayList(Details).init(allocator),
        .playbacks = std.ArrayList(Details).init(allocator),
    };
}

pub fn format(self: Card, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    try writer.print("{s}\n", .{self.details});
    try writer.print("Playbacks: ({d})\n", .{self.playback_count});

    for (self.playbacks.items) |playback| {
        try writer.print("  {s}", .{playback});
    }
    try writer.print("Captures: ({d})\n", .{self.capture_count});

    for (self.captures.items) |capture| {
        try writer.print("  {s}", .{capture});
    }

    // try writer.writeAll("\n");
}

pub fn addPlayback(self: *Card, index: c_int, id: [*c]const u8, name: [*c]const u8) !void {
    try self.playbacks.append(try Details.init(self.allocator, index, id, name));
}

pub fn addCapture(self: *Card, index: c_int, id: [*c]const u8, name: [*c]const u8) !void {
    try self.captures.append(try Details.init(self.allocator, index, id, name));
}

pub fn deinit(self: *Card) void {
    self.details.deinit();

    for (self.playbacks.items) |*playback| {
        playback.*.deinit();
    }
    for (self.captures.items) |*capture| {
        capture.*.deinit();
    }

    self.playbacks.deinit();
    self.captures.deinit();
}
