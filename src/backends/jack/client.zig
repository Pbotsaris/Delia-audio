const std = @import("std");

const c_jack = @cImport({
    @cInclude("jack/jack.h");
});

const log = std.log.scoped(.jack);
const Hardware = @import("Hardware.zig");

const port_names = @import("port_names.zig");

const default_audio_type = c_jack.JACK_DEFAULT_AUDIO_TYPE;

pub const PortHandler = struct {
    name: []const u8,
    port: ?*c_jack.jack_port_t,
    port_type: PortType,
    client: *JackClient,
};

const null_init = [_]?*c_jack.jack_port_t{null} ** (port_names.max_n_ports * 2);

pub const JackClient = struct {
    const Self = @This();

    client_name: []const u8,
    client: *c_jack.jack_client_t,
    server_name: ?[]const u8,
    allocator: std.mem.Allocator,
    hardware: Hardware,
    n_playbacks: usize = 0,
    n_captures: usize = 0,
    n_registeredPorts: usize = 0,
    registeredPorts: [port_names.max_n_ports * 2]?*c_jack.jack_port_t = null_init,
    connectedPorts: [port_names.max_n_ports * 2]?*c_jack.jack_port_t = null_init,

    pub fn init(allocator: std.mem.Allocator, opts: JackClientOptions) !Self {
        if (opts.client_name.len >= c_jack.jack_client_name_size()) {
            return JackClientError.client_name_too_long;
        }

        var jack_options = opts.jack_options;

        if (opts.server_name != null and !opts.jack_options.contains(.server_name)) {
            // we add the option if caller provided a server name but didn't set the option
            jack_options = opts.jack_options.merge(.server_name);
        }

        var open_status: c_jack.jack_status_t = undefined;

        const maybe_client = c_jack.jack_client_open(
            opts.client_name.ptr,
            jack_options.toInt(),
            &open_status,
            if (opts.server_name != null) opts.server_name.?.ptr else null,
        );

        const client = maybe_client orelse {
            if ((open_status & c_jack.JackServerFailed) != 0) {
                std.log.err("JACK server failed to start", .{});
                return JackClientError.failed_start_server;
            }

            return JackClientError.failed_open_client;
        };

        if ((open_status & c_jack.JackServerStarted) != 0) {
            std.log.info("JACK server was stopped. Starting server...", .{});
        }

        var maybe_new_name: ?[]const u8 = null;

        if ((open_status & c_jack.JackNameNotUnique) != 0) {
            const new_name = c_jack.jack_get_client_name(maybe_client);
            std.log.warn("Client name: {s} not unique. New name generated and assigned: {s}", .{ opts.client_name, new_name });
            maybe_new_name = std.mem.span(new_name);
        }

        return .{
            .client_name = maybe_new_name orelse opts.client_name,
            .server_name = opts.server_name,
            .client = client,
            .allocator = allocator,
            .hardware = try Hardware.init(allocator, client),
        };
    }

    pub fn registerPort(self: *Self, port_type: PortType) !PortHandler {
        if (port_names.maxReached(self.n_playbacks)) {
            log.err("Max number of playbacks reached: {d} >= {d}", .{ self.n_playbacks, port_names.max_n_ports });

            return JackClientError.max_ports_reached;
        }

        if (port_names.maxReached(self.n_captures)) {
            log.err("Max number of captures reached: {d} >= {d}", .{ self.n_captures, port_names.max_n_ports });

            return JackClientError.max_ports_reached;
        }

        const port_name = switch (port_type) {
            PortType.playback => blk: {
                const name = port_names.playback[self.n_playbacks];
                self.n_playbacks += 1;
                break :blk name;
            },

            PortType.capture => blk: {
                const name = port_names.capture[self.n_captures];
                self.n_captures += 1;
                break :blk name;
            },
        };

        const port = c_jack.jack_port_register(self.client, port_name.ptr, default_audio_type, port_type.toFlag(), 0);

        if (port == null) {
            log.err("Failed to register port: {s}", .{port_name});
            return JackClientError.failed_register_port;
        }

        self.registeredPorts[self.n_registeredPorts] = port;
        self.n_registeredPorts += 1;

        return .{
            .name = port_name,
            .port = port,
            .client = self,
            .port_type = port_type,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.registeredPorts) |maybe_port| {
            const port = maybe_port orelse continue;
            const err = c_jack.jack_port_unregister(self.client, port);

            if (err != 0) {
                std.log.err("Failed to unregister port: {d}", .{err});
            }
        }

        const err = c_jack.jack_client_close(self.client);

        if (err != 0) {
            std.log.err("Failed to close JACK client: {d}", .{err});
        }
    }
};

pub const JackOpenOptions = struct {
    flags: c_uint,

    pub const Flag = enum(c_uint) {
        /// Default value when no options are needed
        no_options = c_jack.JackNullOption,
        /// Do not automatically start the JACK server when it is not already running.
        /// This option is always selected if $JACK_NO_START_SERVER is defined in the
        /// calling process environment.
        no_start_server = c_jack.JackNoStartServer,
        /// Use the exact client name requested. Otherwise, JACK automatically
        /// generates a unique one if needed.
        use_exact_name = c_jack.JackUseExactName,
        /// Open with optional (char*)server_name parameter
        server_name = c_jack.JackServerName,
        /// Pass a SessionID Token that allows the session manager to
        /// identify the client again.
        session_id = c_jack.JackSessionID,
    };

    pub fn init(flag: Flag) JackOpenOptions {
        return .{ .flags = @intFromEnum(flag) };
    }

    pub fn initEmpty() JackOpenOptions {
        return .{ .flags = 0 };
    }

    pub fn merge(self: JackOpenOptions, other: Flag) JackOpenOptions {
        return .{ .flags = self.flags | @intFromEnum(other) };
    }

    pub fn contains(self: JackOpenOptions, flag: Flag) bool {
        return (self.flags & @intFromEnum(flag)) != 0;
    }

    pub fn toInt(self: JackOpenOptions) c_uint {
        return self.flags;
    }
};

const JackClientOptions = struct {
    client_name: []const u8 = "device",
    server_name: ?[]const u8 = null,
    jack_options: JackOpenOptions = JackOpenOptions.initEmpty(),
};

const JackClientError = error{
    client_name_too_long,
    failed_open_client,
    failed_start_server,
    max_ports_reached,
    failed_register_port,
};

const PortType = enum(c_int) {
    playback = c_jack.JackPortIsInput,
    capture = c_jack.JackPortIsOutput,

    pub fn toFlag(self: PortType) c_ulong {
        return @as(c_ulong, @intCast(@intFromEnum(self)));
    }
};
