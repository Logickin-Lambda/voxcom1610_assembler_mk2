const std = @import("std");

/// The assembler support multiple number format, thus
///
/// 10
/// 1_2_34_5
/// 0xfF
/// 0X8_9
/// 0b11_0
/// 0B111
///
/// are all considered as valid inputs
pub fn is_number(input: []const u8) bool {
    _ = std.fmt.parseInt(i32, input, 0) catch {
        return false;
    };

    // Intuitively, my voxasm number formatting is identical to zig,
    // so if zig fails to format the number, I can squarely return false;
    // otherwise true.
    return true;
}

test "basic numerical detection test" {
    // decimal
    try std.testing.expect(is_number("10"));
    try std.testing.expect(is_number("-10"));
    try std.testing.expect(is_number("1_0"));

    try std.testing.expect(!is_number("a"));

    // Hexidecimal
    try std.testing.expect(is_number("0x0F"));
    try std.testing.expect(is_number("0X0_F"));
    try std.testing.expect(!is_number("0xNoTeY"));

    // binary
    try std.testing.expect(is_number("0b1010"));
    try std.testing.expect(is_number("0B01__01"));
    try std.testing.expect(!is_number("0b1234"));
    try std.testing.expect(!is_number("0bDd05"));
}
