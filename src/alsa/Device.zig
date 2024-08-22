const std = @import("std");
const AlsaError = @import("error.zig").AlsaError;

const alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const log = std.log.scoped(.alsa);
const Device = @This();

pub const StreamType = enum(c_uint) {
    playback = alsa.SND_PCM_STREAM_PLAYBACK,
    capture = alsa.SND_PCM_STREAM_CAPTURE,
};

pub const MODE_NONE: c_int = 0;
//  opens in non-blocking mode: calls to read/write audio data will return immediately
pub const MODE_NONBLOCK: c_int = alsa.SND_PCM_NONBLOCK;
// async for when handling audio I/O asynchronously
pub const MODE_ASYNC: c_int = alsa.SND_PCM_ASYNC;
// prevents automatic resampling when sample rate doesn't match hardware
pub const MODE_NO_RESAMPLE: c_int = alsa.SND_PCM_NO_AUTO_RESAMPLE;
// prevents from automatically ajudisting the number of channel
pub const MODE_NO_AUTOCHANNEL: c_int = alsa.SND_PCM_NO_AUTO_CHANNELS;
// prevents from automatically ajusting the sample format
pub const MODE_NO_AUTOFORMAT: c_int = alsa.SND_PCM_NO_AUTO_FORMAT;

pcm_handle: ?*alsa.snd_pcm_t = null,
params: ?*alsa.snd_pcm_hw_params_t = null,
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
};

pub fn init(opts: DeviceOptions) !Device {
    var pcm_handle: ?*alsa.snd_pcm_t = null;
    var params: ?*alsa.snd_pcm_hw_params_t = null;
    var sample_rate: u32 = opts.sample_rate;
    var dir: i32 = 0;

    var res = alsa.snd_pcm_open(&pcm_handle, "default", @intFromEnum(opts.stream_type), opts.mode);
    if (res < 0) {
        log.err("Failed to open PCM: {s}", .{alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    res = alsa.snd_pcm_hw_params_malloc(&params);

    if (res < 0) {
        log.err("Failed to allocate hardware parameters: {s}", .{alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    _ = alsa.snd_pcm_hw_params_any(pcm_handle, params);

    res = alsa.snd_pcm_hw_params_set_access(pcm_handle, params, alsa.SND_PCM_ACCESS_RW_INTERLEAVED);

    if (res < 0) {
        log.err("Failed to set access type: {s}", .{alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    res = alsa.snd_pcm_hw_params_set_format(pcm_handle, params, alsa.SND_PCM_FORMAT_S16_LE);

    if (res < 0) {
        log.err("Failed to set sample format: {s}", .{alsa.snd_strerror(res)});
        return AlsaError.device_init;
    }

    res = alsa.snd_pcm_hw_params_set_channels(pcm_handle, params, opts.channels);

    if (res < 0) {
        log.err("Failed to set channel count of {d}: {s}", .{ opts.channels, alsa.snd_strerror(res) });
        return AlsaError.device_init;
    }

    res = alsa.snd_pcm_hw_params_set_rate_near(pcm_handle, params, &sample_rate, &dir);

    if (res < 0) {
        log.err("Failed to set sample rate of {d}: {s}", .{ sample_rate, alsa.snd_strerror(res) });
        return AlsaError.device_init;
    }

    res = alsa.snd_pcm_hw_params(pcm_handle, params);

    if (res < 0) {
        log.err("Failed to set hardware parameters: {s}", .{alsa.snd_strerror(res)});
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
    alsa.snd_pcm_hw_params_free(self.params);
    const res = alsa.snd_pcm_close(self.pcm_handle);

    if (res < 0) {
        log.err("Failed to close PCM: {s}", .{alsa.snd_strerror(res)});
        return AlsaError.device_deinit;
    }
}

const Card = struct {
    pub const internal_buffer_len: usize = 1048;

    index: i32,
    id: []u8,
    name: []u8,
    internal_buffer: [internal_buffer_len]u8 = undefined,
    allocator: std.mem.Allocator,

    pub fn init(index: i32, id: []u8, name: []u8) !void {
        const card = Card{
            .index = index,
        };

        const fba = std.heap.FixedBufferAllocator.init(&card.internal_buffer);
        const allocator = fba.allocator();
        card.id = try allocator.alloc(u8, id.len);
        card.name = try allocator.alloc(u8, name.len);

        @memcpy(card.id, id);
        @memcpy(card.name, name);

        card.allocator = allocator;

        return card;
    }
};

pub fn listSystemCards() void {
    var card: c_int = -1;

    while (alsa.snd_card_next(&card) >= 0 and card >= 0) {
        var ctl: ?*alsa.snd_ctl_t = null;
        var card_name: [32]u8 = undefined;

        try std.fmt.bufPrint(&card_name, "hw:{d}", .{card});

        var res = alsa.snd_ctl_open(&ctl, &card_name, 0);

        if (res < 0) {
            log.warn("Failed to open control interface for card {d}: {s}", .{ card, alsa.snd_strerror(res) });
            continue;
        }

        var info: ?*alsa.snd_ctl_card_info_t = null;
        alsa.snd_ctl_card_info_malloc(&info);
        defer alsa.snd_ctl_card_info_free(info);

        res = alsa.snd_ctl_card_info(ctl, info);

        if (res < 0) {
            log.warn("Failed to get card info for card {d}: {s}", .{ card, alsa.snd_strerror(res) });
            continue;
        }

        log.info("Card {d}", .{card});
        log.info("Id: {s}", .{alsa.snd_ctl_card_info_get_id(info)});
        log.info("Name: {s}", .{alsa.snd_ctl_card_info_get_name(info)});

        alsa.snd.ctl.close(ctl);
    }
}
