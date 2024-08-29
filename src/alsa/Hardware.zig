const std = @import("std");
const log = std.log.scoped(.alsa);
pub const Device = @import("Device.zig");
pub const AudioCard = @import("AudioCard.zig");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

/// `Hardware` manages ALSA audio cards and ports on the system.
/// It handles the initialization, selection, and configuration of audio cards
/// and ports. This struct interacts with the ALSA API to gather and manage
/// information about available audio cards and their capabilities.
///
/// The `Hardware` struct should be initialized once during the application
/// lifecycle and should be deinitialized when no longer needed to free up
/// resources.
const Hardware = @This();

/// A list of audio cards detected on the system.
cards: std.ArrayList(AudioCard),
/// Index of the currently selected audio card.
selected_card: usize = 0,
/// Index of the currently selected audio port on the selected card.
selected_port: usize = 0,
/// The type of audio stream currently selected (playback or capture).
selected_stream_type: Device.StreamType = Device.StreamType.playback,
/// The total number of audio cards detected on the system.
card_count: usize = 0,

allocator: std.mem.Allocator,

/// Initializes the `Hardware` struct, gathering information about the
/// available audio cards on the system.
///
/// - `allocator`: The memory allocator to be used for dynamic allocations.
/// - Returns: An initialized `Hardware` struct.
/// - Errors: Can return errors related to ALSA operations or memory allocations.
pub fn init(allocator: std.mem.Allocator) !Hardware {
    var alsa = Hardware{ .cards = std.ArrayList(AudioCard).init(allocator), .allocator = allocator };
    try loadSystemCards(&alsa);
    return alsa;
}

pub fn deinit(self: *Hardware) void {
    for (self.cards.items) |*card| {
        card.*.deinit();
    }

    self.cards.deinit();
}
/// Retrieves an `AudioCard` by its index in the list of detected cards.
///
/// - `at`: The index of the audio card.
/// - Returns: The `AudioCard` at the specified index.
/// - Errors: Returns an error if the index is out of bounds.
pub fn getAudioCardAt(self: Hardware, at: usize) !AudioCard {
    if (at >= self.cards.items.len) {
        return AlsaError.card_out_of_bounds;
    }

    return self.cards.items[at];
}

/// Retrieves an `AudioCard` by its identifier.
///
/// - `ident`: The identifier string of the audio card.
/// - Returns: The `AudioCard` with the specified identifier.
/// - Errors: Returns an error if the identifier is invalid or if no matching card is found.
pub fn getAudioCardByIdent(self: Hardware, ident: []const u8) !AudioCard {
    try validateIdentifier(ident);

    for (self.cards.items) |card| {
        if (std.mem.eql(u8, card.details.identifier, ident)) {
            return card;
        }
    }

    return AlsaError.card_not_found;
}

/// Selects an audio card by its index.
///
/// - `at`: The index of the audio card to select.
/// - Errors: Returns an error if the index is out of bounds.
pub fn selectAudioCardAt(self: *Hardware, at: usize) !void {
    if (at >= self.cards.items.len) {
        return AlsaError.card_out_of_bounds;
    }

    self.selected_card = at;
}

/// Selects an audio card by its identifier(e.g. `hw:0`).
///
/// - `ident`: The identifier string of the audio card to select.
/// - Errors: Returns an error if the identifier is invalid or if no matching card is found.
pub fn selectAudioCardByIdent(self: *Hardware, ident: []const u8) !void {
    try validateIdentifier(ident);

    for (0.., self.cards.items) |i, card| {
        if (std.mem.eql(u8, card.details.identifier, ident)) {
            self.selected_card = i;
            return;
        }
    }

    return AlsaError.card_not_found;
}

/// Selects an audio port on the selected audio card by its index.
///
/// - `stream_type`: The type of stream (playback or capture).
/// - `at`: The index of the audio port to select.
/// - Errors: Returns an error if the index is out of bounds or if no cards are available.
pub fn selectAudioPortAt(self: *Hardware, stream_type: Device.StreamType, at: usize) !void {
    try errWhenEmpty(self.cards.items.len);

    const selected_card = self.cards.items[self.selected_card];

    const ports = switch (stream_type) {
        Device.StreamType.capture => selected_card.capture_ports,
        Device.StreamType.playback => selected_card.playback_ports,
    };

    if (at >= ports.len) {
        return switch (stream_type) {
            Device.StreamType.capture => AlsaError.capture_port_out_of_bounds,
            Device.StreamType.playback => AlsaError.playback_port_out_of_bounds,
        };
    }

    self.selected_port = at;
    self.selected_stream_type = stream_type;
}

/// Selects an audio port on the selected audio card by its identifier (e.g. `hw:0`).
///
/// - `stream_type`: The type of stream (playback or capture).
/// - `ident`: The identifier string of the audio port to select.
/// - Errors: Returns an error if the identifier is invalid, if no cards are available, or if no matching port is found.
pub fn selectAudioPortByIdent(self: *Hardware, stream_type: Device.StreamType, ident: []const u8) !void {
    try validateIdentifier(ident);
    try errWhenEmpty(self.cards.items.len);

    const selected_card = self.cards.items[self.selected_card];
    self.selected_port = try selected_card.getIndexOf(stream_type, ident);
    self.selected_stream_type = stream_type;
}

/// Retrieves the currently selected `AudioCard`.
///
/// - Returns: The currently selected `AudioCard`.
/// - Errors: Returns an error if no cards are available.
pub fn getSelectedAudioCard(self: Hardware) !AudioCard {
    try errWhenEmpty(self.cards.items.len);
    return self.cards.items[self.selected_card];
}

