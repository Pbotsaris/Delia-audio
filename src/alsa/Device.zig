//! The `Device` struct abstracts the initialization and management of an ALSA audio device.
//! It encapsulates all the necessary configurations and states required to set up and operate
//! an audio device for playback or capture operations. This struct allows users to specify
//! various options related to audio format, buffering, access types, and operational modes,
//! providing a flexible interface for interacting with ALSA.
//!
//! The Hardware buffer size and period size are calculated based on the user-defined buffer size
//! for minimizing latency and optimizing performance. This can be further customized by adjusting
//! the NB_PERIODS constant to increase the number of periods per hardware buffer.

// TODO: Create an Alsa Allocator following the same pattern as STD for memory allocation
const std = @import("std");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const log = std.log.scoped(.alsa);
const Device = @This();

pub const Format = @import("Format.zig");
pub const Hardware = @import("Hardware.zig");

pub const Signedness = @import("settings.zig").Signedness;
pub const ByteOrder = @import("settings.zig").ByteOrder;
pub const BufferSize = @import("settings.zig").BufferSize;
pub const FormatType = @import("settings.zig").FormatType;
pub const AccessType = @import("settings.zig").AccessType;
pub const StreamType = @import("settings.zig").StreamType;
pub const Strategy = @import("settings.zig").Strategy;
pub const SampleRate = @import("settings.zig").SampleRate;
pub const ChannelCount = @import("settings.zig").ChannelCount;
pub const Mode = @import("settings.zig").Mode;
pub const StartThreshold = @import("settings.zig").StartThreshold;

// this constant will is the multiplier that will define the size of the hardware buffer size.
//  hardware_buffer_size = user_defined_buffer_size * NB_PERIODS
pub const NB_PERIODS = 5;

/// Pointer to the PCM device handle.
pcm_handle: ?*c_alsa.snd_pcm_t = null,
/// Pointer to the hardware parameters configuration.
hw_params: ?*c_alsa.snd_pcm_hw_params_t = null,
/// Pointer to the software parameters configuration.
sw_params: ?*c_alsa.snd_pcm_sw_params_t = null,
/// Mode for opening the audio device (e.g., non-blocking, async).
mode: Mode,
/// Indicates whether the device is for playback or capture.
stream_type: StreamType,
/// Number of audio channels (e.g., 2 for stereo).
channels: u32,
/// Audio device's sample rate in Hz.
sample_rate: u32,
/// Direction flag for adjusting the sample rate, typically set by ALSA.
dir: i32,
/// Software buffer size in frames. This is the size of the buffer that the audio callback reads/writes.
buffer_size: BufferSize,
/// Total size of the hardware audio buffer in frames.
hardware_buffer_size: u32,
/// Size of one hardware period in frames.
hardware_period_size: u32,
/// Number of periods before ALSA starts reading/writing audio data.
start_thresh: StartThreshold,
/// Timeout in milliseconds for ALSA to wait before returning an error during read/write operations.
timeout: i32,
/// Defines the transfer method used by the audio callback (e.g., read/write interleaved,  read/write non-interleaved , mmap intereaved).
access_type: AccessType,
/// Audio sample format (e.g., 16-bit signed little-endian).
audio_format: Format,
/// TODO: Description
strategy: Strategy = Strategy.min_available,

const DeviceOptions = struct {
    // there is no default values for these fields, user must provide them
    sample_rate: SampleRate,
    channels: ChannelCount,
    stream_type: StreamType,
    audio_format: FormatType,
    ident: [:0]const u8 = "default",
    mode: Mode = Mode.none,
    buffer_size: BufferSize = BufferSize.bz_2048,
    start_thresh: StartThreshold = StartThreshold.three_periods,
    timeout: i32 = -1,
    access_type: AccessType = AccessType.mmap_interleaved,
    allow_resampling: bool = false,
};

const DeviceOptionsFromHardware = struct {
    mode: Mode = Mode.none,
    buffer_size: BufferSize = BufferSize.bz_2048,
    start_thresh: StartThreshold = StartThreshold.three_periods,
    timeout: i32 = -1,
    access_type: AccessType = AccessType.rw_interleaved,
    allow_resampling: bool = true,
};

