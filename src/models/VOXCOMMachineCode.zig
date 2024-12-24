const std = @import("std");
const String = @import("string").String;

const SUNVOX_CTRL_MULTIPLIER: c_int = 128;

pub fn VOXCOMMachineCode() type {
    return struct {
        const Self = @This();
        raw_code_line: String,
        high_byte: u8,
        low_byte: u8,

        pub fn init(raw_code_line: String, high_byte: u8, low_byte: u8) !Self {
            return .{
                .raw_code_line = try raw_code_line.clone(),
                .high_byte = high_byte,
                .low_byte = low_byte,
            };
        }

        pub fn deinit(self: *Self) void {
            self.raw_code_line.deinit();
        }

        fn highByteToCtrl(self: *Self) c_int {
            return @as(c_int, @intCast(self.high_byte)) * SUNVOX_CTRL_MULTIPLIER;
        }

        fn lowByteToCtrl(self: *Self) c_int {
            return @as(c_int, @intCast(self.low_byte)) * SUNVOX_CTRL_MULTIPLIER;
        }
    };
}

test "VOXCOMMachineCode Test" {
    const test_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const high_byte: u8 = 0b00_100_000;
    const low_byte: u8 = 0b00_001_001;
    var raw_code_line = try String.init_with_contents(arena.allocator(), "ADDC A 9");
    defer raw_code_line.deinit();

    var machine_code = try VOXCOMMachineCode().init(raw_code_line, high_byte, low_byte);
    defer machine_code.deinit();

    try std.testing.expectEqualStrings("ADDC A 9", machine_code.raw_code_line.str());
    try std.testing.expectEqual(0b00_100_000, machine_code.high_byte);
    try std.testing.expectEqual(0b00_001_001, machine_code.low_byte);
    try std.testing.expectEqual(0x1000, machine_code.highByteToCtrl());
    try std.testing.expectEqual(0x480, machine_code.lowByteToCtrl());
}
