const std = @import("std");
const Device = @import("Device.zig");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const Context = @This();

device: Device,

pub fn init(device: Device) Context {
    return .{
        device.device,
    };
}

const log = std.log.scoped(.alsa);

pub fn start(self: *Device) !void {
    while (self.running) {
        const err = c_alsa.snd_pcm_wait(self.pcm_handler, self.timeout);

        if (err < 0) {
            log.debug("Failed to pool device or timeout: {s}", .{c_alsa.snd_strerror(err)});
            return AlsaError.device_timeout;
        }

        // how much space is avail for playback data?
        var frames_avail: c_alsa.snd_pcm_sframes_t = c_alsa.snd_pcm_avail_update(self.pcm_handler);

        if (frames_avail < 0) {
            switch (frames_avail) {
                -c_alsa.EPIPE => {
                    log.debug("Buffer xrun detected");
                    return AlsaError.device_xrun;
                },
                else => {
                    log.debug("Unexpected error: {s}", .{c_alsa.snd_strerror(frames_avail)});
                    return AlsaError.device_unexpected;
                },
            }
        }

        frames_avail = if (frames_avail > self.buffer_size) self.buffer_size else frames_avail;

        // I cant do buff size because it's not comptime, but I can have a buffer with the max size and then slice it
        //var buffer: [self.buffer_size]u8 = undefined;

    }
}
