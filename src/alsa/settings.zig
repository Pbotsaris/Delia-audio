const c_alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});

pub const StreamType = enum(c_uint) {
    playback = c_alsa.SND_PCM_STREAM_PLAYBACK,
    capture = c_alsa.SND_PCM_STREAM_CAPTURE,
};

pub const StartThreshold = enum(u32) {
    one_period = 1,
    two_periods = 2,
    three_periods = 3,
    four_periods = 4,
    five_periods = 5,
};

/// The `Strategy` enum defines the method by which ALSA will handle audio data transfer.
///
/// - `period_event`:
///   - This strategy enables period events, which means the ALSA hardware will trigger
///     an interrupt after every period is processed. This approach can reduce CPU usage
///     by allowing the system to sleep until the period event occurs, making it suitable
///     for low-latency applications.
///   - When this strategy is selected, the `avail_min` is set to the full hardware buffer size,
///     essentially relying on interrupt-driven processing rather than polling or manually
///     checking for available buffer space.
///
/// - `min_available`:
///   - This strategy disables period events and instead sets `avail_min` to the size of the
///     period buffer. This means the application will handle data transfer whenever the
///     buffer has enough space for a full period. It is typically used in scenarios where
///     more precise control over buffer availability is needed, and where polling or
///     manual checks are preferred over interrupt-driven processing.
pub const Strategy = enum {
    period_event,
    min_available,
};

pub const BufferSize = enum(u32) {
    bz_216 = 216,
    bz_521 = 512,
    bz_1024 = 1024,
    bz_2048 = 2048,
    bz_4096 = 4096,
};

pub const ChannelCount = enum(u32) {
    mono = 1,
    stereo = 2,
    quad = 4,
    surround_5_1 = 6,
    surround_7_1 = 8,
};

// https://en.wikipedia.org/wiki/Sampling_(signal_processing)
// ommting incredibly high sample rates
pub const SampleRate = enum(u32) {
    sr_8Khz = 8000,
    sr_11Khz = 11025,
    sr_16Khz = 16000,
    sr_22Khz = 22050,
    sr_32Khz = 32000, // miniDV isoterical sample rate
    sr_37Khz = 37800, // CD-XA audio
    sr_44k56hz = 44056, // NTSC color subcarrier
    sr_44Khz = 44100,
    sr_50Khz = 50000,
    sr_50k400hz = 50400, // DAT audio
    sr_64Khz = 64000, // very unconventional
    sr_48Khz = 48000,
    sr_82Khz = 82000,
    sr_96Khz = 96000,
    sr_176Khz = 176400, // HDCD recorders. 4x CD audio
    sr_192Khz = 192000,
    sr_352Khz = 352800,
};

