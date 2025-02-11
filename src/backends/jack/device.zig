const std = @import("std");

const c_jack = @cImport({
    @cInclude("jack/jack.h");
});

const log = std.log.scoped(.jack);

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

const DeviceOptions = struct {
    client_name: []const u8 = "device",
    server_name: ?[]const u8 = null,
    jack_options: JackOpenOptions = JackOpenOptions.initEmpty(),
};

const JackDeviceError = error{
    client_name_too_long,
    failed_open_client,
    failed_start_server,
};

pub fn GenericDevice(comptime T: type) type {
    if (T != f32 and T != f64) {
        @compileError("Device only supports f32 and f64");
    }

    return struct {
        const Self = @This();

        client_name: []const u8,
        client: ?*c_jack.jack_client_t = null,
        server_name: ?[]const u8,

        pub fn init(opts: DeviceOptions) !Self {
            if (opts.client_name.len >= c_jack.jack_client_name_size()) {
                return JackDeviceError.client_name_too_long;
            }

            var jack_options = opts.jack_options;

            if (opts.server_name != null and !opts.jack_options.contains(.server_name)) {
                // we add the option if caller provided a server name but didn't set the option
                jack_options = opts.jack_options.merge(.server_name);
            }

            var open_status: c_jack.jack_status_t = undefined;

            const client = c_jack.jack_client_open(
                opts.client_name.ptr,
                jack_options.toInt(),
                &open_status,
                if (opts.server_name != null) opts.server_name.?.ptr else null,
            );

            if (client == null) {
                //   std.log.err("Failed to open JACK client, status: 0x{x}", open_status);
                if ((open_status & c_jack.JackServerFailed) != 0) {
                    std.log.err("JACK server failed to start", .{});
                    return JackDeviceError.failed_start_server;
                }

                return JackDeviceError.failed_open_client;
            }

            if ((open_status & c_jack.JackServerStarted) != 0) {
                std.log.info("JACK server started", .{});
            }

            if ((open_status & c_jack.JackNameNotUnique) != 0) {
                const new_name = c_jack.jack_get_client_name(client);
                std.log.warn("Client name: {s} not unique. New name generated and assigned: {s}", .{ opts.client_name, new_name });
            }

            return .{
                .client_name = opts.client_name,
                .server_name = opts.server_name,
                .client = client,
            };
        }
    };
}
