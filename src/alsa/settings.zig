const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

pub const StreamType = enum(c_uint) {
    playback = c_alsa.SND_PCM_STREAM_PLAYBACK,
    capture = c_alsa.SND_PCM_STREAM_CAPTURE,
};

pub const BufferSize = enum(u32) {
    sr_216 = 216,
    sr_521 = 512,
    sr_1024 = 1024,
    sr_2048 = 2048,
    sr_4096 = 4096,
};

// interleaved channels     [L1 R1 L2 R2 L3 R3 3R...]
// non-interleaved channels [L1 L2 L3 L4 L5 L6... R1 R2 R3 R4 R5 R6...]
pub const AccessType = enum(c_uint) {
    // read-only access: simpler API
    // use `snd_pcm_readi` and `snd_pcm_writei` to read/write smaples.
    rw_interleaved = c_alsa.SND_PCM_ACCESS_RW_INTERLEAVED,
    rw_noninterleaved = c_alsa.SND_PCM_ACCESS_RW_NONINTERLEAVED,

    // MMAP access: more efficient
    // can directly map the ALSA b uffer into the application's memory space
    mmap_interleaved = c_alsa.SND_PCM_ACCESS_MMAP_INTERLEAVED,
    mmap_noninterleaved = c_alsa.SND_PCM_ACCESS_MMAP_NONINTERLEAVED,

    // NOTE: ommting `SND_PCM_ACCESS_MMAP_COMPLEX`
};

pub const Mode = enum(c_int) {
    none = 0,
    //  opens in non-blocking mode: calls to read/write audio data will return immediately
    nonblock = c_alsa.SND_PCM_NONBLOCK,
    // async for when handling audio I/O asynchronously
    async_mode = c_alsa.SND_PCM_ASYNC,
    // prevents automatic resampling when sample rate doesn't match hardware
    no_resample = c_alsa.SND_PCM_NO_AUTO_RESAMPLE,
    // prevents from automatically ajudisting the number of channel
    no_autochannel = c_alsa.SND_PCM_NO_AUTO_CHANNELS,
    // prevents from automatically ajusting the sample format
    no_autoformat = c_alsa.SND_PCM_NO_AUTO_FORMAT,
};