/// interleaved channels     [L1 R1 L2 R2 L3 R3 3R...]
/// non-interleaved channels [L1 L2 L3 L4 L5 L6... R1 R2 R3 R4 R5 R6...]
pub const AccessType = enum(c_uint) {
    /// read-only access: simpler API
    //. use `snd_pcm_readi` and `snd_pcm_writei` to read/write smaples.
    rw_interleaved = c_alsa.SND_PCM_ACCESS_RW_INTERLEAVED,
    rw_noninterleaved = c_alsa.SND_PCM_ACCESS_RW_NONINTERLEAVED,

    /// MMAP access: more efficient
    /// can directly map the ALSA b uffer into the application's memory space
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

pub const Signedness = enum(u32) {
    signed,
    unsigned,
};

pub const ByteOrder = enum(u32) {
    little_endian,
    big_endian,
};

pub const FormatType = enum(c_int) {
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
    signed_24bits_packed3_little_endian = c_alsa.SND_PCM_FORMAT_S24_3LE,
    signed_24bits_packed3_big_endian = c_alsa.SND_PCM_FORMAT_S24_3BE,
    unsigned_24bits_packed3_little_endian = c_alsa.SND_PCM_FORMAT_U24_3LE,
    unsigned_24bits_packed3_big_endian = c_alsa.SND_PCM_FORMAT_U24_3BE,

    // 20-bit packed formats (3 bytes per sample)
    signed_20bits_packed3_little_endianendian = c_alsa.SND_PCM_FORMAT_S20_3LE,
    signed_20bits_packed3_big_endian = c_alsa.SND_PCM_FORMAT_S20_3BE,
    unsigned_20bits_packed3_little_endian = c_alsa.SND_PCM_FORMAT_U20_3LE,
    unsigned_20bits_packed3_big_endian = c_alsa.SND_PCM_FORMAT_U20_3BE,

    // 18-bit packed formats (3 bytes per sample)
    signed_18bits_packed3_little_endian = c_alsa.SND_PCM_FORMAT_S18_3LE,
    signed_18bits_packed3_big_endian = c_alsa.SND_PCM_FORMAT_S18_3BE,
    unsigned_18bits_packed3_little_endian = c_alsa.SND_PCM_FORMAT_U18_3LE,
    unsigned_18bits_packed3_big_endian = c_alsa.SND_PCM_FORMAT_U18_3BE,

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

    // Note in use
    //
    // G.723 ADPCM formats
    // G.723 is a codec used for voice compression, especially in telephony
    // g723_24 = c_alsa.SND_PCM_FORMAT_G723_24, // G.723, 24 kbps
    // g723_24_1b = c_alsa.SND_PCM_FORMAT_G723_24_1B, // G.723, 24 kbps, 1-byte alignment
    // g723_40 = c_alsa.SND_PCM_FORMAT_G723_40, // G.723, 40 kbps
    // g723_40_1b = c_alsa.SND_PCM_FORMAT_G723_40_1B, // G.723, 40 kbps, 1-byte alignment
    /////////////////////////////////////////////////////////////

    // Note in use
    //
    // DSD (Direct Stream Digital) formats
    // DSD is a high-resolution audio format used in SACDs (Super Audio CDs) and other high-fidelity audio systems
    // dsd_u8 = c_alsa.SND_PCM_FORMAT_DSD_U8,
    // dsd_u16_little_endian = c_alsa.SND_PCM_FORMAT_DSD_U16_LE,
    // dsd_u16_big_endian = c_alsa.SND_PCM_FORMAT_DSD_U16_BE,
    // dsd_u32_little_endian = c_alsa.SND_PCM_FORMAT_DSD_U32_LE,
    // dsd_u32_big_endian = c_alsa.SND_PCM_FORMAT_DSD_U32_BE,
    /////////////////////////////////////////////////////////////

    // Special format
    // This is a catch-all for formats that don't fit into the standard categories, used for custom or non-standard formats
    // special = c_alsa.SND_PCM_FORMAT_SPECIAL,

    ////////// same as the little endian counterparts ///////////
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
    ///////////////////////////////////////////

    pub fn ToType(self: FormatType) type {
        return switch (self) {
            .signed_8bits => i8,
            .unsigned_8bits => u8,

            .signed_16bits_little_endian, .signed_16bits_big_endian => i16,
            .unsigned_16bits_little_endian, .unsigned_16bits_big_endian => u16,

            // NOTE: that Alsa uses 32 word packed in 4bytesm with the lower 20 bits used
            // The data is LSB justified, meaning the data is packed towards the least significant bit
            .signed_20bits_little_endian, .signed_20bits_big_endian => i20,
            .unsigned_20bits_little_endian, .unsigned_20bits_big_endian => u20,

            // NOTE: that in ALSA this uses 32bits words using the bottom 3 bytes
            .signed_24bits_little_endian, .signed_24bits_big_endian => i24,
            .unsigned_24bits_little_endian, .unsigned_24bits_big_endian => u24,

            .signed_32bits_little_endian, .signed_32bits_big_endian => i32,
            .unsigned_32bits_little_endian, .unsigned_32bits_big_endian => u32,

            // ranges from -1.0 to 1.0
            .float_32bits_little_endian, .float_32bits_big_endian => f32,
            .float64_little_endian, .float64_big_endian => f64,

            .signed_24bits_packed3_little_endian,
            .signed_24bits_packed3_big_endian,
            .unsigned_24bits_packed3_little_endian,
            .unsigned_24bits_packed3_big_endian,
            .signed_20bits_packed3_little_endian,
            .signed_20bits_packed3_big_endian,
            .unsigned_20bits_packed3_little_endian,
            .unsigned_20bits_packed3_big_endian,
            .signed_18bits_packed3_little_endian,
            .signed_18bits_packed3_big_endian,
            .unsigned_18bits_packed3_little_endian,
            .unsigned_18bits_packed3_big_endian,
            => [3]u8,

            // Generally 32bits with audio in 16, 20, 24 bits
            // and the remaining bits is used for syncronization
            .iec958_subframe_little_endian, .iec958_subframe_big_endian => u32,

            // Compressed formats
            // will need decoding logic
            else => u8,
        };
    }
};

pub const formats: [@typeInfo(FormatType).Enum.fields.len]c_int = blk: {
    const info = @typeInfo(FormatType);
    const len = info.Enum.fields.len;
    var temp: [len]c_int = undefined;

    for (0..len) |i| {
        temp[i] = info.Enum.fields[i].value;
    }

    break :blk temp;
};

pub const sample_rates: [@typeInfo(SampleRate).Enum.fields.len]u32 = blk: {
    const info = @typeInfo(SampleRate);
    const len = info.Enum.fields.len;
    var temp: [len]u32 = undefined;

    for (0..len) |i| {
        temp[i] = info.Enum.fields[i].value;
    }

    break :blk temp;
};

pub const channel_counts: [@typeInfo(ChannelCount).Enum.fields.len]u32 = blk: {
    const info = @typeInfo(ChannelCount);
    const len = info.Enum.fields.len;
    var temp: [len]u32 = undefined;

    for (0..len) |i| {
        temp[i] = info.Enum.fields[i].value;
    }

    break :blk temp;
};
