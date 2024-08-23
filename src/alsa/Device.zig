const std = @import("std");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const log = std.log.scoped(.alsa);
const Device = @This();

pub const StreamType = enum(c_uint) {
    playback = c_alsa.SND_PCM_STREAM_PLAYBACK,
    capture = c_alsa.SND_PCM_STREAM_CAPTURE,
};

pub const MODE_NONE: c_int = 0;
//  opens in non-blocking mode: calls to read/write audio data will return immediately
pub const MODE_NONBLOCK: c_int = c_alsa.SND_PCM_NONBLOCK;
// async for when handling audio I/O asynchronously
pub const MODE_ASYNC: c_int = c_alsa.SND_PCM_ASYNC;
// prevents automatic resampling when sample rate doesn't match hardware
pub const MODE_NO_RESAMPLE: c_int = c_alsa.SND_PCM_NO_AUTO_RESAMPLE;
// prevents from automatically ajudisting the number of channel
pub const MODE_NO_AUTOCHANNEL: c_int = c_alsa.SND_PCM_NO_AUTO_CHANNELS;
// prevents from automatically ajusting the sample format
pub const MODE_NO_AUTOFORMAT: c_int = c_alsa.SND_PCM_NO_AUTO_FORMAT;

pcm_handle: ?*c_alsa.snd_pcm_t = null,
params: ?*c_alsa.snd_pcm_hw_params_t = null,
mode: c_int,
stream_type: StreamType,
channels: u32,
sample_rate: u32,
dir: i32,

const DeviceOptions = struct {
    sample_rate: u32,
    channels: u32,
    stream_type: StreamType,
    mode: c_int,
    handler_name: [:0]const u8 = "default",
};

pub fn init(opts: DeviceOptions) !Device {
    var pcm_handle: ?*c_alsa.snd_pcm_t = null;
    var params: ?*c_alsa.snd_pcm_hw_params_t = null;
    var sample_rate: u32 = opts.sample_rate;
    var dir: i32 = 0;

    var res = c_alsa.snd_pcm_open(&pcm_handle, opts.handler_name.ptr, @intFromEnum(opts.stream_type), opts.mode);
    if (res < 0) {
        log.err("Failed to open PCM: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    res = c_alsa.snd_pcm_hw_params_malloc(&params);

    if (res < 0) {
        log.err("Failed to allocate hardware parameters: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    _ = c_alsa.snd_pcm_hw_params_any(pcm_handle, params);

    res = c_alsa.snd_pcm_hw_params_set_access(pcm_handle, params, c_alsa.SND_PCM_ACCESS_RW_INTERLEAVED);

    if (res < 0) {
        log.err("Failed to set access type: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    res = c_alsa.snd_pcm_hw_params_set_format(pcm_handle, params, c_alsa.SND_PCM_FORMAT_S16_LE);

    if (res < 0) {
        log.err("Failed to set sample format: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    res = c_alsa.snd_pcm_hw_params_set_channels(pcm_handle, params, opts.channels);

    if (res < 0) {
        log.err("Failed to set channel count of {d}: {s}", .{ opts.channels, c_alsa.snd_strerror(res) });
        return AlsaError.device_init;
    }

    res = c_alsa.snd_pcm_hw_params_set_rate_near(pcm_handle, params, &sample_rate, &dir);

    if (res < 0) {
        log.err("Failed to set sample rate of {d}: {s}", .{ sample_rate, c_alsa.snd_strerror(res) });
        return AlsaError.device_init;
    }

    res = c_alsa.snd_pcm_hw_params(pcm_handle, params);

    if (res < 0) {
        log.err("Failed to set hardware parameters: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    return Device{
        .pcm_handle = pcm_handle,
        .params = params,
        .channels = 2,
        .sample_rate = sample_rate,
        .dir = dir,
        .mode = opts.mode,
        .stream_type = opts.stream_type,
    };
}

pub fn deinit(self: *Device) !void {
    c_alsa.snd_pcm_hw_params_free(self.params);
    const res = c_alsa.snd_pcm_close(self.pcm_handle);

    if (res < 0) {
        log.err("Failed to close PCM: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.device_deinit;
    }
}
