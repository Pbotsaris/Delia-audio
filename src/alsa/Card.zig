const std = @import("std");
const log = std.log.scoped(.alsa);

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const AlsaError = @import("error.zig").AlsaError;
const FormatType = @import("settings.zig").FormatType;
const StreamType = @import("settings.zig").StreamType;
const settings = @import("settings.zig");
const SupportedSettings = @import("SupportedSettings.zig");
const Card = @This();

const Identifier = struct {
    device: c_int,
    card: c_int,
};

pub const HardwareDetails = struct {
    index: c_int,
    id: []u8 = undefined,
    name: []u8 = undefined,
    // identifier is going to be used to interact with the a C APi so we sentinel terminate it
    identifier: [:0]u8 = undefined,
    // only playbacks or captures details have supported settings. or stream_type.
    // Card details won't have this information as it is already in playbacks and captures
    supported_settings: ?SupportedSettings = null,
    stream_type: ?StreamType = null,
    allocator: std.mem.Allocator,

    // inits from alsa C types
    pub fn init(allocator: std.mem.Allocator, ident: Identifier, id: [*c]const u8, name: [*c]const u8) !HardwareDetails {
        var details = HardwareDetails{
            .allocator = allocator,
            .index = if (ident.device >= 0) ident.device else ident.card,
        };

        const spanned_id = std.mem.span(id);
        const spanned_name = std.mem.span(name);
        const ident_len = getLength(ident);

        details.id = try details.allocator.alloc(u8, spanned_id.len);
        details.name = try details.allocator.alloc(u8, spanned_name.len);
        var identifier = try details.allocator.alloc(u8, ident_len);
        defer details.allocator.free(identifier);

        @memcpy(details.id, spanned_id);
        @memcpy(details.name, spanned_name);

        if (ident.device >= 0) {
            identifier = try std.fmt.bufPrint(identifier, "hw:{d},{d}", .{ ident.card, ident.device });
        } else {
            identifier = try std.fmt.bufPrint(identifier, "hw:{d}", .{ident.card});
        }

        // for sentinel termination
        details.identifier = try details.allocator.dupeZ(u8, identifier);
        return details;
    }

    pub fn addSupportedFormats(self: *HardwareDetails, stream_type: StreamType) void {
        self.supported_settings = SupportedSettings.init(self.allocator, self.identifier, stream_type);
        self.stream_type = stream_type;
    }

    pub fn format(self: HardwareDetails, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("handle:      {s}\n", .{self.identifier});
        try writer.print("id:          {s}\n", .{self.id});
        try writer.print("name:        {s}\n", .{self.name});

        if (self.stream_type) |st| {
            try writer.print("stream type: {s}\n", .{@tagName(st)});
        }

        if (self.supported_settings) |ss| {
            try writer.print("{s}", .{ss});
        }
    }

    pub fn deinit(self: HardwareDetails) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.identifier);

        if (self.supported_settings) |*sf| {
            sf.*.deinit();
        }
    }

    fn getLength(ident: Identifier) usize {
        if (ident.device >= 0) return std.fmt.count("hw:{d},{d}", .{ ident.card, ident.device });
        return std.fmt.count("hw:{d}", .{ident.card});
    }
};

details: HardwareDetails,
captures: std.ArrayList(HardwareDetails),
playbacks: std.ArrayList(HardwareDetails),
// default to playback

allocator: std.mem.Allocator,
pub fn init(allocator: std.mem.Allocator, details: HardwareDetails) !Card {
    return Card{ //
        .allocator = allocator,
        .details = details,
        .captures = std.ArrayList(HardwareDetails).init(allocator),
        .playbacks = std.ArrayList(HardwareDetails).init(allocator),
    };
}

pub fn format(self: Card, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    try writer.print("\n{s}\n", .{self.details});
    try writer.print("Playbacks: ({d})\n", .{self.playbacks.items.len});

    for (self.playbacks.items) |playback| {
        try writer.print("{s}\n", .{playback});
    }
    try writer.print("Captures: ({d})\n", .{self.captures.items.len});

    for (self.captures.items) |capture| {
        try writer.print("{s}\n\n", .{capture});
    }
}

pub fn addPlayback(self: *Card, index: c_int, id: [*c]const u8, name: [*c]const u8) !void {
    var details = try HardwareDetails.init(self.allocator, .{ .card = self.details.index, .device = index }, id, name);
    details.addSupportedFormats(StreamType.playback);

    try self.playbacks.append(details);
}

pub fn addCapture(self: *Card, index: c_int, id: [*c]const u8, name: [*c]const u8) !void {
    var details = try HardwareDetails.init(self.allocator, .{ .card = self.details.index, .device = index }, id, name);
    details.addSupportedFormats(StreamType.capture);

    try self.captures.append(details);
}

pub fn getPlayback(self: Card, at: usize) !HardwareDetails {
    if (at >= self.playbacks.items.len) {
        return AlsaError.playback_out_of_bounds;
    }

    return self.playbacks.items[at];
}

pub fn getCapture(self: Card, at: usize) !HardwareDetails {
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
