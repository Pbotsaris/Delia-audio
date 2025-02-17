pub fn FullDuplexDevice(comptime format_type: FormatType, ContextType: type) type {
    const HalfDuplex = HalfDuplexDevice(format_type, ContextType);
    const T = format_type.ToType();
    
    return struct {
        const Self = @This();
        pub const FORMAT_TYPE = format_type;
        const AudioLoop = FullDuplexAudioLoop(format_type, ContextType);
        pub const AudioCallback = AudioLoop.AudioCallback();

        playback: HalfDuplex,
        capture: HalfDuplex,
        is_linked: bool = false,
        allocator: std.mem.Allocator,

        const DeviceOptions = struct {
            playback_device: [:0]const u8,
            capture_device: [:0]const u8,
            sample_rate: SampleRate = SampleRate.sr_44100,
            channels: ChannelCount = ChannelCount.stereo,
            buffer_size: BufferSize = BufferSize.buf_1024,
            timeout: i32 = -1,
            n_periods: u32 = 5,
            start_thresh: StartThreshold = .fill_one_period,
            allow_resampling: bool = false,
        };

        pub fn init(allocator: std.mem.Allocator, opts: DeviceOptions) !Self {
            // Initialize playback device
            const playback = try HalfDuplex.init(allocator, .{
                .sample_rate = opts.sample_rate,
                .channels = opts.channels,
                .stream_type = StreamType.playback,
                .ident = opts.playback_device,
                .buffer_size = opts.buffer_size,
                .timeout = opts.timeout,
                .n_periods = opts.n_periods,
                .start_thresh = opts.start_thresh,
                .allow_resampling = opts.allow_resampling,
            });

            // Initialize capture device
            const capture = try HalfDuplex.init(allocator, .{
                .sample_rate = opts.sample_rate,
                .channels = opts.channels,
                .stream_type = StreamType.capture,
                .ident = opts.capture_device,
                .buffer_size = opts.buffer_size,
                .timeout = opts.timeout,
                .n_periods = opts.n_periods,
                .start_thresh = opts.start_thresh,
                .allow_resampling = opts.allow_resampling,
            });

            var self = Self{
                .playback = playback,
                .capture = capture,
                .allocator = allocator,
            };

            // Try to link the devices if they're on the same card
            if (std.mem.eql(u8, opts.playback_device, opts.capture_device)) {
                const err = c_alsa.snd_pcm_link(playback.pcm_handle, capture.pcm_handle);
                if (err == 0) {
                    self.is_linked = true;
                } else {
                    log.warn("Could not link playback and capture devices: {s}", .{c_alsa.snd_strerror(err)});
                }
            }

            return self;
        }

        pub fn prepare(self: *Self, strategy: Strategy) !void {
            try self.playback.prepare(strategy);
            try self.capture.prepare(strategy);
        }

        pub fn start(self: *Self, ctx: *ContextType, callback: AudioCallback) !void {
            var audio_loop = AudioLoop.init(self, ctx, callback);
            try audio_loop.start();
        }

        pub fn deinit(self: *Self) void {
            if (self.is_linked) {
                _ = c_alsa.snd_pcm_unlink(self.playback.pcm_handle);
            }
            self.playback.deinit();
            self.capture.deinit();
        }
    };
}

