const std = @import("std");

const c_alsa = @cImport({
    @cInclude("asoundlib.h");
});

const settings = @import("settings.zig");
const FormatType = @import("settings.zig").FormatType;
const StreamType = @import("settings.zig").StreamType;
const SampleRate = @import("settings.zig").SampleRate;
const Channels = @import("settings.zig").ChannelCount;

const log = std.log.scoped(.alsa);
const SupportedSettings = @This();

formats: std.ArrayList(FormatType),
sample_rates: std.ArrayList(SampleRate),
channel_counts: std.ArrayList(Channels),

pub fn init(allocator: std.mem.Allocator, hw_identifier: [:0]const u8, stream_type: StreamType) ?SupportedSettings {
    var params: ?*c_alsa.snd_pcm_hw_params_t = null;
    var pcm_handle: ?*c_alsa.snd_pcm_t = null;

    var err = c_alsa.snd_pcm_hw_params_malloc(&params);
    defer c_alsa.snd_pcm_hw_params_free(params);

    if (err < 0) {
        log.err("Could not get supported formats. Malloc Fialed: {s}", .{c_alsa.snd_strerror(err)});
        return null;
    }

    err = c_alsa.snd_pcm_open(&pcm_handle, hw_identifier, @intFromEnum(stream_type), 0);

    defer {
        if (pcm_handle != null and c_alsa.snd_pcm_close(pcm_handle) < 0) {
            log.warn("SupportedFormats: Failed to close PCM for StreamType {s}", .{@tagName(stream_type)});
        }
    }

    if (err < 0) {
        log.err("Could not get supported formats. Failed to open Stream type {s}: {s}", .{ @tagName(stream_type), c_alsa.snd_strerror(err) });
        return null;
    }

    err = c_alsa.snd_pcm_hw_params_any(pcm_handle, params);

    if (err < 0) {
        log.err("Could not get supported formats. Failed init harware params: {s}", .{c_alsa.snd_strerror(err)});
        return null;
    }

    var supported_formats = std.ArrayList(FormatType).init(allocator);
    var supported_sample_rates = std.ArrayList(SampleRate).init(allocator);
    var supported_channels_counts = std.ArrayList(Channels).init(allocator);

    for (settings.formats) |f| {
        if (f < 0) continue; // skip FormatType.unknown
        if (c_alsa.snd_pcm_hw_params_test_format(pcm_handle, params, f) >= 0) {
            supported_formats.append(@enumFromInt(f)) catch {
                log.warn("Could not append format {d}", .{f});
            };
        }
    }

    for (settings.sample_rates) |sr| {
        if (c_alsa.snd_pcm_hw_params_test_rate(pcm_handle, params, sr, 0) >= 0) {
            supported_sample_rates.append(@enumFromInt(sr)) catch {
                log.warn("SupportedSettings: Could not append sample rate settings {d}", .{sr});
            };
        }
    }

    for (settings.channel_counts) |c| {
        if (c_alsa.snd_pcm_hw_params_test_channels(pcm_handle, params, c) >= 0) {
            supported_channels_counts.append(@enumFromInt(c)) catch {
                log.warn("SupportedSettings: Could not append channel settings {d}", .{c});
            };
        }
    }
    return .{
        .formats = supported_formats,
        .sample_rates = supported_sample_rates,
        .channel_counts = supported_channels_counts,
    };
}

pub fn format(self: SupportedSettings, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    try writer.print("  │    │     ├──  Supported Settings: \n", .{});

    try writer.print("  │    │     │     Formats({d}):\n", .{self.formats.items.len});
    for (0.., self.formats.items) |i, f| {
        if (i == 0) {
            try writer.print("  │    │     │    - {s}(default)\n", .{@tagName(f)});
        } else try writer.print("  │    │     │    - {s}\n", .{@tagName(f)});
    }

    try writer.print("  │    │     ├── Sample Rates({d}):\n", .{self.sample_rates.items.len});
    for (0.., self.sample_rates.items) |i, sr| {
        if (i == 0) {
            try writer.print("  │    │     │    - {d}hz(default)\n", .{@intFromEnum(sr)});
        } else try writer.print("  │    │     │    - {d}hz\n", .{@intFromEnum(sr)});
    }

    try writer.print("  │    │     ├── Channel Count({d}):\n", .{self.channel_counts.items.len});
    for (0.., self.channel_counts.items) |i, c| {
        if (i == 0) {
            try writer.print("  │    │     │     - {s}: {d}(default)\n", .{ @tagName(c), @intFromEnum(c) });
        } else try writer.print("  │    │     │     - {s}: {d}\n", .{ @tagName(c), @intFromEnum(c) });
    }

    try writer.print("  │    │     └──\n", .{});
}

pub fn deinit(self: SupportedSettings) void {
    self.formats.deinit();
    self.sample_rates.deinit();
    self.channel_counts.deinit();
}
