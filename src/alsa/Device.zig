const std = @import("std");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const log = std.log.scoped(.alsa);
const Device = @This();

pub const Format = @import("settings.zig").Format;
pub const AccessType = @import("settings.zig").AccessType;
pub const BufferSize = @import("settings.zig").BufferSize;
pub const StreamType = @import("settings.zig").StreamType;
pub const Mode = @import("settings.zig").Mode;

pcm_handle: ?*c_alsa.snd_pcm_t = null,
hw_params: ?*c_alsa.snd_pcm_hw_params_t = null,
sw_params: ?*c_alsa.snd_pcm_sw_params_t = null,
// The mode in which the audio device will be opened
mode: Mode,
// If either this is a playback or capture device
stream_type: StreamType,
// The number of channels in the audio device
channels: u32,
// the sample rate of the audio device
sample_rate: u32, // in Hz
dir: i32,
// the size of the buffer or period in frames(1 frame = 1 sample per channel) that ALSA will interrupt the CPU to deliver new audio data
buffer_size: BufferSize,
// determines how long ALSA will wait in frames before starting read/write
start_thresh: u32,
timeout: u32,
// will essentially determine the transfer method used by the audio callback
access_type: AccessType,

format: Format,

const DeviceOptions = struct {
    sample_rate: u32,
    channels: u32,
    stream_type: StreamType,
    mode: Mode = Mode.none,
    handler_name: [:0]const u8 = "default",
    buffer_size: BufferSize = BufferSize.sr_2048,
    start_thresh: u32 = @intFromEnum(BufferSize.sr_2048) / 2,
    timeout: u32 = 1000,
    access_type: AccessType = AccessType.rw_interleaved,
    format: Format = Format.signed_16bits_little_endian,
};

pub fn init(opts: DeviceOptions) !Device {
    var pcm_handle: ?*c_alsa.snd_pcm_t = null;
    var params: ?*c_alsa.snd_pcm_hw_params_t = null;
    var sample_rate: u32 = opts.sample_rate;
    var dir: i32 = 0;

    var err = c_alsa.snd_pcm_open(&pcm_handle, opts.handler_name.ptr, @intFromEnum(opts.stream_type), @intFromEnum(opts.mode));
    if (err < 0) {
        log.err("Failed to open PCM: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_malloc(&params);

    if (err < 0) {
        log.err("Failed to allocate hardware parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    _ = c_alsa.snd_pcm_hw_params_any(pcm_handle, params);

    err = c_alsa.snd_pcm_hw_params_set_access(pcm_handle, params, @intFromEnum(opts.access_type));

    if (err < 0) {
        log.err("Failed to set access type: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_format(pcm_handle, params, @intFromEnum(opts.format));

    if (err < 0) {
        log.err("Failed to set sample format: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_channels(pcm_handle, params, opts.channels);

    if (err < 0) {
        log.err("Failed to set channel count of {d}: {s}", .{ opts.channels, c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_rate_near(pcm_handle, params, &sample_rate, &dir);

    if (err < 0) {
        log.err("Failed to set sample rate of {d}: {s}", .{ sample_rate, c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params(pcm_handle, params);

    if (err < 0) {
        log.err("Failed to set hardware parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    return Device{
        .pcm_handle = pcm_handle,
        .hw_params = params,
        .channels = opts.channels,
        .sample_rate = sample_rate,
        .dir = dir,
        .mode = opts.mode,
        .stream_type = opts.stream_type,
        .buffer_size = opts.buffer_size,
        .start_thresh = opts.start_thresh,
        .timeout = opts.timeout,
        .access_type = opts.access_type,
        .format = opts.format,
    };
}

pub fn prepare(self: *Device) !void {
    var err = c_alsa.snd_pcm_sw_params_malloc(&self.sw_params);

    if (err < 0) {
        log.err("Failed to allocate software parameters: {s}", .{c_alsa.snd_strerror(err)});
        // TODO: change error
        return AlsaError.device_prepare;
    }

    err = c_alsa.snd_pcm_sw_params_current(self.pcm_handler, self.sw_params);

    if (err < 0) {
        log.err("Failed to get current software parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_prepare;
    }

    // The audio interface will interrupt the CPU at every buffer_size frames to deliver new audio data
    err = c_alsa.snd_pcm_sw_params_set_avail_min(self.pcm_handler, self.sw_params, @intFromEnum(self.buffer_size));

    if (err < 0) {
        log.err("Failed to set minimum available count '{d}': {s}", .{ self.buffer_size, c_alsa.snd_strerror(err) });
        return AlsaError.device_prepare;
    }

    err = c_alsa.snd_pcm_sw_params_set_start_threshold(self.pcm_handler, self.sw_params, self.start_thresh);

    if (err < 0) {
        log.err("Failed to set start threshold '{d}': {s}", .{ self.start_delay, c_alsa.snd_strerror(err) });
        return AlsaError.device_prepare;
    }

    err = c_alsa.snd_pcm_sw_params(self.pcm_handler, self.sw_params);

    if (err < 0) {
        log.err("Failed to set software parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_prepare;
    }

    err = c_alsa.snd_pcm_prepare(self.pcm_handler);

    if (err < 0) {
        log.err("Failed to prepare Audio Interface: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }
}

pub fn deinit(self: *Device) !void {
    c_alsa.snd_pcm_hw_params_free(self.hw_params);
    c_alsa.snd_pcm_sw_params_free(self.sw_params);

    const res = c_alsa.snd_pcm_close(self.pcm_handle);

    if (res < 0) {
        log.err("Failed to close PCM: {s}", .{c_alsa.snd_strerror(res)});
        return AlsaError.device_deinit;
    }
}