/// Retrieves the currently selected audio port.
///
/// - Returns: The `AudioCard.AudioCardInfo` of the selected port.
/// - Errors: Returns an error if no cards are available.
pub fn getSelectedAudioPort(self: Hardware) !AudioCard.AudioCardInfo {
    try errWhenEmpty(self.cards.items.len);

    const card = self.cards.items[self.selected_card];

    if (self.selected_stream_type == Device.StreamType.playback) {
        return card.getPlaybackAt(self.selected_port);
    }

    return card.getCaptureAt(self.selected_port);
}

/// Sets the number of channels for the selected audio port.
///
/// - `channel_count`: The desired channel count.
/// - Errors: Returns an error if no cards are available or if the channel count is invalid.
pub fn setAudioPortChannelCount(self: *Hardware, channel_count: AudioCard.ChannelCount) !void {
    try errWhenEmpty(self.cards.items.len);

    const card = self.cards.items[self.selected_card];
    try card.setChannelCount(self.selected_stream_type, self.selected_port, channel_count);
}

/// Sets the audio format for the selected audio port.
///
/// - `format`: The desired audio format.
/// - Errors: Returns an error if no cards are available or if the format is invalid.
pub fn setAudioPortFormat(self: *Hardware, format: AudioCard.FormatType) !void {
    try errWhenEmpty(self.cards.items.len);

    const card = self.cards.items[self.selected_card];
    try card.setFormat(self.selected_stream_type, self.selected_port, format);
}

// Private

fn validateIdentifier(ident: []const u8) !void {
    if (ident.len == 0) {
        return AlsaError.invalid_identifier;
    }

    if (ident.len < 3 or !std.mem.eql(u8, ident[0..2], "hw")) {
        return AlsaError.invalid_identifier;
    }
}

fn addCard(alsa: *Hardware, card: AudioCard) !void {
    try alsa.cards.append(card);
}

fn loadSystemCards(alsa: *Hardware) !void {
    var card: c_int = -1;

    while (c_alsa.snd_card_next(&card) >= 0 and card >= 0) {
        var ctl: ?*c_alsa.snd_ctl_t = null;
        var buffer: [32]u8 = undefined;

        const card_name = try std.fmt.bufPrintZ(&buffer, "hw:{d}", .{card});
        var res = c_alsa.snd_ctl_open(&ctl, card_name, 0);

        if (res < 0) {
            log.warn("Failed to open control interface for card {d}: {s}", .{ card, c_alsa.snd_strerror(res) });
            continue;
        }

        var info: ?*c_alsa.snd_ctl_card_info_t = null;
        res = c_alsa.snd_ctl_card_info_malloc(&info);

        if (res < 0) {
            log.warn("Failed to allocate card info for card {d}: {s}", .{ card, c_alsa.snd_strerror(res) });
            continue;
        }

        defer c_alsa.snd_ctl_card_info_free(info);

        res = c_alsa.snd_ctl_card_info(ctl, info);

        if (res < 0) {
            log.warn("Failed to get card info for card {d}: {s}", .{ card, c_alsa.snd_strerror(res) });
            continue;
        }

        const card_details = try AudioCard.AudioCardInfo.init(alsa.allocator, .{ .card = card, .device = -1 }, c_alsa.snd_ctl_card_info_get_id(info), c_alsa.snd_ctl_card_info_get_name(info));
        var alsa_card = try AudioCard.init(alsa.allocator, card_details);

        alsa_card = (try addCardDevices(&alsa_card, ctl, Device.StreamType.playback)).*;
        alsa_card = (try addCardDevices(&alsa_card, ctl, Device.StreamType.capture)).*;

        try alsa.addCard(alsa_card);
        res = c_alsa.snd_ctl_close(ctl);

        if (res < 0) {
            log.warn("Failed to close control interface for card {d}: {s}", .{ card, c_alsa.snd_strerror(res) });
        }
    }
}

fn addCardDevices(card: *AudioCard, ctl: ?*c_alsa.snd_ctl_t, stream_type: Device.StreamType) !*AudioCard {
    var device: c_int = -1;
    var res: c_int = -1;

    while (c_alsa.snd_ctl_pcm_next_device(ctl, &device) >= 0 and device >= 0) {
        var pcm_info: ?*c_alsa.snd_pcm_info_t = null;

        res = c_alsa.snd_pcm_info_malloc(&pcm_info);

        if (res < 0) {
            log.warn("Failed to allocate PCM info for device {d}: {s}", .{ device, c_alsa.snd_strerror(res) });
            continue;
        }

        defer c_alsa.snd_pcm_info_free(pcm_info);

        c_alsa.snd_pcm_info_set_device(pcm_info, @as(c_uint, @intCast(device)));
        c_alsa.snd_pcm_info_set_subdevice(pcm_info, 0);
        c_alsa.snd_pcm_info_set_stream(pcm_info, @intFromEnum(stream_type));
        res = c_alsa.snd_ctl_pcm_info(ctl, pcm_info);

        if (res < 0) {
            log.warn("Failed to get PCM info for device {d}: {s}", .{ device, c_alsa.snd_strerror(res) });
            continue;
        }
        switch (stream_type) {
            Device.StreamType.capture => try card.addCapture(device, c_alsa.snd_pcm_info_get_id(pcm_info), c_alsa.snd_pcm_info_get_name(pcm_info)),
            Device.StreamType.playback => try card.addPlayback(device, c_alsa.snd_pcm_info_get_id(pcm_info), c_alsa.snd_pcm_info_get_name(pcm_info)),
        }
    }

    return card;
}

fn errWhenEmpty(len: usize) !void {
    if (len == 0) {
        log.err("Hardware: No cards available", .{});
        return AlsaError.card_not_found;
    }
}
