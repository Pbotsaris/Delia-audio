pub const AlsaError = error{
    device_init,
    device_deinit,
    device_list,
    device_prepare,
    device_timeout,
    device_xrun,
    device_unexpected,
    card_out_of_bounds,
    playback_out_of_bounds,
    capture_out_of_bounds,
};
