const std = @import("std");
const log = std.log.scoped(.alsa);

const AlsaError = @import("error.zig").AlsaError;
const Card = @This();

pub const INTERNAL_BUFFER_SIZE: usize = 1048;
pub const MAX_PLAYBACKS: usize = 20;
pub const MAX_CAPTURES: usize = 20;

const Handler = struct {
    device: c_int,
    card: c_int,
};

pub const Details = struct {
    index: c_int,
    id: []u8 = undefined,
    name: []u8 = undefined,
    // handler is going to be used to interact with the a C APi so we sentinel terminate it
    handler: [:0]u8 = undefined,
    allocator: std.mem.Allocator,

    // inits from alsa C types
    pub fn init(allocator: std.mem.Allocator, handler: Handler, id: [*c]const u8, name: [*c]const u8) !Details {
        var details = Details{
            .allocator = allocator,
            .index = if (handler.device >= 0) handler.device else handler.card,
        };

        const spanned_id = std.mem.span(id);
        const spanned_name = std.mem.span(name);
        const handler_len = getLength(handler);

        details.id = try details.allocator.alloc(u8, spanned_id.len);
        details.name = try details.allocator.alloc(u8, spanned_name.len);
        var handler_name = try details.allocator.alloc(u8, handler_len);
        defer details.allocator.free(handler_name);

        @memcpy(details.id, spanned_id);
        @memcpy(details.name, spanned_name);

        if (handler.device >= 0) {
            handler_name = try std.fmt.bufPrint(handler_name, "hw:{d},{d}", .{ handler.card, handler.device });
        } else {
            handler_name = try std.fmt.bufPrint(handler_name, "hw:{d}", .{handler.card});
        }

        // for sentinel termination
        details.handler = try details.allocator.dupeZ(u8, handler_name);
        return details;
    }

    pub fn format(self: Details, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("  | handler: {d}\n", .{self.handler});
        try writer.print("  | id:    {s}\n", .{self.id});
        try writer.print("  | name:  {s}\n", .{self.name});
        try writer.print("  |_\n", .{});
    }

    pub fn deinit(self: Details) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.handler);
    }

    fn getLength(handler: Handler) usize {
        if (handler.device >= 0) return std.fmt.count("hw:{d},{d}", .{ handler.card, handler.device });
        return std.fmt.count("hw:{d}", .{handler.card});
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

    try writer.print("\n{s}\n", .{self.details});
    try writer.print("  Playbacks: ({d})\n", .{self.playbacks.items.len});

    for (self.playbacks.items) |playback| {
        try writer.print("{s}", .{playback});
    }
    try writer.print("  Captures: ({d})\n", .{self.captures.items.len});

    for (self.captures.items) |capture| {
        try writer.print("{s}", .{capture});
    }

    // try writer.writeAll("\n");
}

pub fn addPlayback(self: *Card, index: c_int, id: [*c]const u8, name: [*c]const u8) !void {
    try self.playbacks.append(try Details.init(self.allocator, .{ .card = self.details.index, .device = index }, id, name));
}

pub fn addCapture(self: *Card, index: c_int, id: [*c]const u8, name: [*c]const u8) !void {
    try self.captures.append(try Details.init(self.allocator, .{ .card = self.details.index, .device = index }, id, name));
}

pub fn getPlayback(self: Card, at: usize) !Details {
    if (at >= self.playbacks.items.len) {
        return AlsaError.playback_out_of_bounds;
    }

    return self.playbacks.items[at];
}

pub fn getCapture(self: Card, at: usize) !Details {
    if (at >= self.captures.items.len) {
        return AlsaError.capture_out_of_bounds;
    }

    return self.captures.items[at];
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
