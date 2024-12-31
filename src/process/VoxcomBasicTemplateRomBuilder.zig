const std = @import("std");
const sv = @import("Sunvox.zig");
const mxhc = @import("../models/VOXCOMMachineCode.zig");

// each rom module can supports up to 128 word
const VOXCOM_MEMORY_SLOT_SIZE = 128;

// This is specified in the sunvox lib which the module id for the set event function must be offseted by one
const VOXOM_MEMORY_FIRST_MEMORY_MODULE_ID: c_int = 0x82 + 1;
const VOXOM_MEMORY_CTL = 0x0300;

const GEN_ERR = error{
    PROGRAM_TOO_LARGE,
};

pub fn RomGenerator() type {
    return struct {
        const Self = @This();
        compiled_programs: *const std.ArrayList(mxhc.VOXCOMMachineCode()),
        allocator: std.mem.Allocator,

        pub fn init(
            allocator: std.mem.Allocator,
            compiled_programs: *const std.ArrayList(mxhc.VOXCOMMachineCode()),
        ) !Self {
            _ = try sv.init(0, 44100, 2, 0);
            try sv.openSlot(0);

            return Self{
                .compiled_programs = compiled_programs,
                .allocator = allocator,
            };
        }

        pub fn deinit(_: *Self) !void {
            try sv.closeSlot(0);
            try sv.deinit();
        }

        pub fn generate(self: *Self) !void {
            // calculate the number of modules required for the program
            const program_size = self.compiled_programs.items.len;
            if (program_size > 65536) {
                std.log.err("Program Too Large For VOXCOM 1610 (Current: {d}, Max: 65536)", .{program_size});
                return GEN_ERR.PROGRAM_TOO_LARGE;
            }
            // If we have remainder of the division, we need to add an extra block for the remaining code
            const page_offset: usize = if (program_size % VOXCOM_MEMORY_SLOT_SIZE != 0) 1 else 0;
            const memory_slot_count = @divTrunc(program_size, VOXCOM_MEMORY_SLOT_SIZE) + page_offset;

            for (0..memory_slot_count) |i| {
                try self.generatePartition(i);
            }
        }

        fn generatePartition(self: *Self, index: usize) !void {
            const program_size = self.compiled_programs.items.len;
            const slice_start = index * VOXCOM_MEMORY_SLOT_SIZE;
            const slice_end = if (slice_start + VOXCOM_MEMORY_SLOT_SIZE > program_size) program_size else slice_start + VOXCOM_MEMORY_SLOT_SIZE;

            const program_partition = self.compiled_programs.items[slice_start..slice_end];

            // To write the rom, we need:
            // 1. load the internal rom project
            // 2. iterate the partition, and write all the line into the rom project
            // 3. Play the project so that the pattern applys the control change for the memory cells
            // 4. once the prject playback has completed, save the project into the temp file call "ROMXX.sunvox"
            try sv.load(0, "resources/Rom Chip Internal.sunvox");

            var module_id: c_int = VOXOM_MEMORY_FIRST_MEMORY_MODULE_ID;
            for (0..program_partition.len) |i| {
                var program_line = program_partition[i];
                const high_byte = program_line.highByteToCtrl();
                const low_byte = program_line.lowByteToCtrl();

                try sv.setPatternEvent(0, 0, 0, @as(c_int, @intCast(i)), 0, 0, module_id, VOXOM_MEMORY_CTL, high_byte);
                module_id += 1;
                try sv.setPatternEvent(0, 0, 1, @as(c_int, @intCast(i)), 0, 0, module_id, VOXOM_MEMORY_CTL, low_byte);
                module_id += 1;
            }

            try sv.playFromBeginning(0);

            const compiled_rom_name = try std.fmt.allocPrint(self.allocator, "resources/temp/ROM{d}.sunvox", .{index});

            try sv.playFromBeginning(0);

            // To prevent halt and catch fire, I decided to put the program into a sleep during
            // the project playback which is done asynchoniously
            while (!sv.endOfSong(0)) {
                std.time.sleep(1000 * 1000); // 1 ms of stopping
            }

            try sv.save(0, @as([*c]const u8, @ptrCast(compiled_rom_name)));
        }
    };
}
