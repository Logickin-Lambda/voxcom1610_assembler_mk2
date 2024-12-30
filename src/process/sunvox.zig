// test

const sv = @cImport({
    @cDefine("SUNVOX_MAIN", {});
    @cInclude("../../sunvox/sunvox.h");
});

const Module = struct {
    // synths
    AnalogGenerator: []const u8 = "Analog generator",
    DrumSynth: []const u8 = "DrumSynth",
    FM: []const u8 = "FM",
    FMX: []const u8 = "FMX",
    Generator: []const u8 = "Generator",
    Input: []const u8 = "Input",
    Kicker: []const u8 = "Kicker",
    VorbisPlayer: []const u8 = "Vorbis player",
    Sampler: []const u8 = "Sampler",
    SpectraVoice: []const u8 = "SpectraVoice",
    // effects
    Amplifier: []const u8 = "Amplifier",
    Compressor: []const u8 = "Compressor",
    DCBlocker: []const u8 = "DC Blocker",
    Delay: []const u8 = "Delay",
    Distortion: []const u8 = "Distortion",
    Echo: []const u8 = "Echo",
    EQ: []const u8 = "EQ",
    FFT: []const u8 = "FFT",
    Filter: []const u8 = "Filter",
    FilterPro: []const u8 = "Filter Pro",
    Flanger: []const u8 = "Flanger",
    LFO: []const u8 = "LFO",
    Loop: []const u8 = "Loop",
    Modulator: []const u8 = "Modulator",
    PitchShifter: []const u8 = "Pitch shifter",
    Reverb: []const u8 = "Reverb",
    Smooth: []const u8 = "Smooth",
    VocalFilter: []const u8 = "Vocal filter",
    Vibrato: []const u8 = "Vibrato",
    WaveShaper: []const u8 = "WaveShaper",
    // miscs
    ADSR: []const u8 = "ADSR",
    Ctl2Note: []const u8 = "Ctl2Note",
    Feedback: []const u8 = "Feedback",
    Glide: []const u8 = "Glide",
    GPIO: []const u8 = "GPIO",
    MetaModule: []const u8 = "MetaModule",
    MultiCtl: []const u8 = "MultiCtl",
    MultiSynth: []const u8 = "MultiSynth",
    Pitch2Ctl: []const u8 = "Pitch2Ctl",
    PitchDetector: []const u8 = "Pitch Detector",
    Sound2Ctl: []const u8 = "Sound2Ctl",
    Velocity2Ctl: []const u8 = "Velocity2Ctl",
};

const SV_ERR = error{
    MISSING_DLL,
    METHOD_NOT_FOUND,
    FAILED_TO_INITIALIZED,
    FAILED_TO_CREATE_NEW_SLOT,
    FAILED_TO_LOAD_PROJECT,
    FAILED_TO_PLAY_PROJECT,
};

pub fn init(config: [*c]const u8, sample_rate: i32, channels: i32, flags: u32) !i32 {
    if (sv.sv_load_dll() != 0) return SV_ERR.MISSING_DLL;

    if (sv.sv_init) |func| {
        const result = func(config, @as(c_int, sample_rate), @as(c_int, channels), flags);

        if (result < 0) return SV_ERR.FAILED_TO_INITIALIZED;

        return @as(i32, result);
    } else {
        return SV_ERR.METHOD_NOT_FOUND;
    }
}

pub fn open_slot(slot_id: i4) !void {
    const status = sv.sv_open_slot.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_CREATE_NEW_SLOT;
}

pub fn load(slot_id: i4, file_name: [*c]const u8) !void {
    const status = sv.sv_load.?(@as(c_int, slot_id), file_name);

    if (status < 0) return SV_ERR.FAILED_TO_LOAD_PROJECT;
}

pub fn play_from_Beginning(slot_id: i4) !void {
    const status = sv.sv_play_from_beginning.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_PLAY_PROJECT;
}

pub fn end_of_song(slot_id: i4) bool {
    const status = sv.sv_end_of_song.?(@as(c_int, slot_id));

    if (status == 1) return true else return false;
}

pub fn new_module() !u32{
    //test 
} 