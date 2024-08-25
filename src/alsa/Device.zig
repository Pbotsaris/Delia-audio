const std = @import("std");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const log = std.log.scoped(.alsa);
const Device = @This();

pub const FormatType = @import("settings.zig").FormatType;
pub const AccessType = @import("settings.zig").AccessType;
pub const BufferSize = @import("settings.zig").BufferSize;
pub const StreamType = @import("settings.zig").StreamType;
pub const Signedness = @import("settings.zig").Signedness;
pub const ByteOrder = @import("settings.zig").ByteOrder;
pub const Strategy = @import("settings.zig").Strategy;
pub const SampleRate = @import("settings.zig").SampleRate;
pub const ChannelCount = @import("settings.zig").ChannelCount;
pub const Mode = @import("settings.zig").Mode;
pub const StartThreshold = @import("settings.zig").StartThreshold;

const Format = struct {
    // the format type as per ALSA definitions
    format_type: FormatType,
    // the signedness of the format: signed or unsigned
    signedness: Signedness,
    // the byte order of the format: little or big endian
    byte_order: ByteOrder,
    // The number of bits per sample: 8, 16, 24, 32 bits. Negative if not applicable
    bit_depth: i32,
    // The number of bytes per sample: 1, 2, 3, 4 bytes. Negative if not applicable
    byte_rate: i32,
    // This is the same as bit_depth but also includes any padding bits. Relevant for formats like S24_3LE that are not packed
    // Negative if not applicable
    physical_width: i32,
    // same as byte_rate but for physical width. Negative if not applicable
    physical_byte_rate: i32,

    pub fn init(fmt: FormatType) Format {
        const int_fmt = @intFromEnum(fmt);
        const is_big_endian: bool = c_alsa.snd_pcm_format_little_endian(int_fmt) == 1;
        const is_signed: bool = c_alsa.snd_pcm_format_signed(int_fmt) == 1;

        const byte_order = if (is_big_endian) ByteOrder.big_endian else ByteOrder.little_endian;
        const sign_type = if (is_signed) Signedness.signed else Signedness.unsigned;

        const bit_depth = c_alsa.snd_pcm_format_width(int_fmt);
        const physical_width = c_alsa.snd_pcm_format_physical_width(int_fmt);

        return .{
            .format_type = fmt,
            .signedness = sign_type,
            .byte_order = byte_order,
            .bit_depth = bit_depth,
            .byte_rate = if (bit_depth >= 0) @divFloor(bit_depth, 8) else -1,
            .physical_width = bit_depth,
            .physical_byte_rate = if (physical_width >= 0) @divFloor(physical_width, 8) else -1,
        };
    }

    pub fn format(self: Format, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("\nFormat\n", .{});
        try writer.print("| signedness:         {s}\n", .{@tagName(self.signedness)});
        try writer.print("| byte_order:         {s}\n", .{@tagName(self.byte_order)});
        try writer.print("| bit_depth:          {d}\n", .{self.bit_depth});
        try writer.print("| byte_rate:          {d}\n", .{self.byte_rate});
        try writer.print("| physical_width:     {d}\n", .{self.physical_width});
        try writer.print("| physical_byte_rate: {d}\n", .{self.physical_byte_rate});
    }
};

// this constant will is the multiplier that will define the size of the hardware buffer size.
pub const NB_PERIODS = 5;
//  hardware_buffer_size = user_defined_buffer_size * NB_PERIODS

// Pointer to the PCM device handle.
pcm_handle: ?*c_alsa.snd_pcm_t = null,
// Pointer to the hardware parameters configuration.
hw_params: ?*c_alsa.snd_pcm_hw_params_t = null,
// Pointer to the software parameters configuration.
sw_params: ?*c_alsa.snd_pcm_sw_params_t = null,
// Mode for opening the audio device (e.g., non-blocking, async).
mode: Mode,
// Indicates whether the device is for playback or capture.
stream_type: StreamType,
// Number of audio channels (e.g., 2 for stereo).
channels: u32,
// Audio device's sample rate in Hz.
sample_rate: u32,
// Direction flag for adjusting the sample rate, typically set by ALSA.
dir: i32,
// Software buffer size in frames. This is the size of the buffer that the audio callback reads/writes.
buffer_size: BufferSize,
// Total size of the hardware audio buffer in frames.
hardware_buffer_size: u32,
// Size of one hardware period in frames.
hardware_period_size: u32,
// Number of periods before ALSA starts reading/writing audio data.
start_thresh: StartThreshold,
// Timeout in milliseconds for ALSA to wait before returning an error during read/write operations.
timeout: u32,
// Defines the transfer method used by the audio callback (e.g., read/write interleaved,  read/write non-interleaved , mmap intereaved).
access_type: AccessType,
// Audio sample format (e.g., 16-bit signed little-endian).
format: Format,
// TODO: Description
strategy: Strategy = Strategy.min_available,

const DeviceOptions = struct {
    sample_rate: SampleRate,
    channels: ChannelCount,
    stream_type: StreamType,
    mode: Mode = Mode.none,
    ident: [:0]const u8 = "default",
    buffer_size: BufferSize = BufferSize.bz_2048,
    start_thresh: StartThreshold = StartThreshold.three_periods,
    timeout: u32 = 1000,
    access_type: AccessType = AccessType.rw_interleaved,
    format: FormatType = FormatType.signed_16bits_little_endian,
    allow_resampling: bool = false,
};