fn FullDuplexAudioLoop(comptime format_type: FormatType, ContextType: type) type {
    const T = format_type.ToType();
    return struct {
        const Self = @This();
        pub fn AudioCallback() type {
            return *const fn (
                ctx: *ContextType,
                capture: *GenericAudioData(format_type),
                playback: *GenericAudioData(format_type)
            ) void;
        }

        // Configuration for xrun recovery retries
        const MAX_RETRY = 5;
        const MILLISECONDS = 1_000_000; // 1ms
        const SLEEP_INCREMENT = 1.2;
        const MAX_ZERO_TRANSFERS = 5;
        const BYTE_ALIGN = 8;

        device: FullDuplexDevice(format_type, ContextType),
        running: bool = false,
        callback: AudioCallback(),
        ctx: *ContextType,

        // For monitoring transfer count and detecting stalls
        playback_zero_transfers: usize = 0,
        capture_zero_transfers: usize = 0,

        pub fn init(
            device: FullDuplexDevice(format_type, ContextType),
            ctx: *ContextType,
            callback: AudioCallback()
        ) Self {
            return .{
                .device = device,
                .callback = callback,
                .ctx = ctx,
            };
        }

        pub fn start(self: *Self) !void {
            self.running = true;

            // If devices are linked, we only need to start capture
            if (self.device.is_linked) {
                try self.device.capture.pcm_start();
            } else {
                try self.device.playback.pcm_start();
                try self.device.capture.pcm_start();
            }

            try self.audioLoop();
        }

        fn audioLoop(self: *Self) !void {
            const buffer_size = @intFromEnum(self.device.playback.buffer_size);
            var playback_areas: ?*c_alsa.snd_pcm_channel_area_t = null;
            var capture_areas: ?*c_alsa.snd_pcm_channel_area_t = null;
            var stopped = true;

            while (self.running) {
                // Check device states and handle errors
                try self.checkDeviceStates(&stopped);

                // Get available frames for both devices
                const playback_avail = c_alsa.snd_pcm_avail_update(self.device.playback.pcm_handle);
                const capture_avail = c_alsa.snd_pcm_avail_update(self.device.capture.pcm_handle);

                if (playback_avail < 0) {
                    try self.xrunRecovery(@intCast(playback_avail));
                    continue;
                }
                if (capture_avail < 0) {
                    try self.xrunRecovery(@intCast(capture_avail));
                    continue;
                }

                // Wait until we have enough frames in both buffers
                if (!self.device.is_linked) {
                    const min_avail = @min(playback_avail, capture_avail);
                    if (min_avail < buffer_size and !stopped) {
                        const err = c_alsa.snd_pcm_wait(self.device.playback.pcm_handle, self.device.playback.timeout);
                        if (err < 0) {
                            try self.xrunRecovery(err);
                            stopped = true;
                            continue;
                        }
                    }
                }

                // Process audio
                var to_transfer = buffer_size;
                var playback_offset: c_ulong = 0;
                var capture_offset: c_ulong = 0;

                while (to_transfer > 0) {
                    // Get capture and playback buffers
                    var frames_to_transfer = to_transfer;
                    const capture_res = try self.beginTransfer(
                        self.device.capture.pcm_handle,
                        &capture_areas,
                        &capture_offset,
                        &frames_to_transfer
                    );

                    const playback_res = try self.beginTransfer(
                        self.device.playback.pcm_handle,
                        &playback_areas,
                        &playback_offset,
                        &frames_to_transfer
                    );

                    // Process the audio data
                    try self.processAudioBuffers(
                        capture_areas.?,
                        playback_areas.?,
                        capture_offset,
                        playback_offset,
                        frames_to_transfer
                    );

                    // Commit the transfers
                    const capture_transferred = try self.commitTransfer(
                        self.device.capture.pcm_handle,
                        capture_offset,
                        frames_to_transfer,
                        &self.capture_zero_transfers
                    );

                    const playback_transferred = try self.commitTransfer(
                        self.device.playback.pcm_handle,
                        playback_offset,
                        frames_to_transfer,
                        &self.playback_zero_transfers
                    );

                    // Update remaining frames to transfer
                    to_transfer -= @min(capture_transferred, playback_transferred);
                }
            }
        }

        fn beginTransfer(
            self: *Self,
            handle: ?*c_alsa.snd_pcm_t,
            areas: *?*c_alsa.snd_pcm_channel_area_t,
            offset: *c_ulong,
            frames: *c_ulong,
        ) !c_int {
            const res = c_alsa.snd_pcm_mmap_begin(handle, areas, offset, frames);
            if (res < 0) {
                try self.xrunRecovery(res);
                return error.TransferError;
            }
            return res;
        }

        fn processAudioBuffers(
            self: *Self,
            capture_areas: *c_alsa.snd_pcm_channel_area_t,
            playback_areas: *c_alsa.snd_pcm_channel_area_t,
            capture_offset: c_ulong,
            playback_offset: c_ulong,
            frames: c_ulong,
        ) !void {
            try self.verifyAlignment(capture_areas);
            try self.verifyAlignment(playback_areas);

            // Set up capture buffer
            const capture_step = @divFloor(capture_areas.step, 8);
            const capture_start = (@divFloor(capture_areas.first, 8)) + (capture_offset * capture_step);
            const capture_buffer = @as([*]u8, @ptrCast(capture_areas.addr))[capture_start .. capture_start + frames * capture_step];

            // Set up playback buffer
            const playback_step = @divFloor(playback_areas.step, 8);
            const playback_start = (@divFloor(playback_areas.first, 8)) + (playback_offset * playback_step);
            const playback_buffer = @as([*]u8, @ptrCast(playback_areas.addr))[playback_start .. playback_start + frames * playback_step];

            // Create audio data wrappers
            var capture_data = GenericAudioData(format_type).init(
                capture_buffer,
                self.device.capture.channels,
                self.device.capture.sample_rate,
                self.device.capture.audio_format,
            );

            var playback_data = GenericAudioData(format_type).init(
                playback_buffer,
                self.device.playback.channels,
                self.device.playback.sample_rate,
                self.device.playback.audio_format,
            );

            // Call user callback with both buffers
            self.callback(self.ctx, &capture_data, &playback_data);
        }

        fn commitTransfer(
            self: *Self,
            handle: ?*c_alsa.snd_pcm_t,
            offset: c_ulong,
            frames: c_ulong,
            zero_transfers: *usize,
        ) !c_int {
            const transferred = c_alsa.snd_pcm_mmap_commit(handle, offset, frames);
            if (transferred < 0) {
                try self.xrunRecovery(@intCast(transferred));
                return error.TransferError;
            }

            if (transferred == 0) {
                zero_transfers.* += 1;
            } else {
                zero_transfers.* = 0;
            }

            if (zero_transfers.* >= MAX_ZERO_TRANSFERS) {
                log.err("Too many consecutive zero transfers", .{});
                return error.XrunError;
            }

            return @intCast(transferred);
        }

        fn checkDeviceStates(self: *Self, stopped: *bool) !void {
            // Check playback state
            const playback_state = c_alsa.snd_pcm_state(self.device.playback.pcm_handle);
            try self.handleDeviceState(playback_state, stopped, "playback");

            // If devices aren't linked, check capture state separately
            if (!self.device.is_linked) {
                const capture_state = c_alsa.snd_pcm_state(self.device.capture.pcm_handle);
                try self.handleDeviceState(capture_state, stopped, "capture");
            }
        }

        fn handleDeviceState(self: *Self, state: c_uint, stopped: *bool, device_name: []const u8) !void {
            switch (state) {
                c_alsa.SND_PCM_STATE_XRUN => {
                    try self.xrunRecovery(-c_alsa.EPIPE);
                    stopped.* = true;
                },
                c_alsa.SND_PCM_STATE_SUSPENDED => {
                    try self.xrunRecovery(-c_alsa.ESTRPIPE);
                },
                else => {
                    if (state < 0) {
                        log.err("Unexpected {s} state error: {s}", .{device_name, c_alsa.snd_strerror(state)});
                        return error.UnexpectedState;
                    }
                },
            }
        }

        fn xrunRecovery(self: *Self, err: c_int) !void {
            // Handle recovery for both devices
            try self.recoverDevice(self.device.playback.pcm_handle, err, "playback");
            if (!self.device.is_linked) {
                try self.recoverDevice(self.device.capture.pcm_handle, err, "capture");
            }
        }

        fn recoverDevice(self: *Self, handle: ?*c_alsa.snd_pcm_t, err: c_int, device_name: []const u8) !void {
            const recovery_err = if (err == -c_alsa.EPIPE) error.Xrun else error.Suspended;

            switch (recovery_err) {
                error.Xrun => {
                    log.warn("{s} device xrun detected", .{device_name});

                    const res = c_alsa.snd_pcm_prepare(handle);
                    if (res < 0) {
                        log.err("Failed to recover {s} device from xrun: {s}", .{
                            device_name,
                            c_alsa.snd_strerror(res),
                        });
                        return error.XrunRecoveryFailed;
                    }
                },
                error.Suspended => {
                    log.warn("{s} device suspended", .{device_name});
                    
                    var res = c_alsa.snd_pcm_resume(handle);
                    var sleep: u64 = 10 * MILLISECONDS;
                    var retries: i32 = MAX_RETRY;

                    // Try to resume the suspended device
                    while (res == -c_alsa.EAGAIN) {
                        log.debug("Trying to resume {s} device. Retry: {d}", .{
                            device_name,
                            MAX_RETRY - retries,
                        });

                        if (retries == 0) {
                            log.err("Timeout while trying to resume {s} device after {d} retries", .{
                                device_name,
                                MAX_RETRY,
                            });
                            return error.ResumeTimeout;
                        }

                        std.time.sleep(sleep);
                        sleep = @intFromFloat(@as(f32, @floatFromInt(sleep)) * SLEEP_INCREMENT);
                        retries -= 1;
                        res = c_alsa.snd_pcm_resume(handle);
                    }

                    // If resume failed, try to prepare the device
                    if (res < 0) {
                        log.warn("Could not resume {s} device, attempting prepare", .{device_name});
                        res = c_alsa.snd_pcm_prepare(handle);
                        if (res < 0) {
                            log.err("Failed to prepare {s} device after suspend: {s}", .{
                                device_name,
                                c_alsa.snd_strerror(res),
                            });
                            return error.SuspendRecoveryFailed;
                        }
                    }
                },
            }

            // Restart the device after recovery
            const start_res = c_alsa.snd_pcm_start(handle);
            if (start_res < 0) {
                log.err("Failed to restart {s} device after recovery: {s}", .{
                    device_name,
                    c_alsa.snd_strerror(start_res),
                });
                return error.RestartFailed;
            }
        }

        inline fn verifyAlignment(self: Self, area: *c_alsa.snd_pcm_channel_area_t) !void {
            // Verify first offset is byte-aligned
            if (area.first % BYTE_ALIGN != 0) {
                log.err("Area.first not byte({d}) aligned. area.first == {d}", .{
                    BYTE_ALIGN,
                    area.first,
                });
                return error.AudioBufferNonAlignment;
            }

            const bit_depth: c_uint = @intCast(self.device.playback.audio_format.bit_depth);
            
            // Verify step aligns with bit depth
            if (area.step % bit_depth != 0) {
                log.err(
                    "Area.step is non-aligned with audio_format.bit_depth. " ++
                    "area.step == {d} bits && audio_format.bit_depth == {d} bits",
                    .{ area.step, bit_depth },
                );
                return error.AudioBufferNonAlignment;
            }

            const n_channels: c_uint = @intCast(self.device.playback.channels);

            // Verify step matches total channel width
            if (area.step != (n_channels * bit_depth)) {
                log.err(
                    "Area.step is not equal to audio_format.bit_depth * Device.n_channels. " ++
                    "area.step == {d} bits && audio_format.bit_depth({d}) * " ++
                    "Device.n_channels({d}) == {d} bits",
                    .{
                        area.step,
                        bit_depth,
                        n_channels,
                        bit_depth * n_channels,
                    },
                );
                return error.AudioBufferNonAlignment;
            }
        }
    };
