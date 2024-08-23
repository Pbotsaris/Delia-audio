const std = @import("std");
const log = std.log.scoped(.alsa);
pub const Device = @import("Device.zig");
pub const Card = @import("Card.zig");
const AlsaError = @import("error.zig").AlsaError;

const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

pub const Alsa = struct {
    pub const MAX_CARDS = 32;

    cards: std.ArrayList(Card),
    card_count: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Alsa {
        var alsa = Alsa{ .cards = std.ArrayList(Card).init(allocator), .allocator = allocator };
        try getSystemCards(&alsa);

        //        log.debug("outer card: {s}", .{alsa.cards[0].details.name});
        //        log.debug("outer capture: {s}", .{alsa.cards[0].captures[0].name});
        //        log.debug("outer capture internal buffer: {s}", .{alsa.cards[0].captures[0].internal_buffer});
        //
        return alsa;
    }

    pub fn deinit(self: *Alsa) void {
        for (self.cards.items) |*card| {
            card.*.deinit();
        }

        self.cards.deinit();
    }

    fn addCard(alsa: *Alsa, card: Card) !void {
        if (alsa.card_count >= Alsa.MAX_CARDS) {
            return AlsaError.card_max_reached;
        }

        try alsa.cards.append(card);
    }

    fn getSystemCards(alsa: *Alsa) !void {
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

            const card_details = try Card.Details.init(alsa.allocator, card, c_alsa.snd_ctl_card_info_get_id(info), c_alsa.snd_ctl_card_info_get_name(info));
            var alsa_card = try Card.init(alsa.allocator, card_details);

            alsa_card = try addCardDevices(&alsa_card, ctl, Device.StreamType.playback);
            alsa_card = try addCardDevices(&alsa_card, ctl, Device.StreamType.capture);

            try alsa.addCard(alsa_card);

            res = c_alsa.snd_ctl_close(ctl);

            if (res < 0) {
                log.warn("Failed to close control interface for card {d}: {s}", .{ card, c_alsa.snd_strerror(res) });
            }
        }
    }

    fn addCardDevices(card: *Card, ctl: ?*c_alsa.snd_ctl_t, stream_type: Device.StreamType) !Card {
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

            //break;
        }

        return card.*;
    }
};