pub fn init(opts: DeviceOptions) !Device {
    var pcm_handle: ?*c_alsa.snd_pcm_t = null;
    var params: ?*c_alsa.snd_pcm_hw_params_t = null;
    var sample_rate: u32 = @intFromEnum(opts.sample_rate);

    // we are configuring the hardware to match the sofware buffer size and optimize latency
    var hardware_period_size: c_alsa.snd_pcm_uframes_t = @intFromEnum(opts.buffer_size);
    var hardware_buffer_size: c_alsa.snd_pcm_uframes_t = hardware_period_size * NB_PERIODS;

    var dir: i32 = 0;

    var err = c_alsa.snd_pcm_open(&pcm_handle, opts.ident.ptr, @intFromEnum(opts.stream_type), @intFromEnum(opts.mode));
    if (err < 0) {
        log.err("Failed to open PCM for StreamType: {s}, Mode: {s}: {s}", .{ @tagName(opts.stream_type), @tagName(opts.mode), c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_malloc(&params);

    if (err < 0) {
        log.err("Failed to allocate hardware parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    _ = c_alsa.snd_pcm_hw_params_any(pcm_handle, params);

    if (opts.allow_resampling) {
        if (c_alsa.snd_pcm_hw_params_set_rate_resample(pcm_handle, params, 1) < 0) {
            log.warn("Failed to set resampling: {s}", .{c_alsa.snd_strerror(err)});
        }
    }

    err = c_alsa.snd_pcm_hw_params_set_access(pcm_handle, params, @intFromEnum(opts.access_type));

    if (err < 0) {
        log.err("Failed to set access type '{s}': {s}", .{ @tagName(opts.access_type), c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_format(pcm_handle, params, @intFromEnum(opts.format));

    if (err < 0) {
        log.err("The format is '{s}' not valid for this hardware.Please check the format options of your hardwave with hardware.formats().", .{@tagName(opts.format)});
        log.err("ALSA error: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_channels(pcm_handle, params, @intFromEnum(opts.channels));

    if (err < 0) {
        log.err("Failed to set channel count of {d}: {s}", .{ @intFromEnum(opts.channels), c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_rate_near(pcm_handle, params, &sample_rate, &dir);
    const desired_sampe_rate = sample_rate;

    if (err < 0) {
        log.err("Failed to set sample rate of {d}: {s}", .{ sample_rate, c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    if (sample_rate != desired_sampe_rate) {
        log.err("Sample rate {d} did not match the requested {d} ", .{ sample_rate, desired_sampe_rate });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_buffer_size_near(pcm_handle, params, &hardware_buffer_size);

    if (err < 0) {
        log.err("Failed to set hardware buffer size {d}: {s}", .{ hardware_period_size, c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_set_period_size_near(pcm_handle, params, &hardware_period_size, &dir);

    if (err < 0) {
        log.err("Failed to set hardware period size {d}: {s}", .{ hardware_period_size, c_alsa.snd_strerror(err) });
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params(pcm_handle, params);

    if (err < 0) {
        log.err("Failed to set hardware parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_get_buffer_size(params, &hardware_buffer_size);

    if (err < 0) {
        log.err("Failed to get hardware buffer size: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    err = c_alsa.snd_pcm_hw_params_get_period_size(params, &hardware_period_size, &dir);

    if (err < 0) {
        log.err("Failed to get hardware period size: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_init;
    }

    return Device{
        .pcm_handle = pcm_handle,
        .hw_params = params,
        .channels = @intFromEnum(opts.channels),
        .sample_rate = sample_rate,
        .dir = dir,
        .mode = opts.mode,
        .stream_type = opts.stream_type,
        .buffer_size = opts.buffer_size,
        .start_thresh = opts.start_thresh,
        .timeout = opts.timeout,
        .access_type = opts.access_type,
        .hardware_buffer_size = @as(u32, @intCast(hardware_buffer_size)),
        .hardware_period_size = @as(u32, @intCast(hardware_period_size)),
        .format = Format.init(opts.format),
    };
}

pub fn prepare(self: *Device, strategy: Strategy) !void {
    var err = c_alsa.snd_pcm_sw_params_malloc(&self.sw_params);

    if (err < 0) {
        log.err("Failed to allocate software parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_prepare;
    }

    err = c_alsa.snd_pcm_sw_params_current(self.pcm_handle, self.sw_params);

    if (err < 0) {
        log.err("Failed to get current software parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_prepare;
    }

    // If we are using period_event strategy, we set the avail_min to the hardware buffer size
    // essentially disabling this mechanism in favor of polling for period events
    const min_size =
        if (strategy == Strategy.period_event) self.hardware_buffer_size else @intFromEnum(self.buffer_size);

    err = c_alsa.snd_pcm_sw_params_set_avail_min(self.pcm_handle, self.sw_params, min_size);

    if (err < 0) {
        log.err("Failed to set minimum available count '{s}': {s}", .{ @tagName(self.buffer_size), c_alsa.snd_strerror(err) });
        return AlsaError.device_prepare;
    }

    err = c_alsa.snd_pcm_sw_params_set_start_threshold(self.pcm_handle, self.sw_params, @intFromEnum(self.start_thresh));

    if (err < 0) {
        log.err("Failed to set start threshold '{s}': {s}", .{ @tagName(self.start_thresh), c_alsa.snd_strerror(err) });
        return AlsaError.device_prepare;
    }

    if (strategy == Strategy.period_event) {
        if (c_alsa.snd_pcm_sw_params_set_period_event(self.pcm_handle, self.sw_params, 1) < 0) {
            log.err("Failed to enable period event: {s}", .{c_alsa.snd_strerror(err)});
            return AlsaError.device_prepare;
        }
    }

    err = c_alsa.snd_pcm_sw_params(self.pcm_handle, self.sw_params);

    if (err < 0) {
        log.err("Failed to set software parameters: {s}", .{c_alsa.snd_strerror(err)});
        return AlsaError.device_prepare;
    }

    err = c_alsa.snd_pcm_prepare(self.pcm_handle);

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
