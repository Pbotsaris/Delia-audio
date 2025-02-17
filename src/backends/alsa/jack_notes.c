

// full duplex checks rates and formats
// checking sample rate

/// GET RaTE FIRSt
///
if (driver->playback_handle) {
  snd_pcm_hw_params_get_rate(driver->playback_hw_params, &pr, &dir);
}

if (driver->capture_handle) {
  snd_pcm_hw_params_get_rate(driver->capture_hw_params, &cr, &dir);
}

if (driver->capture_handle && driver->playback_handle) {

  // check sample rate
  if (cr != pr) {
    jack_error("playback and capture sample rates do "
               "not match (%d vs. %d)",
               pr, cr);
  }

  /* only change if *both* capture and playback rates
   * don't match requested certain hardware actually
   * still works properly in full-duplex with slightly
   */
  * different rate values between adc and dac
  if (cr != driver->frame_rate && pr != driver->frame_rate) {

    // check sample rate
    jack_error("sample rate in use (%d Hz) does not "
               "match requested rate (%d Hz)",
               cr, driver->frame_rate);
    driver->frame_rate = cr;
  }

} else if (driver->capture_handle && cr != driver->frame_rate) {
  jack_error("capture sample rate in use (%d Hz) does not "
             "match requested rate (%d Hz)",
             cr, driver->frame_rate);
  driver->frame_rate = cr;
} else if (driver->playback_handle && pr != driver->frame_rate) {
  jack_error("playback sample rate in use (%d Hz) does not "
             "match requested rate (%d Hz)",
             pr, driver->frame_rate);
  driver->frame_rate = pr;
}

//////////////////////////

// IMPORTANT - avail min is set up different for playback and capture
// apparently, the capture is set with smaller buffer size for lower latency
// and playback with greater to prevent xruns
// to be decided what to do

if (handle == driver->playback_handle)

  //
  err = snd_pcm_sw_params_set_avail_min(
      handle, sw_params,
      driver->frames_per_cycle *(*nperiodsp - driver->user_nperiods + 1));
else
  err = snd_pcm_sw_params_set_avail_min(handle, sw_params,
                                        driver->frames_per_cycle);

if (err < 0) {
  jack_error("ALSA: cannot set avail min for %s", stream_name);
  return -1;
}

// time stamp mode?
err =
    snd_pcm_sw_params_set_tstamp_mode(handle, sw_params, SND_PCM_TSTAMP_ENABLE);
if (err < 0) {
  jack_info("Could not enable ALSA time stamp mode for %s (err %d)",
            stream_name, err);
}

// time stamp
err = snd_pcm_sw_params_set_tstamp_type(handle, sw_params,
                                        SND_PCM_TSTAMP_TYPE_MONOTONIC);
if (err < 0) {
  jack_info("Could not use monotonic ALSA time stamps for %s (err %d)",
            stream_name, err);
}

/// In jack we store which stream has the most channel for some reason I don't
/// know yet

if (driver->playback_nchannels > driver->capture_nchannels) {
  driver->max_nchannels = driver->playback_nchannels;
} else {
  driver->max_nchannels = driver->capture_nchannels;
}

/// Silencing channels
///
/// jack keeps a bit set to track which channels have been processed or not
///
/// Allocate and initialize structures that rely on the
//     channels counts.
//
//     Set up the bit pattern that is used to record which
//     channels require action on every cycle. any bits that are
//     not set after the engine's process() call indicate channels
//     that potentially need to be silenced.
//

bitset_create(&driver->channels_done, driver->max_nchannels);
bitset_create(&driver->channels_not_done, driver->max_nchannels);

// then silences before commit

if (!bitset_empty(driver->channels_not_done)) {
  alsa_driver_silence_untouched_channels(driver, contiguous);
}

if ((err = snd_pcm_mmap_commit(driver->playback_handle, offset, contiguous)) <
    0) {
  jack_error("ALSA: could not complete playback of %" PRIu32
             " frames: error = %d",
             contiguous, err);
  if (err != -EPIPE && err != -ESTRPIPE)
    return -1;
}

