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

const c_alsa = @cImport({
    @cInclude("alsa_wrapper.h");
});

const log = std.log.scoped(.alsa);

pub const Hardware = @import("Hardware.zig");
pub const Format = @import("format.zig").Format;
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
const GenericAudioData = @import("audio_data.zig").GenericAudioData;

const DeviceOptions = struct {
    sample_rate: SampleRate = SampleRate.sr_44k100hz,
    channels: ChannelCount = ChannelCount.stereo,
    stream_type: StreamType = StreamType.playback,
    ident: [:0]const u8 = "default",
    buffer_size: BufferSize = BufferSize.bz_2048,
    start_thresh: StartThreshold = StartThreshold.three_periods,
    timeout: i32 = -1,
    // not exposed to the user for now
    // access_type: AccessType = AccessType.mmap_interleaved,
    // mode: Mode = Mode.none,
    allow_resampling: bool = false,
};

pub const DeviceHardwareError = error{
    open_stream,
    alsa_allocation,
    access_type,
    audio_format,
    channel_count,
    sample_rate,
    buffer_size,
    hardware_params,
};

pub const DeviceSoftwareError = error{
    software_params,
    alsa_allocation,
    set_avail_min,
    set_start_threshold,
    set_period_event,
    prepare,
};

pub const AudioLoopError = error{
    start,
    xrun,
    suspended,
    unexpected,
    timeout,
    unsupported,
    audio_buffer_nonalignment,
};