pub const Format = enum(c_int) {
    unknown = c_alsa.SND_PCM_FORMAT_UNKNOWN,

    // 8-bit integer formats
    signed_8bits = c_alsa.SND_PCM_FORMAT_S8,
    unsigned_8bits = c_alsa.SND_PCM_FORMAT_U8,

    // 16-bit integer formats
    signed_16bits_little_endian = c_alsa.SND_PCM_FORMAT_S16_LE,
    signed_16bits_big_endian = c_alsa.SND_PCM_FORMAT_S16_BE,
    unsigned_16bits_little_endian = c_alsa.SND_PCM_FORMAT_U16_LE,
    unsigned_16bits_big_endian = c_alsa.SND_PCM_FORMAT_U16_BE,

    // 20-bit integer formats
    signed_20bits_little_endian = c_alsa.SND_PCM_FORMAT_S20_LE,
    signed_20bits_big_endian = c_alsa.SND_PCM_FORMAT_S20_BE,
    unsigned_20bits_little_endian = c_alsa.SND_PCM_FORMAT_U20_LE,
    unsigned_20bits_big_endian = c_alsa.SND_PCM_FORMAT_U20_BE,

    // 24-bit integer formats
    signed_24bits_little_endian = c_alsa.SND_PCM_FORMAT_S24_LE,
    signed_24bits_big_endian = c_alsa.SND_PCM_FORMAT_S24_BE,
    unsigned_24bits_little_endian = c_alsa.SND_PCM_FORMAT_U24_LE,
    unsigned_24bits_big_endian = c_alsa.SND_PCM_FORMAT_U24_BE,

    // 32-bit integer formats
    signed_32bits_little_endian = c_alsa.SND_PCM_FORMAT_S32_LE,
    signed_32bits_big_endian = c_alsa.SND_PCM_FORMAT_S32_BE,
    unsigned_32bits_little_endian = c_alsa.SND_PCM_FORMAT_U32_LE,
    unsigned_32bits_big_endian = c_alsa.SND_PCM_FORMAT_U32_BE,

    // 32-bit floating-point formats
    float_32bits_little_endian = c_alsa.SND_PCM_FORMAT_FLOAT_LE,
    float_32bits_big_endian = c_alsa.SND_PCM_FORMAT_FLOAT_BE,

    // 64-bit floating-point formats
    float64_little_endian = c_alsa.SND_PCM_FORMAT_FLOAT64_LE,
    float64_big_endian = c_alsa.SND_PCM_FORMAT_FLOAT64_BE,

    // 3-byte per sample formats
    // These formats use 3 bytes per sample instead of 4, making them more compact than the regular 24-bit formats

    // 24-bit packed formats (3 bytes per sample)
    signed_24_3bits_little_endian = c_alsa.SND_PCM_FORMAT_S24_3LE,
    signed_24_3bits_big_endian = c_alsa.SND_PCM_FORMAT_S24_3BE,
    unsigned_24_3bits_little_endian = c_alsa.SND_PCM_FORMAT_U24_3LE,
    unsigned_24_3bits_big_endian = c_alsa.SND_PCM_FORMAT_U24_3BE,

    // 20-bit packed formats (3 bytes per sample)
    signed_20_3bits_little_endian = c_alsa.SND_PCM_FORMAT_S20_3LE,
    signed_20_3bits_big_endian = c_alsa.SND_PCM_FORMAT_S20_3BE,
    unsigned_20_3bits_little_endian = c_alsa.SND_PCM_FORMAT_U20_3LE,
    unsigned_20_3bits_big_endian = c_alsa.SND_PCM_FORMAT_U20_3BE,

    // 18-bit packed formats (3 bytes per sample)
    signed_18_3bits_little_endian = c_alsa.SND_PCM_FORMAT_S18_3LE,
    signed_18_3bits_big_endian = c_alsa.SND_PCM_FORMAT_S18_3BE,
    unsigned_18_3bits_little_endian = c_alsa.SND_PCM_FORMAT_U18_3LE,
    unsigned_18_3bits_big_endian = c_alsa.SND_PCM_FORMAT_U18_3BE,

    // Compressed formats
    mu_law = c_alsa.SND_PCM_FORMAT_MU_LAW, // µ-law compression, common in North American telephony
    a_law = c_alsa.SND_PCM_FORMAT_A_LAW, // A-law compression, common in European telephony
    ima_adpcm = c_alsa.SND_PCM_FORMAT_IMA_ADPCM, // IMA ADPCM compression
    mpeg = c_alsa.SND_PCM_FORMAT_MPEG,
    gsm = c_alsa.SND_PCM_FORMAT_GSM, // GSM 6.10 compression, used in mobile telephony

    // IEC 958 subframe formats
    // These formats represent subframes of data as defined by the IEC 958 standard, commonly used in digital audio interfaces like S/PDIF
    iec958_subframe_little_endian = c_alsa.SND_PCM_FORMAT_IEC958_SUBFRAME_LE,
    iec958_subframe_big_endian = c_alsa.SND_PCM_FORMAT_IEC958_SUBFRAME_BE,

    // G.723 ADPCM formats
    // G.723 is a codec used for voice compression, especially in telephony
    g723_24 = c_alsa.SND_PCM_FORMAT_G723_24, // G.723, 24 kbps
    g723_24_1b = c_alsa.SND_PCM_FORMAT_G723_24_1B, // G.723, 24 kbps, 1-byte alignment
    g723_40 = c_alsa.SND_PCM_FORMAT_G723_40, // G.723, 40 kbps
    g723_40_1b = c_alsa.SND_PCM_FORMAT_G723_40_1B, // G.723, 40 kbps, 1-byte alignment

    // DSD (Direct Stream Digital) formats
    // DSD is a high-resolution audio format used in SACDs (Super Audio CDs) and other high-fidelity audio systems
    dsd_u8 = c_alsa.SND_PCM_FORMAT_DSD_U8,
    dsd_u16_little_endian = c_alsa.SND_PCM_FORMAT_DSD_U16_LE,
    dsd_u32_little_endian = c_alsa.SND_PCM_FORMAT_DSD_U32_LE,
    dsd_u16_big_endian = c_alsa.SND_PCM_FORMAT_DSD_U16_BE,
    dsd_u32_big_endian = c_alsa.SND_PCM_FORMAT_DSD_U32_BE,

    // Special format
    // This is a catch-all for formats that don't fit into the standard categories, used for custom or non-standard formats
    special = c_alsa.SND_PCM_FORMAT_SPECIAL,

    ////////// same as the little endian counterparts ///////////
    //
    // signed_16bits = c_alsa.SND_PCM_FORMAT_S16,
    // unsigned_16bits = c_alsa.SND_PCM_FORMAT_U16,
    // signed_24bits = c_alsa.SND_PCM_FORMAT_S24,
    // unsigned_24bits = c_alsa.SND_PCM_FORMAT_U24,
    // signed_32bits = c_alsa.SND_PCM_FORMAT_S32,
    // unsigned_32bits = c_alsa.SND_PCM_FORMAT_U32,
    // float_32bits = c_alsa.SND_PCM_FORMAT_FLOAT,
    // float_64bits = c_alsa.SND_PCM_FORMAT_FLOAT64,
    // signed_20bits = c_alsa.SND_PCM_FORMAT_S20,
    // unsigned_20bits = c_alsa.SND_PCM_FORMAT_U20,
    // iec958_subframe = c_alsa.SND_PCM_FORMAT_IEC958_SUBFRAME,
    //
    ///////////////////////////////////////////

};
