const std = @import("std");
const nfd = @import("nfd");
const sv = @import("Sunvox.zig");
const String = @import("string").String;

// each rom module can supports up to 128 word
const MOD_ODD_ENABLE: c_int = 0x48;
const MOD_EVEN_ENABLE: c_int = 0x49;

const MOD_ODD_INDEX: c_int = 0x5A;
const MOD_EVEN_INDEX: c_int = 0x4D6;

const MOD_ROM_TRIGGER: c_int = 0x6A;
const MOD_PROGRAM_BUS: c_int = 0x5F;

const MOD_ROM_PAGE_INDEX: c_int = 0x40;

const Cooridination = struct { x: c_int, y: c_int };
const MemoryCellOrigin = Cooridination{ .x = 3056, .y = 960 };
const DecoderCellOrigin = Cooridination{ .x = 2656, .y = 240 };
const ModuleOffset = Cooridination{ .x = 80, .y = 80 };

pub fn Exporter() type {
    return struct {
        const Self = @This();
        rom_struct_input_ports: std.ArrayList(c_int),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Self {
            _ = try sv.init(0, 44100, 2, 0);
            try sv.openSlot(0);

            return Self{
                .allocator = allocator,
                .rom_struct_input_ports = std.ArrayList(c_int).init(allocator),
            };
        }

        pub fn deinit(self: *Self) !void {
            self.rom_struct_input_ports.deinit();
            try sv.closeSlot(0);
            try sv.deinit();
        }

        pub fn constructRomBank(self: *Self) !void {
            try sv.load(0, "resources/VoxCom1610 Basic Blank.sunvox");

            const resource_root_path = "resources/temp/";
            var dir = try std.fs.cwd().openDir(resource_root_path, .{ .iterate = true });
            var walker = try dir.walk(self.allocator);
            defer walker.deinit();

            // construct Memory Bank
            var memory_block_index: c_int = 0;
            while (try walker.next()) |e| {
                const file_path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ resource_root_path, e.path });
                try self.constructRom(file_path, memory_block_index);
                memory_block_index += 1;
            }

            // construct Decoder
            // memory_block_index can also be used for counting the number of ROM chips, thus using the halved value to build the decoder
            const is_even: c_int = if (@mod(memory_block_index, 2) != 0) 1 else 0;
            const decoder_size: c_int = @divTrunc(memory_block_index, 2) + is_even;

            for (0..@as(usize, @intCast(decoder_size))) |i| {
                try self.constructDecoder(i);
            }

            try sv.playFromBeginning(0);

            const path_opt = try nfd.saveFileDialog("sunvox", null);

            if (path_opt) |path| {
                var path_string = try String.init_with_contents(self.allocator, path);
                defer path_string.deinit();

                if (!path_string.endsWith(".sunvox")) {
                    try path_string.concat(".sunvox");
                }

                while (!sv.endOfSong(0)) {
                    std.time.sleep(1000 * 1000 * 5);
                }

                try sv.save(0, @as([*c]const u8, @ptrCast(path_string.str())));
            }
        }

        /// This construct a ROM structure used in VOXCOM 1610 like shown:
        ///  ____________        ____________        ____________        ____________        ____________
        /// |            |      |            |      |            |      |            |      |            |
        /// |  AND GATE  |----->| Transistor |----->| Sound2CTL  |----->|    ROM     |----->| Transistor |
        /// |____________|      |____________|      |____________|      |____________|      |____________|
        ///       \______________________________________________________________________________/`
        ///
        fn constructRom(self: *Self, rom_file_path: []const u8, memory_block_index: c_int) !void {
            try sv.lockSlot(0);

            // define the y level of the module group
            const input_y = MemoryCellOrigin.y - (ModuleOffset.y * memory_block_index);

            // input port
            const input_x = MemoryCellOrigin.x;
            const input_module_id = try sv.loadModule(0, "resources/Rom Chip/[1] AND GATE [2-5].sunsynth", input_x, input_y, 0);
            try self.rom_struct_input_ports.append(input_module_id); // will be used for decoder connection

            // indexer transistor
            const idx_trstor_x = MemoryCellOrigin.x + ModuleOffset.x;
            const idx_trstor_module_id = try sv.loadModule(0, "resources/Rom Chip/[2] Transistor [3].sunsynth", idx_trstor_x, input_y, 0);
            try sv.connectModule(0, input_module_id, idx_trstor_module_id);

            if (@mod(memory_block_index, 2) == 1) {
                try sv.connectModule(0, MOD_EVEN_ENABLE, input_module_id);
                try sv.connectModule(0, MOD_EVEN_INDEX, idx_trstor_module_id);
            } else {
                try sv.connectModule(0, MOD_ODD_ENABLE, input_module_id);
                try sv.connectModule(0, MOD_ODD_INDEX, idx_trstor_module_id);
            }

            // sound2ctl
            const sound2ctl_x = MemoryCellOrigin.x + ModuleOffset.x * 2;
            const sound2ctl_module_id = try sv.loadModule(0, "resources/Rom Chip/[3] Sound2Ctl [4].sunsynth", sound2ctl_x, input_y, 0);
            try sv.connectModule(0, idx_trstor_module_id, sound2ctl_module_id);

            // The ROM Chip
            const rom_x = MemoryCellOrigin.x + ModuleOffset.x * 3;
            const rom_module_id = try sv.loadModule(0, "resources/Rom Chip/[4] Rom Chip [5].sunsynth", rom_x, input_y, 0);
            try sv.connectModule(0, sound2ctl_module_id, rom_module_id);
            try sv.connectModule(0, MOD_ROM_TRIGGER, rom_module_id);
            std.debug.print("ROM file path: {s}\n", .{rom_file_path});
            try sv.metamoduleLoad(0, rom_module_id, @as([*c]const u8, @ptrCast(rom_file_path)));

            // output transistor
            const output_x = MemoryCellOrigin.x + ModuleOffset.x * 4;
            const output_module_id = try sv.loadModule(0, "resources/Rom Chip/[5] Transistor.sunsynth", output_x, input_y, 0);
            try sv.connectModule(0, rom_module_id, output_module_id);
            try sv.connectModule(0, input_module_id, output_module_id);
            try sv.connectModule(0, output_module_id, MOD_PROGRAM_BUS);

            try sv.unlockSlot(0);
        }

        fn constructDecoder(self: *Self, decoder_index: usize) !void {
            try sv.lockSlot(0);

            // define the y level of the module group
            const decoder_y = @as(i32, @intCast(DecoderCellOrigin.y - (ModuleOffset.y * @as(i32, @intCast(decoder_index)))));

            // input port
            const input_x = DecoderCellOrigin.x;
            const input_module_id = try sv.loadModule(0, "resources/Decoder/[1] Pager Base [2].sunsynth", input_x, decoder_y, 0);
            try sv.connectModule(0, MOD_ROM_PAGE_INDEX, input_module_id);

            // negative detector
            const neg_detector_x = DecoderCellOrigin.x + ModuleOffset.x;
            const neg_detector_module_id = try sv.loadModule(0, "resources/Decoder/[2] Negative Detector [3].sunsynth", neg_detector_x, decoder_y, 0);
            try sv.connectModule(0, input_module_id, neg_detector_module_id);

            // not gate
            const not_gate_x = DecoderCellOrigin.x + ModuleOffset.x * 2;
            const not_gate_module_id = try sv.loadModule(0, "resources/Decoder/[3] Not Gate.sunsynth", not_gate_x, decoder_y, 0);
            try sv.connectModule(0, neg_detector_module_id, not_gate_module_id);

            // connect the output of the decoder into the input of the ROM transistor, two ROM at a time
            const is_lone_tail = if (decoder_index * 2 > self.rom_struct_input_ports.items.len) true else false;

            try sv.connectModule(0, not_gate_module_id, self.rom_struct_input_ports.items[decoder_index * 2]);
            if (!is_lone_tail) try sv.connectModule(0, not_gate_module_id, self.rom_struct_input_ports.items[decoder_index * 2 + 1]);

            try sv.unlockSlot(0);

            // For some reason setModuleCtlValue doesn't work for zig currently, so I decided to write the control update as an automation,
            // which it should be triggered at the end of the program when the it plays a finished tone.
            const dc_offset = 0x8000 - 0x80 * @as(i32, @intCast(decoder_index));
            const track_id: i32 = if (@mod(decoder_index, 2) == 0) 2 else 3;
            try sv.setPatternEvent(0, 0, track_id, @as(i32, @intCast(decoder_index)) >> 1, 0, 0, input_module_id + 1, 0x0300, dc_offset);
        }
    };
}