pub fn GenericDevice(comptime format_type: FormatType) type {
    const T = format_type.ToType();

    return struct {
        pub fn AudioDataType() type {
            return *GenericAudioData(format_type);
        }

        pub fn maxFormatSize() usize {
            return Format(T).maxSize();
        }

        const Self = @This();
        // this constant will is the multiplier that will define the size of the hardware buffer size.
        //  hardware_buffer_size = user_defined_buffer_size * NB_PERIODS
        pub const NB_PERIODS = 5;

        // defined at compile time for this device type
        pub const FORMAT_TYPE = format_type;

        const AudioLoop = GenericAudioLoop(format_type);

        /// Pointer to the PCM device handle.
        pcm_handle: ?*c_alsa.snd_pcm_t = null,
        /// Pointer to the hardware parameters configuration.
        hw_params: ?*c_alsa.snd_pcm_hw_params_t = null,
        /// Pointer to the software parameters configuration.
        sw_params: ?*c_alsa.snd_pcm_sw_params_t = null,
        /// Mode for opening the audio device (e.g., non-blocking, async).
        /// Currently no mode is supported.
        mode: Mode = Mode.none,
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
        /// Currently only mmap interleaved is supported.
        access_type: AccessType = AccessType.mmap_interleaved,
        /// Audio sample format (e.g., 16-bit signed little-endian).
        audio_format: Format(T),
        /// TODO: Description
        strategy: Strategy = Strategy.min_available,

        //const DeviceOptionsFromHardware = struct {
        //    mode: Mode = Mode.none,
        //    buffer_size: BufferSize = BufferSize.bz_2048,
        //    start_thresh: StartThreshold = StartThreshold.three_periods,
        //    timeout: i32 = -1,
        //    access_type: AccessType = AccessType.mmap_interleaved,
        //    allow_resampling: bool = true,
        //};
        //
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
        //pub fn fromHardware(hardware: Hardware, inc_opts: DeviceOptionsFromHardware) !Self {
        //    const port = try hardware.getSelectedAudioPort();
        //
        //    const opts = DeviceOptions{
        //        .sample_rate = port.selected_settings.sample_rate orelse SampleRate.sr_44k100hz,
        //        .channels = port.selected_settings.channels orelse ChannelCount.stereo,
        //        .stream_type = port.stream_type orelse StreamType.playback,
        //        .audio_format = port.selected_settings.format orelse FormatType.signed_16bits_little_endian,
        //        .ident = port.identifier,
        //        .buffer_size = inc_opts.buffer_size,
        //        .start_thresh = inc_opts.start_thresh,
        //        .timeout = inc_opts.timeout,
        //        .allow_resampling = inc_opts.allow_resampling,
        //    };
        //
        //    return try init(opts);
        //}

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
        pub fn init(opts: DeviceOptions) DeviceHardwareError!Self {
            var pcm_handle: ?*c_alsa.snd_pcm_t = null;
            var params: ?*c_alsa.snd_pcm_hw_params_t = null;
            var sample_rate: u32 = @intFromEnum(opts.sample_rate);

            // we are configuring the hardware to match the software buffer size and optimize latency
            var hardware_period_size: c_ulong = @intFromEnum(opts.buffer_size);
            var hardware_buffer_size: c_ulong = hardware_period_size * NB_PERIODS;

            var dir: i32 = 0;

            // always mode none for now
            var err = c_alsa.snd_pcm_open(&pcm_handle, opts.ident.ptr, @intFromEnum(opts.stream_type), @intFromEnum(Mode.none));
            if (err < 0) {
                log.warn("Failed to open PCM for ident '{s}': '{s}'. Attempting default...", .{ opts.ident, c_alsa.snd_strerror(err) });

                err = c_alsa.snd_pcm_open(&pcm_handle, "default", @intFromEnum(opts.stream_type), @intFromEnum(Mode.none));

                if (err < 0) {
                    log.err("Failed to open PCM for ident 'default': '{s}'", .{c_alsa.snd_strerror(err)});
                    return DeviceHardwareError.open_stream;
                }

                log.info("Successfully opened PCM for ident 'default'", .{});
            }

            errdefer {
                const e = c_alsa.snd_pcm_close(pcm_handle);
                _ = e;
            }

            err = c_alsa.snd_pcm_hw_params_malloc(&params);

            if (err < 0) {
                log.err("Failed to allocate hardware parameters: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceHardwareError.alsa_allocation;
            }

            errdefer c_alsa.snd_pcm_hw_params_free(params);

            _ = c_alsa.snd_pcm_hw_params_any(pcm_handle, params);

            if (opts.allow_resampling) {
                if (c_alsa.snd_pcm_hw_params_set_rate_resample(pcm_handle, params, 1) < 0) {
                    log.warn("Failed to set resampling: {s}", .{c_alsa.snd_strerror(err)});
                }
            }

            // always set mmap interleaved access type for now
            err = c_alsa.snd_pcm_hw_params_set_access(pcm_handle, params, @intFromEnum(AccessType.mmap_interleaved));

            if (err < 0) {
                log.err("Failed to set access type '{s}': {s}", .{ @tagName(AccessType.mmap_interleaved), c_alsa.snd_strerror(err) });
                return DeviceHardwareError.access_type;
            }

            err = c_alsa.snd_pcm_hw_params_set_format(pcm_handle, params, @intFromEnum(FORMAT_TYPE));

            if (err < 0) {
                log.err(
                    "The format is '{s}' not valid for this hardware. Please check the format options of your hardwave with hardware.formats().",
                    .{@tagName(FORMAT_TYPE)},
                );
                log.err("ALSA error: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceHardwareError.audio_format;
            }

            err = c_alsa.snd_pcm_hw_params_set_channels(pcm_handle, params, @intFromEnum(opts.channels));

            if (err < 0) {
                log.err("Failed to set channel count of {d}: {s}", .{ @intFromEnum(opts.channels), c_alsa.snd_strerror(err) });
                return DeviceHardwareError.channel_count;
            }

            err = c_alsa.snd_pcm_hw_params_set_rate_near(pcm_handle, params, &sample_rate, &dir);
            const desired_sampe_rate = sample_rate;

            if (err < 0) {
                log.err("Failed to set sample rate of {d}: {s}", .{ sample_rate, c_alsa.snd_strerror(err) });
                return DeviceHardwareError.sample_rate;
            }

            if (sample_rate != desired_sampe_rate) {
                log.err("Sample rate {d} did not match the requested {d} ", .{ sample_rate, desired_sampe_rate });
                return DeviceHardwareError.sample_rate;
            }

            err = c_alsa.snd_pcm_hw_params_set_buffer_size_near(pcm_handle, params, &hardware_buffer_size);

            if (err < 0) {
                log.err("Failed to set hardware buffer size {d}: {s}", .{ hardware_period_size, c_alsa.snd_strerror(err) });
                return DeviceHardwareError.buffer_size;
            }

            err = c_alsa.snd_pcm_hw_params_set_period_size_near(pcm_handle, params, &hardware_period_size, &dir);

            if (err < 0) {
                log.err("Failed to set hardware period size {d}: {s}", .{ hardware_period_size, c_alsa.snd_strerror(err) });
                return DeviceHardwareError.buffer_size;
            }

            err = c_alsa.snd_pcm_hw_params(pcm_handle, params);

            if (err < 0) {
                log.err("Failed to set hardware parameters: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceHardwareError.hardware_params;
            }

            err = c_alsa.snd_pcm_hw_params_get_buffer_size(params, &hardware_buffer_size);

            if (err < 0) {
                log.err("Failed to get hardware buffer size: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceHardwareError.buffer_size;
            }

            err = c_alsa.snd_pcm_hw_params_get_period_size(params, &hardware_period_size, &dir);

            if (err < 0) {
                log.err("Failed to get hardware period size: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceHardwareError.buffer_size;
            }

            return Self{
                .pcm_handle = pcm_handle,
                .hw_params = params,
                .channels = @intFromEnum(opts.channels),
                .sample_rate = sample_rate,
                .dir = dir,
                .stream_type = opts.stream_type,
                .buffer_size = opts.buffer_size,
                .start_thresh = opts.start_thresh,
                .timeout = opts.timeout,
                .hardware_buffer_size = @as(u32, @intCast(hardware_buffer_size)),
                .hardware_period_size = @as(u32, @intCast(hardware_period_size)),
                .audio_format = Format(T).init(FORMAT_TYPE),
            };
        }

        ///
        /// Prepares the ALSA device for playback or capture using the specified strategy.
        /// This function configures the software parameters of the ALSA device, including the
        /// method by which audio data will be transferred to or from the hardware.
        ///
        /// # Parameters:
        ///
        /// - `strategy`: Specifies the data transfer strategy to be used.
        ///   - `Strategy.period_event`:
        ///      # TODO
        ///   - `Strategy.min_available`:
        ///     - Sets `avail_min` to the size of the period buffer, meaning the application will
        ///       handle data transfer when there is enough space in the buffer for a full period.
        ///
        /// # Errors:
        ///
        /// Returns an error if any of the ALSA API calls fail, including memory allocation for
        /// software parameters, setting the current software parameters, or preparing the device
        /// for playback/capture.
        pub fn prepare(self: *Self, strategy: Strategy) DeviceSoftwareError!void {
            var err = c_alsa.snd_pcm_sw_params_malloc(&self.sw_params);

            if (err < 0) {
                log.err("Failed to allocate software parameters: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceSoftwareError.alsa_allocation;
            }

            err = c_alsa.snd_pcm_sw_params_current(self.pcm_handle, self.sw_params);

            if (err < 0) {
                log.err("Failed to get current software parameters: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceSoftwareError.software_params;
            }

            // If we are using period_event strategy, we set the avail_min to the hardware buffer size
            // essentially disabling this mechanism in favor of polling for period events
            const min_size =
                if (strategy == Strategy.period_event) self.hardware_buffer_size else @intFromEnum(self.buffer_size);

            err = c_alsa.snd_pcm_sw_params_set_avail_min(self.pcm_handle, self.sw_params, min_size);

            if (err < 0) {
                log.err("Failed to set minimum available count '{s}': {s}", .{ @tagName(self.buffer_size), c_alsa.snd_strerror(err) });
                return DeviceSoftwareError.set_avail_min;
            }

            err = c_alsa.snd_pcm_sw_params_set_start_threshold(self.pcm_handle, self.sw_params, @intFromEnum(self.start_thresh));

            if (err < 0) {
                log.err("Failed to set start threshold '{s}': {s}", .{ @tagName(self.start_thresh), c_alsa.snd_strerror(err) });
                return DeviceSoftwareError.set_start_threshold;
            }

            if (strategy == Strategy.period_event) {
                if (c_alsa.snd_pcm_sw_params_set_period_event(self.pcm_handle, self.sw_params, 1) < 0) {
                    log.err("Failed to enable period event: {s}", .{c_alsa.snd_strerror(err)});
                    return DeviceSoftwareError.set_period_event;
                }

                err = c_alsa.snd_pcm_sw_params(self.pcm_handle, self.sw_params);
            }

            if (err < 0) {
                log.err("Failed to set software parameters: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceSoftwareError.software_params;
            }

            err = c_alsa.snd_pcm_prepare(self.pcm_handle);

            if (err < 0) {
                log.err("Failed to prepare Audio Interface: {s}", .{c_alsa.snd_strerror(err)});
                return DeviceSoftwareError.prepare;
            }
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
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

        pub fn deinit(self: *Self) !void {
            c_alsa.snd_pcm_hw_params_free(self.hw_params);
            c_alsa.snd_pcm_sw_params_free(self.sw_params);

            const res = c_alsa.snd_pcm_close(self.pcm_handle);

            if (res < 0) {
                log.err("Failed to close PCM: {s}", .{c_alsa.snd_strerror(res)});
                return DeviceHardwareError.alsa_allocation;
            }
        }

        pub fn start(self: Self, callback: AudioLoop.AudioCallback()) !void {
            var audio_loop = AudioLoop.init(self, callback);

            try audio_loop.start();
        }
    };
}

// Audio Loop Implementation

fn GenericAudioLoop(comptime format_type: FormatType) type {
    return struct {
        const Self = @This();

        pub fn AudioCallback() type {
            return *const fn (*GenericAudioData(format_type)) void;
        }

        // configuration for xrun recovery retries
        const MAX_RETRY = 5;
        const MILLISECONDS = 1_000_000; // 1ms
        const SLEEP_INCREMENT = 1.2;
        //--

        // if we have 5 consecutive zero transfers we will consider it an xrun
        const MAX_ZERO_TRANSFERS = 5;
        const BYTE_ALIGN = 8;

        device: GenericDevice(format_type),
        running: bool = false,
        callback: AudioCallback(),

        pub fn init(device: GenericDevice(format_type), callback: AudioCallback()) Self {
            return .{
                .device = device,
                .callback = callback,
            };
        }

        pub fn start(self: *Self) AudioLoopError!void {
            self.running = true;

            switch (self.device.access_type) {
                // this is the only access type currently supported at this point
                AccessType.mmap_interleaved => try self.directWrite(),
                else => {
                    log.err("Unsupported access type: {s}", .{@tagName(self.device.access_type)});
                    return AudioLoopError.unsupported;
                },
            }
        }

        fn directWrite(self: *Self) !void {
            const buffer_size: c_ulong = @intFromEnum(self.device.buffer_size);
            var maybe_areas: ?*c_alsa.snd_pcm_channel_area_t = null;
            var stopped: bool = true;
            var zero_transfers: usize = 0;

            while (self.running) {
                const state: c_uint = c_alsa.snd_pcm_state(self.device.pcm_handle);

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
                            return AudioLoopError.unexpected;
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
                        log.err("Failed to start pcm: {s}", .{c_alsa.snd_strerror(err)});
                        return AudioLoopError.start;
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
                var offset: c_ulong = 0;

                while (to_transfer > 0) {
                    // we request for a transfer_size frames from begin but it may return less
                    var expected_to_transfer = to_transfer;
                    const res = c_alsa.snd_pcm_mmap_begin(self.device.pcm_handle, &maybe_areas, &offset, &expected_to_transfer);

                    if (res < 0) {
                        try self.xrunRecovery(res);
                        stopped = true;
                    }

                    const areas = maybe_areas orelse return AudioLoopError.unexpected;
                    const addr = areas.addr orelse return AudioLoopError.unexpected;

                    try self.verifyAlignment(areas);

                    const step: c_ulong = @divFloor(areas.step, 8);
                    const buf_start: c_ulong = (@divFloor(areas.first, 8)) + (offset * step);

                    const buffer: []u8 = @as([*]u8, @ptrCast(addr))[buf_start .. buf_start + expected_to_transfer * step];

                    var audio_data =
                        GenericAudioData(format_type)
                        .init(
                        buffer,
                        self.device.channels,
                        self.device.sample_rate,
                        self.device.audio_format,
                    );

                    self.callback(&audio_data);

                    const frames_actually_transfered =
                        c_alsa.snd_pcm_mmap_commit(self.device.pcm_handle, offset, expected_to_transfer);

                    log.debug("Transferred {d} frames", .{frames_actually_transfered});

                    if (frames_actually_transfered < 0) {
                        try self.xrunRecovery(@intCast(frames_actually_transfered));
                    } else if (frames_actually_transfered != expected_to_transfer) try self.xrunRecovery(-c_alsa.EPIPE);

                    if (frames_actually_transfered == 0) zero_transfers += 1 else zero_transfers = 0;

                    if (zero_transfers >= MAX_ZERO_TRANSFERS) {
                        log.err("Too many consecutive zero transfers. Stopping device.", .{});
                        stopped = true;
                        return AudioLoopError.xrun;
                    }

                    to_transfer -= @as(c_ulong, @intCast(frames_actually_transfered));
                }
            }
        }

        fn xrunRecovery(self: *Self, c_err: c_int) AudioLoopError!void {
            const err = if (c_err == -c_alsa.EPIPE) AudioLoopError.xrun else AudioLoopError.suspended;

            const needs_prepare = switch (err) {
                AudioLoopError.xrun => true,

                AudioLoopError.suspended => blk: {
                    var res = c_alsa.snd_pcm_resume(self.device.pcm_handle);
                    var sleep: u64 = 10 * MILLISECONDS; // 10ms
                    var retries: i32 = MAX_RETRY;

                    while (res == -c_alsa.EAGAIN) {
                        log.debug("Trying to resume device. Retry: {d}", .{MAX_RETRY - retries});

                        if (retries == 0) {
                            log.err("Timeout while trying to resume device after {d} retries.", .{MAX_RETRY});
                            return AudioLoopError.timeout;
                        }

                        std.time.sleep(sleep);

                        sleep = @intFromFloat(@as(f32, @floatFromInt(sleep)) * SLEEP_INCREMENT);
                        retries -= 1;
                        res = c_alsa.snd_pcm_resume(self.device.pcm_handle);
                    }

                    if (res < 0) break :blk true;
                    break :blk false;
                },

                else => {
                    log.err("Unexpected error: {s}", .{c_alsa.snd_strerror(c_err)});
                    return AudioLoopError.unexpected;
                },
            };

            if (!needs_prepare) return;

            const res = c_alsa.snd_pcm_prepare(self.device.pcm_handle);

            if (res < 0) {
                log.err("Failed to recover from xrun: {s}", .{c_alsa.snd_strerror(res)});
                return AudioLoopError.xrun;
            }
        }

        inline fn verifyAlignment(self: Self, area: *c_alsa.snd_pcm_channel_area_t) !void {
            if (area.first % BYTE_ALIGN != 0) {
                log.err("Area.first not byte(8) aligned. area.first == {d}", .{area.first});
                return AudioLoopError.audio_buffer_nonalignment;
            }

            const bit_depth: c_uint = @intCast(self.device.audio_format.bit_depth);
            const physical_byte_rate: c_uint = @intCast(self.device.audio_format.physical_byte_rate);

            if (area.step % bit_depth != 0) {
                log.err("Area.step is non-aligned with audio_format.bit_depth. area.step == {d} bits && audio_format.bit_depth == {d} bits", .{ area.step, bit_depth });
                return AudioLoopError.audio_buffer_nonalignment;
            }

            if (area.step != (physical_byte_rate * bit_depth)) {
                log.err("Area.step is not equal to audio_format.physical_byte_rate. area.step == {d} bits && audio_format.physical_byte_rate == {d} bits", .{ area.step, physical_byte_rate * bit_depth });
                return AudioLoopError.audio_buffer_nonalignment;
            }
        }
    };
}
