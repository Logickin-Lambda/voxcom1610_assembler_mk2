const std = @import("std");
const sv = @import("Sunvox.zig");

// each rom module can supports up to 128 word
const MOD_ODD_ENABLE: c_int = 0x48 + 1;
const MOD_EVEN_ENABLE: c_int = 0x49 + 1;

const MOD_ODD_INDEX: c_int = 0x5A + 1;
const MOD_EVEN_INDEX: c_int = 0x4D6 + 1;

const MOD_ROM_TRIGGER: c_int = 0x6A + 1;
const MOD_PROGRAM_BUS: c_int = 0x5F + 1;

const MOD_ROM_PAGE_INDEX: c_int = 0x40 + 1;

pub fn Exporter() type {
    return struct {
        const Self = @This();
        rom_struct_input_ports: std.ArrayList(c_int),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .rom_struct_input_ports = std.ArrayList(c_int).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.rom_struct_input_ports.deinit();
        }
    };
}
