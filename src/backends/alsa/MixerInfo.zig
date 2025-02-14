const std = @import("std");
const log = std.log.scoped(.alsa);
const utils = @import("../../utils/utils.zig");

const AlsaError = @import("error.zig").AlsaError;
pub const AudioCard = @import("AudioCard.zig");

const c_alsa = @cImport({
    @cInclude("asoundlib.h");
});

const MixerInfoError = error{
    must_init_mix_info_with_card,
    open_mixer,
    mixer_elem_alloc,
    mixer_deinit,
    get_elem_list,
};

const InterfaceType = enum(c_int) {
    pcm = c_alsa.SND_CTL_ELEM_IFACE_PCM,
    mixer = c_alsa.SND_CTL_ELEM_IFACE_MIXER,
    timer = c_alsa.SND_CTL_ELEM_IFACE_TIMER,
    rawmidi = c_alsa.SND_CTL_ELEM_IFACE_RAWMIDI,
    sequencer = c_alsa.SND_CTL_ELEM_IFACE_SEQUENCER,
    hwdep = c_alsa.SND_CTL_ELEM_IFACE_HWDEP,
};

const Self = @This();

ctl: ?c_alsa.snd_mixer_ctl_t = null,
list: ?c_alsa.snd_mixer_elem_list_t = null,
count: usize = 0,
info: ?c_alsa.snd_ctl_elem_info_t = null,
elem_id: ?c_alsa.snd_ctl_elem_id_t = null,

pub fn init(card: AudioCard.AudioCardInfo) !void {
    if (card.type != .card) {
        return MixerInfoError.must_init_mix_info_with_card;
    }

    var ctl: ?c_alsa.snd_mixer_ctl_t = null;
    var list: ?*c_alsa.snd_ctl_elem_list_t = null;
    var elem_info: ?*c_alsa.snd_ctl_elem_info_t = null;
    var elem_id: ?*c_alsa.snd_ctl_elem_id_t = null;

    if (c_alsa.snd_mixer_open(&ctl, card.identifier, 0) != 0) {
        return MixerInfoError.open_mixer;
    }

    errdefer {
        if (ctl) |c|
            _ = c_alsa.snd_mixer_close(c);
    }

    if (c_alsa.snd_ctl_elem_list_malloc(&list) != 0) {
        return MixerInfoError.mixer_elem_alloc;
    }

    errdefer if (list) |l| c_alsa.snd_ctl_elem_list_free(l);

    if (c_alsa.snd_ctl_elem_list(ctl, list) != 0) {
        return MixerInfoError.get_elem_list;
    }

    const count = c_alsa.snd_ctl_elem_list_get_count(list);

    if (c_alsa.snd_ctl_elem_list_alloc_space(list, count) != 0) {
        return MixerInfoError.mixer_elem_alloc;
    }

    if (c_alsa.snd_ctl_elem_list(ctl, list) != 0) {
        return MixerInfoError.get_elem_list;
    }

    if (c_alsa.snd_ctl_elem_info_malloc(&elem_info) != 0) {
        return MixerInfoError.mixer_elem_alloc;
    }

    errdefer if (elem_info) |e| c_alsa.snd_ctl_elem_info_free(e);

    if (c_alsa.snd_ctl_elem_id_malloc(&elem_id) != 0) {
        return MixerInfoError.mixer_elem_alloc;
    }

    errdefer if (elem_id) |id| c_alsa.snd_ctl_elem_id_free(id);

    return .{
        .ctl = ctl,
        .list = list,
        .count = count,
        .info = elem_info,
        .elem_id = elem_id,
    };
}

//pub fn queryAlloc(self: *Self, allocator: std.mem.Allocator, iface: InterfaceType) void {
//
//}

pub fn deinit(self: *Self) !void {
    if (self.list) |list| {
        c_alsa.snd_ctl_elem_list_free(list);
    }

    if (self.info) |info| {
        c_alsa.snd_ctl_elem_info_free(info);
    }

    if (self.elem_id) |id| {
        c_alsa.snd_ctl_elem_id_free(id);
    }

    if (self.mixer_ctl) |ctl| {
        const err = c_alsa.snd_mixer_close(ctl);

        if (err != 0) return MixerInfoError.mixer_deinit;
    }
}