/// buffers
/// jack keeps the address to to the buffer for each channel and the step size for each
   // for the pointer address in alsa for each channel
    driver->playback_addr = (char **)malloc(sizeof(char *) * driver->playback_nchannels);
    memset(driver->playback_addr, 0, sizeof(char *) * driver->playback_nchannels);

    // the interleaved step for each channel
    driver->playback_interleave_skip = (unsigned long *)malloc( sizeof(unsigned long *) * driver->playback_nchannels);
    memset(driver->playback_interleave_skip, 0, sizeof(unsigned long *) * driver->playback_nchannels);

    // tracks the channels that are silent
    driver->silent = (unsigned long *)malloc(sizeof(unsigned long) * driver->playback_nchannels);

    for (chn = 0; chn < driver->playback_nchannels; chn++) {
      driver->silent[chn] = 0;
    }

    for (chn = 0; chn < driver->playback_nchannels; chn++) {
      bitset_add(driver->channels_done, chn);
    }


// if I need dithering, they use a buffer
    driver->dither_state = (dither_state_t *)calloc(driver->playback_nchannels,
                                                    sizeof(dither_state_t));
  }


// also a buffer for syncing, may need this
  driver->clock_sync_data = (ClockSyncStatus *)malloc(sizeof(ClockSyncStatus) * driver->max_nchannels);


  //  pool timeout timing based on the period and buffer size, if we implement pooling
  driver->period_usecs = (jack_time_t)floor( (((float)driver->frames_per_cycle) / driver->frame_rate) * 1000000.0f);
  driver->poll_timeout = (int)floor(1.5f * driver->period_usecs);


/// jack storing the each channel in the alsa area_t in the buffer allocated above

  static int alsa_driver_get_channel_addresses(
    alsa_driver_t *driver,
    snd_pcm_uframes_t *capture_avail,
    snd_pcm_uframes_t *playback_avail, 
    snd_pcm_uframes_t *capture_offset,
    snd_pcm_uframes_t *playback_offset
    ) {
  int err;
  channel_t chn;

  if (capture_avail) {
    if ((err =
             snd_pcm_mmap_begin(driver->capture_handle, &driver->capture_areas,
                                (snd_pcm_uframes_t *)capture_offset,
                                (snd_pcm_uframes_t *)capture_avail)) < 0) {
      jack_error("ALSA: %s: mmap areas info error", driver->alsa_name_capture);
      return -1;
    }

    for (chn = 0; chn < driver->capture_nchannels; chn++) {
      const snd_pcm_channel_area_t *a = &driver->capture_areas[chn];

      // pointer
      driver->capture_addr[chn] = (char *)a->addr + ((a->first + a->step * *capture_offset) / 8);

      // step size in bytes
      driver->capture_interleave_skip[chn] = (unsigned long)(a->step / 8);
    }
  }

  if (playback_avail) {
    if ((err = snd_pcm_mmap_begin(driver->playback_handle,
                                  &driver->playback_areas,
                                  (snd_pcm_uframes_t *)playback_offset,
                                  (snd_pcm_uframes_t *)playback_avail)) < 0) 
    {
      jack_error("ALSA: %s: mmap areas info error ",
                 driver->alsa_name_playback);
      return -1;
    }

    for (chn = 0; chn < driver->playback_nchannels; chn++) {
      const snd_pcm_channel_area_t *a = &driver->playback_areas[chn];
      driver->playback_addr[chn] =
          (char *)a->addr + ((a->first + a->step * *playback_offset) / 8);
      driver->playback_interleave_skip[chn] = (unsigned long)(a->step / 8);
    }
  }

  return 0;
}

// the function above is called right after update
//    pavail = snd_pcm_avail_update(driver->playback_handle);
//
//    if (pavail != driver->frames_per_cycle * driver->playback_nperiods) {
//      jack_error("ALSA: full buffer not available at start");
//      return -1;
//    }