/// Initializes a `Device` using the provided `Hardware` configuration and additional options.
///
/// This function retrieves the selected audio port from the `Hardware` instance and uses its
/// settings (e.g., sample rate, channel count, format) to configure the `Device`. If specific
/// settings are not available from the hardware, default values are used. The function then
/// calls the `init` function to configure the ALSA hardware parameters.
///
/// # Parameters:
/// - `hardware`: The `Hardware` instance that provides information about the available audio ports.
/// - `inc_opts`: Additional options for configuring the `Device`, such as mode, buffer size,
///   start threshold, timeout, access type, and whether resampling is allowed.
///
/// # Returns:
/// - A `Device` instance configured based on the hardware settings and the provided options.
/// - Returns an error if the hardware or options cannot be used to initialize the device.
///
/// # Errors:
/// - Returns an error if the selected audio port cannot be retrieved or if the device initialization fails.
pub fn fromHardware(hardware: Hardware, inc_opts: DeviceOptionsFromHardware) !Device {
    const port = try hardware.getSelectedAudioPort();

    const opts = DeviceOptions{
        .sample_rate = port.selected_settings.sample_rate orelse SampleRate.sr_44Khz,
        .channels = port.selected_settings.channels orelse ChannelCount.stereo,
        .stream_type = port.stream_type orelse StreamType.playback,
        .audio_format = port.selected_settings.format orelse FormatType.signed_16bits_little_endian,
        .ident = port.identifier,
        .mode = inc_opts.mode,
        .buffer_size = inc_opts.buffer_size,
        .start_thresh = inc_opts.start_thresh,
        .timeout = inc_opts.timeout,
        .access_type = inc_opts.access_type,
        .allow_resampling = inc_opts.allow_resampling,
    };

    return try init(opts);
}

/// Initializes the ALSA device with the provided options and configures the hardware parameters.
///
/// # Parameters:
/// - `opts`: A `DeviceOptions` structure containing various settings for the device, such as sample rate,
///   channels, audio format, buffer size, period size, and more.
///
/// # Returns:
/// - A `Device` instance configured and ready for playback or capture.
/// - Returns an error if the hardware parameters cannot be set or if the device initialization fails.
///
/// # Hardware Configuration:
/// - `sample_rate`: Sets the desired sample rate. If the hardware cannot match the requested rate, an error is returned.
/// - `channels`: Configures the number of audio channels.
/// - `audio_format`: Sets the sample format (e.g., signed 16-bit little-endian).
/// - `buffer_size` and `hardware_buffer_size`: Configures the software and hardware buffer sizes, optimizing for latency.
/// - `hardware_period_size`: Defines the period size, determining the frequency of hardware interrupts.
///
/// # Errors:
/// - Returns an error if the PCM device cannot be opened, if the hardware parameters cannot be set,
///   or if there is a mismatch between the requested and actual sample rate.
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

    err = c_alsa.snd_pcm_hw_params_set_format(pcm_handle, params, @intFromEnum(opts.audio_format));

    if (err < 0) {
        log.err(
            "The format is '{s}' not valid for this hardware. Please check the format options of your hardwave with hardware.formats().",
            .{@tagName(opts.audio_format)},
        );
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
        .audio_format = Format.init(opts.audio_format),
    };
}

/// Prepares the ALSA device for playback or capture using the specified strategy.
///
/// This function configures the software parameters of the ALSA device, including the
/// method by which audio data will be transferred to or from the hardware.
///
/// # Parameters:
///
/// - `strategy`: Specifies the data transfer strategy to be used.
///   - `Strategy.period_event`:
///     - Sets `avail_min` to the hardware buffer size and enables period events. This
///       causes the ALSA hardware to trigger an interrupt after each period is processed,
///       reducing CPU usage.
///   - `Strategy.min_available`:
///     - Sets `avail_min` to the size of the period buffer, meaning the application will
///       handle data transfer when there is enough space in the buffer for a full period.
///
/// # Errors:
///
/// Returns an error if any of the ALSA API calls fail, including memory allocation for
/// software parameters, setting the current software parameters, or preparing the device
/// for playback/capture.
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

        err = c_alsa.snd_pcm_sw_params(self.pcm_handle, self.sw_params);
    }

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

pub fn format(self: Device, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    try writer.print("\nDevice\n", .{});
    try writer.print("  Stream Type:     {s}\n", .{@tagName(self.stream_type)});
    try writer.print("  Access Type:     {s}\n", .{@tagName(self.access_type)});
    try writer.print("  Sample Rate:     {d}hz\n", .{self.sample_rate});
    try writer.print("  Channels:        {d}\n", .{self.channels});
    try writer.print("  Buffer Size:     {d} bytes\n", .{@intFromEnum(self.buffer_size)});
    try writer.print("  HW Buffer Size:  {d} bytes\n", .{self.hardware_buffer_size});
    try writer.print("  Timeout:         {d}ms\n", .{self.timeout});
    try writer.print("  Open Mode:       {s}\n", .{@tagName(self.mode)});
    try writer.print("{s}\n", .{self.audio_format});
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
