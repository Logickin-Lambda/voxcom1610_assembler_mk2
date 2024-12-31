// test
const std = @import("std");
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
    FAILED_TO_INITIALIZE,
    FAILED_TO_DEINITIALIZE,
    FAILED_TO_CREATE_NEW_SLOT,
    FAILED_TO_LOAD_PROJECT,
    FAILED_TO_SAVE_PROJECT,
    FAILED_TO_PLAY_PROJECT,
    FAILED_TO_LOAD_MODULE,
    FAILED_TO_LOCK_SLOT,
    FAILED_TO_UNLOCK_SLOT,
    FAILED_TO_MODIFY_CONNECTION,
    FAILED_TO_LOAD_SUNVOX_PROJECT_IN_METAMODULE,
    FAILED_TO_ACCESS_EVENT,
};

pub fn init(config: [*c]const u8, sample_rate: i32, channels: i32, flags: u32) !i32 {
    if (sv.sv_load_dll() != 0) return SV_ERR.MISSING_DLL;

    if (sv.sv_init) |func| {
        const result = func(config, @as(c_int, sample_rate), @as(c_int, channels), flags);

        if (result < 0) return SV_ERR.FAILED_TO_INITIALIZE;

        return @as(i32, result);
    } else {
        return SV_ERR.METHOD_NOT_FOUND;
    }
}

pub fn deinit() !void {
    const status = sv.sv_deinit.?();
    if (status < 0) return SV_ERR.FAILED_TO_DEINITIALIZE;

    const dll_status = sv.sv_unload_dll();
    if (dll_status < 0) return SV_ERR.FAILED_TO_DEINITIALIZE;
}

pub fn openSlot(slot_id: i4) !void {
    const status = sv.sv_open_slot.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_CREATE_NEW_SLOT;
}

pub fn closeSlot(slot_id: i4) !void {
    const status = sv.sv_close_slot.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_CREATE_NEW_SLOT;
}

pub fn load(slot_id: i4, file_name: [*c]const u8) !void {
    const status = sv.sv_load.?(@as(c_int, slot_id), file_name);

    if (status < 0) return SV_ERR.FAILED_TO_LOAD_PROJECT;
}

pub fn save(slot_id: i4, file_name: [*c]const u8) !void {
    const status = sv.sv_save.?(@as(c_int, slot_id), file_name);

    if (status < 0) return SV_ERR.FAILED_TO_LOAD_PROJECT;
}

pub fn playFromBeginning(slot_id: i4) !void {
    const status = sv.sv_play_from_beginning.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_PLAY_PROJECT;
}

pub fn play(slot_id: i4) !void {
    const status = sv.sv_play.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_PLAY_PROJECT;
}

pub fn endOfSong(slot_id: i4) bool {
    const status = sv.sv_end_of_song.?(@as(c_int, slot_id));

    if (status == 1) return true else return false;
}

pub fn lockSlot(slot_id: i4) !void {
    const status = sv.sv_lock_slot.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_LOCK_SLOT;
}

pub fn unlockSlot(slot_id: i4) !void {
    const status = sv.sv_unlock_slot.?(@as(c_int, slot_id));

    if (status < 0) return SV_ERR.FAILED_TO_UNLOCK_SLOT;
}

pub fn newModule(slot_id: i4, module_type: [*c]const u8, name: [*c]const u8, x: i32, y: i32, z: i32) !u32 {
    const module_id = sv.sv_new_module.?(@as(c_int, slot_id), module_type, name, @as(c_int, x), @as(c_int, y), @as(c_int, z));

    if (module_id == 0) return module_id else return SV_ERR.FAILED_TO_LOAD_MODULE;
}

pub fn connectModule(slot_id: i4, source: i32, destination: i32) !void {
    const status = sv.sv_connect_module.?(@as(c_int, slot_id), @as(c_int, source), @as(c_int, destination));

    if (status < 0) return SV_ERR.FAILED_TO_MODIFY_CONNECTION;
}

pub fn disconnectConnectModule(slot_id: i4, source: i32, destination: i32) !void {
    const status = sv.sv_disconnect_module.?(@as(c_int, slot_id), @as(c_int, source), @as(c_int, destination));

    if (status < 0) return SV_ERR.FAILED_TO_MODIFY_CONNECTION;
}

pub fn loadModule(slot_id: i4, file_name: [*c]const u8, x: i32, y: i32, z: i32) !i32 {
    const module_id = sv.sv_load_module.?(@as(c_int, slot_id), file_name, @as(c_int, x), @as(c_int, y), @as(c_int, z));

    if (module_id >= 0) return @as(i32, module_id) else return SV_ERR.FAILED_TO_LOAD_MODULE;
}

pub fn metamoduleLoad(slot_id: i4, module_id: i32, fileName: [*c]const u8) !void {
    const status = sv.sv_metamodule_load.?(@as(c_int, slot_id), @as(c_int, module_id), fileName);

    if (status < 0) return SV_ERR.FAILED_TO_LOAD_SUNVOX_PROJECT_IN_METAMODULE;
}

pub fn sendEvent(slot_id: i4, track_num: i32, note: i32, vel: i32, module: i32, ctl: i32, ctl_val: i32) !void {
    const status = sv.sv_send_event.?(
        @as(c_int, slot_id),
        @as(c_int, track_num),
        @as(c_int, note),
        @as(c_int, vel),
        @as(c_int, module),
        @as(c_int, ctl),
        @as(c_int, ctl_val),
    );

    if (status < 0) return SV_ERR.FAILED_TO_ACCESS_EVENT;
}

pub fn setPatternEvent(
    slot_id: i4,
    pattern: i32,
    track: i32,
    line: i32,
    note: i32,
    vel: i32,
    module_id: i32,
    ctl: i32,
    ctl_val: i32,
) !void {
    const status = sv.sv_set_pattern_event.?(
        @as(c_int, slot_id),
        @as(c_int, pattern),
        @as(c_int, track),
        @as(c_int, line),
        @as(c_int, note),
        @as(c_int, vel),
        @as(c_int, module_id),
        @as(c_int, ctl),
        @as(c_int, ctl_val),
    );

    if (status < 0) return SV_ERR.FAILED_TO_ACCESS_EVENT;
}

pub fn getPatternEvent(
    slot_id: i4,
    pattern: i32,
    track: i32,
    line: i32,
    column: i32,
) !i32 {
    const data = sv.sv_get_pattern_event.?(
        @as(c_int, slot_id),
        @as(c_int, pattern),
        @as(c_int, track),
        @as(c_int, line),
        @as(c_int, column),
    );

    return if (data >= 0) @as(i32, column) else SV_ERR.FAILED_TO_ACCESS_EVENT;
}

pub fn setModuleCtlValue(slot_id: i4, module_id: i32, ctl: i32, ctl_val: i32, scale: i32) !void {
    const status = sv.sv_set_module_ctl_value.?(
        @as(c_int, slot_id),
        @as(c_int, module_id),
        @as(c_int, ctl),
        @as(c_int, ctl_val),
        @as(c_int, scale),
    );

    if (status < 0) return SV_ERR.FAILED_TO_ACCESS_EVENT;
}

pub fn getModuleCtlValue(slot_id: i4, module_id: i32, ctl: i32, scale: i32) i32 {
    const status = sv.sv_get_module_ctl_value.?(
        @as(c_int, slot_id),
        @as(c_int, module_id),
        @as(c_int, ctl),
        @as(c_int, scale),
    );

    return status;
}
