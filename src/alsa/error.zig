pub const AlsaError = error{
    device_init,
    device_deinit,
    device_list,
    card_out_of_bounds,
    playback_out_of_bounds,
    capture_out_of_bounds,
};
