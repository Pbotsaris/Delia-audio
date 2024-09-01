const std = @import("std");
const Device = @import("Device.zig");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const AudioCallback = @This();

const log = std.log.scoped(.alsa);

const MAX_RETRY = 50;
const NANO_SECONDS = 1_000_000; // 100ms

device: Device,
running: bool = false,
callback: *const fn (*[]u8) void,

pub fn init(device: Device, callback: *const fn (*[]u8) void) AudioCallback {
    return .{
        .device = device,
        .callback = callback,
    };
}

fn xrunRecovery(self: *AudioCallback, c_err: c_int) !void {
    const err = if (c_err == -c_alsa.EPIPE) AlsaError.xrun else AlsaError.suspended;

    const needs_prepare = switch (err) {
        AlsaError.xrun => true,

        AlsaError.suspended => blk: {
            var res = c_alsa.snd_pcm_resume(self.device.pcm_handle);
            var sleep: u64 = 100 * NANO_SECONDS;
            var retries: i32 = MAX_RETRY;

            while (res == -c_alsa.EAGAIN) {
                if (retries == 0) {
                    log.debug("Timeout while trying to resume device.", .{});
                    return AlsaError.timeout;
                }

                std.time.sleep(sleep);

                sleep *= 2; // exponential backoff
                retries -= 1;
                res = c_alsa.snd_pcm_resume(self.device.pcm_handle);
            }

            if (res < 0) break :blk true;
            break :blk false;
        },

        else => return AlsaError.unexpected,
    };

    if (!needs_prepare) return;

    const res = c_alsa.snd_pcm_prepare(self.device.pcm_handle);

    if (res < 0) {
        log.debug("Failed to recover from xrun: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.xrun;
    }
}

pub fn start(self: *AudioCallback) !void {
    self.running = true;
    try self.directWrite();
}

fn directWrite(self: *AudioCallback) !void {
    const buffer_size: c_alsa.snd_pcm_uframes_t = @intFromEnum(self.device.buffer_size);
    var areas: ?*c_alsa.snd_pcm_channel_area_t = null;
    var stopped: bool = true;

    while (self.running) {
        const state: c_alsa.snd_pcm_state_t = c_alsa.snd_pcm_state(self.device.pcm_handle);

        // Check State

        switch (state) {
            c_alsa.SND_PCM_STATE_XRUN => {
                try self.xrunRecovery(-c_alsa.EPIPE);
                stopped = true;
            },
            c_alsa.SND_PCM_STATE_SUSPENDED => try self.xrunRecovery(-c_alsa.ESTRPIPE),

            else => {
                if (state < 0) {
                    log.debug("Unexpected state error: {s}", .{c_alsa.snd_strerror(state)});
                    return AlsaError.unexpected;
                }
            },
        }

        const avail = c_alsa.snd_pcm_avail_update(self.device.pcm_handle);

        if (avail < 0) {
            try self.xrunRecovery(@intCast(avail));
            continue;
        }

        if (avail < buffer_size and stopped) {
            const err = c_alsa.snd_pcm_start(self.device.pcm_handle);
            if (err < 0) {
                log.err("Failed to start device: {s}", .{c_alsa.snd_strerror(err)});
                return AlsaError.device_start;
            }

            stopped = false;
            continue;
        }

        if (avail < buffer_size and !stopped) {
            const err = c_alsa.snd_pcm_wait(self.device.pcm_handle, self.device.timeout);

            if (err < 0) {
                try self.xrunRecovery(err);
                stopped = true;
                continue;
            }
        }

        // Start Transfer

        // in number of frames
        var to_transfer = buffer_size;
        var offset: c_alsa.snd_pcm_uframes_t = 0;

        while (to_transfer > 0) {
            // we request for a transfer_size frames from begin but it may return less
            var expected_to_transfer = to_transfer;
            const res = c_alsa.snd_pcm_mmap_begin(self.device.pcm_handle, &areas, &offset, &expected_to_transfer);

            if (res < 0) {
                try self.xrunRecovery(res);
                stopped = true;
            }

            const written_area = areas orelse return AlsaError.unexpected;
            const addr = written_area.addr orelse return AlsaError.unexpected;
            const byte_rate: c_ulong = @intCast(self.device.audio_format.byte_rate);

            var buffer: []u8 = @as([*]u8, @ptrCast(addr))[0 .. expected_to_transfer * byte_rate];

            self.callback(&buffer);

            const frames_actually_transfered =
                c_alsa.snd_pcm_mmap_commit(self.device.pcm_handle, offset, expected_to_transfer);

            if (frames_actually_transfered < 0) {
                try self.xrunRecovery(@intCast(frames_actually_transfered));
            } else if (frames_actually_transfered != expected_to_transfer) try self.xrunRecovery(-c_alsa.EPIPE);

            to_transfer -= @as(c_ulong, @intCast(frames_actually_transfered));
        }
    }
}
