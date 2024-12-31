const std = @import("std");
const String = @import("string").String;
const lkup = @import("../models/VoxcomLkup.zig");

const SUNVOX_CTRL_MULTIPLIER: c_int = 128;

pub fn VOXCOMMachineCode() type {
    return struct {
        const Self = @This();
        raw_code_line: *const String,
        high_byte: u8,
        low_byte: u8,

        pub fn init(raw_code_line: *const String, opcode: []const u8) Self {
            return .{
                .raw_code_line = raw_code_line,
                .high_byte = lkup.contains(opcode).?,
                .low_byte = 0b00_000_000,
            };
        }

        pub fn init_raw(raw_code_line: *const String, high_byte: u8, low_byte: u8) Self {
            return .{
                .raw_code_line = raw_code_line,
                .high_byte = high_byte,
                .low_byte = low_byte,
            };
        }

        // pub fn deinit(self: *Self) void {
        //     self.raw_code_line.deinit();
        // }

        pub fn highByteToCtrl(self: *Self) c_int {
            return @as(c_int, @intCast(self.high_byte)) * SUNVOX_CTRL_MULTIPLIER;
        }

        pub fn lowByteToCtrl(self: *Self) c_int {
            return @as(c_int, @intCast(self.low_byte)) * SUNVOX_CTRL_MULTIPLIER;
        }
    };
}

test "VOXCOMMachineCode Test" {
    const test_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    var raw_code_line = try String.init_with_contents(arena.allocator(), "ADDC A 9");
    defer raw_code_line.deinit();

    var machine_code = VOXCOMMachineCode().init(&raw_code_line, lkup.ADD);
    machine_code.low_byte = 9;
    // defer machine_code.deinit();

    try std.testing.expectEqualStrings("ADDC A 9", machine_code.raw_code_line.str());
    try std.testing.expectEqual(0b00_100_000, machine_code.high_byte);
    try std.testing.expectEqual(0b00_001_001, machine_code.low_byte);
    try std.testing.expectEqual(0x1000, machine_code.highByteToCtrl());
    try std.testing.expectEqual(0x480, machine_code.lowByteToCtrl());
}
