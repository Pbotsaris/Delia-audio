const std = @import("std");

const Client = @import("client.zig").JackClient;

const log = std.log.scoped(.jack);

const c_jack = @cImport({
    @cInclude("jack/jack.h");
});

const JackHardwareError = error{
    no_ports_found,
};

pub const JackPort = struct {
    uuid: c_jack.jack_uuid_t, // u64
    ptr: *c_jack.jack_port_t,
    name: []u8,

    pub fn format(self: JackPort, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("│ fullname:  {s}\n", .{self.name});
        try writer.print("│ uuid:      {d}\n", .{self.uuid});
        try writer.print("│\n", .{});
    }
};

playbacks: []JackPort,
captures: []JackPort,
allocator: std.mem.Allocator,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, client: Client) !Self {
    const pb_flags = c_jack.JackPortIsPhysical | c_jack.JackPortIsInput;
    const cap_flags = c_jack.JackPortIsPhysical | c_jack.JackPortIsOutput;

    return .{
        .allocator = allocator,
        .playbacks = try getPortsAlloc(allocator, client.client, pb_flags),
        .captures = try getPortsAlloc(allocator, client.client, cap_flags),
    };
}

pub fn deinit(self: Self) void {
    for (self.playbacks) |port| {
        self.allocator.free(port.name);
    }

    for (self.captures) |port| {
        self.allocator.free(port.name);
    }

    self.allocator.free(self.playbacks);
    self.allocator.free(self.captures);
}

fn getPortsAlloc(allocator: std.mem.Allocator, client: *c_jack.jack_client_t, flags: c_ulong) ![]JackPort {
    const maybe_ports = c_jack.jack_get_ports(client, null, null, flags);
    defer c_jack.jack_free(@as(?*anyopaque, @ptrCast(maybe_ports)));

    if (maybe_ports == null) return JackHardwareError.no_ports_found;

    var len: usize = 0;
    while (maybe_ports[len] != null) : (len += 1) {}

    const ports = try allocator.alloc(JackPort, len);

    var i: usize = 0;
    while (maybe_ports[i] != null) : (i += 1) {
        const jack_port_info = maybe_ports[i] orelse continue;

        const port_ptr = c_jack.jack_port_by_name(client, jack_port_info) orelse {
            log.warn("Failed to get port by name for port: {s}.\nThis port is being skipped.\n", .{jack_port_info});
            continue;
        };

        const spanned_port_info = std.mem.span(jack_port_info);

        ports[i].name = try allocator.alloc(u8, spanned_port_info.len);
        @memcpy(ports[i].name, spanned_port_info);

        ports[i].ptr = port_ptr;
        ports[i].uuid = c_jack.jack_port_uuid(port_ptr);
    }

    return ports;
}
