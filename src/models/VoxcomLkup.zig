const std = @import("std");
/// Here are all of the available opcodes in VOXCOM 1610:
/// It use 5 bits as opcode, and the remaining 11 bits for operands
///
/// -- ALU Operations
/// 00 000 000 00000000  NOP / NOTEY
/// 00 001 xxx xxxxxxxx  NAND Register A and B from the ALU
/// 00 010 xWx xxxxxxxx  Left shift, W indicates whether the operation requires a wrap
/// 00 011 xWx xxxxxxxx  Right shift, W indicates whether the operation requires a wrap
/// 00 100 Cxx xxxxxxxx  ADD Register A and B, result to Register S. C indicates if carry is required
/// 00 101 CBB BBBBBBBB  ADD Register A with a constant, result to Register S. C indicates if carry is required
/// 00 110 xxx xxxxxxxx  Perform 2's complement with Register A, result to Register S
/// 00 111 xxx xxxxxxxx  Swap High and Low byte of Register A, result to Register S
///
/// -- Memory Operations
/// 01 000 rrr rrrxxxxx  Pass two register data from the register bank into register A and B respectively
/// 01 001 rrr xxxxxxxx  Send the value from the result register to one of the registers in the register bank R[0-7]
/// 01 010 rrr dddddddd  Clear the specified register R[0-7], and assign a value into the low byte based on dddddddd
/// 01 011 rrr dddddddd  assign a value into the high byte based on dddddddd
///
/// RAMPAGE Mode: dividing the 64k word RAM into 256 pages, and the value of @@@@@@@@ is the index offset of the page
/// 01 100 rrr @@@@@@@@  RAMPAGE write mode: R[rrr] -> page[addr[@@@@@@@@]]
/// 01 101 rrr @@@@@@@@  RAMPAGE read mode:  page[addr[@@@@@@@@]] -> R[rrr]
///
/// Register Indirect Mode: accessing ram address based on the value stored on the register bank
/// 01 110 rrr RRRxxxxx  Indirect register mode: R[rrr] -> RAM[val_of(RRR)]
/// 01 111 rrr RRRxxxxx  Indirect register mode: RAM[val_of(RRR)] -> R[rrr]
///
/// Stack Mode: Currently not in uses because it is impossible to build a proper push and pop operation within a single CPU cycle
/// 10 000 rrr xxxxxxxx  Reserved
/// 10 001 rrr xxxxxxxx  Reserved
///
/// Misc Memory Operations
/// 10 010 xxx kkkkkkkk  Set the RAMPAGE with kkkkkkkk
/// 10 011 rrr xxxxxxxx  Current Rom Address (aka the current program counter value) into R[rrr]
///
/// -- I/O Ports Operations
/// 10 100 rrr pppppppp  Write Register values R[rrr] to I/O ports IO[pppppppp]
/// 10 101 rrr pppppppp  Read I/O ports IO[pppppppp] and write the value into a specified register R[rrr]
/// 10 110 xxx xxxxxxxx  Reserved
/// 10 111 xxx xxxxxxxx  Reserved
///
/// -- Jump and Misc
/// 11 000 sll llllllll  Direct jump mode: Unconditionally jump by l lines, s for directions
/// 11 001 rrr xxxxxxxx  Registers Jump mode: Jump to a given address stored in the specified register R[rrr]
/// 11 010 coe slllllll  Flag Jump mode: when any of the c (carry), o (overflow), or e (even) flags are enabled, it jumps by l lines if the condition met.
/// 11 011 leg slllllll  Comparator Jump mode: when any of the l (lesser), e (equal), or g (greater) flags are enabled, it jumps by l lines if the condition met.
/// 11 100 xxx xxxxxxxx  Reserved
/// 11 101 xxx xxxxxxxx  Reserved
/// 11 110 xxx xxxxxxxx  Reserved
///
/// -- End
/// 11 111 xxx xxxxxxxx  Halt the program
pub const NOP = "NOP"; // 0b00_000_000,
pub const NAND = "NAND"; // 0b00_001_000,
pub const LS = "LS"; // 0b00_010_000,
pub const LSW = "LSW"; // 0b00_010_010,
pub const RS = "RS"; // 0b00_011_000,
pub const RSW = "RSW"; // 0b00_011_010,
pub const ADD = "ADD"; // 0b00_100_000,
pub const ADDC = "ADDC"; // 0b00_100_100,
pub const TCOM = "TCOM"; // 0b00_110_000,
pub const BSWP = "BSWP"; // 0b00_111_000,
pub const MOV = "MOV"; // 0b01_000_000, // Includes all addressing mode
pub const STPG = "STPG"; // 0b10_010_000,
pub const ROMA = "ROMA"; // 0b10_011_000,
pub const PORT = "PORT"; // 0b10_100_000,
pub const JMP = "JMP"; // 0b11_000_000,
pub const JMPR = "JMPR"; // 0b11_001_000,
pub const JCR = "JCR"; // 0b11_010_100,
pub const JOV = "JOV"; // 0b11_010_010,
pub const JEVN = "JEVN"; // 0b11_010_001,
pub const JLZ = "JLZ"; // 0b11_011_100,
pub const JLEZ = "JLEZ"; // 0b11_011_110,
pub const JEZ = "JEZ"; // 0b11_011_010,
pub const JNZ = "JNZ"; // 0b11_011_101,
pub const JGZ = "JGZ"; // 0b11_011_001,
pub const JGEZ = "JGEZ"; // 0b11_011_011,
pub const END = "END"; // 0b11_111_000,
pub const NOTEY = "NOTEY"; // 0b00_000_000,
pub const RAMPAGE = "RAMPAGE"; // 0b10_010_000,

// Hidden operations, not available for users
// ALU
pub const ADD_CONST_MODE: u8 = 0b00_001_000;

// Jumps
pub const NEG_JMP_DIR: u8 = 0b00_000_100;
pub const NEG_JMP_FLG: u8 = 0b10_000_000;

// Write from Register
pub const MOV_AB_FROM_R: u8 = 0b01_000_000;
pub const MOV_RAMPAGE_FROM_R: u8 = 0b01_100_000;
pub const MOV_IR_FROM_R: u8 = 0b01_110_000;

// Write to Register
pub const MOV_R_FROM_S: u8 = 0b01_001_000;
pub const MOV_CONST_LOW: u8 = 0b01_010_000;
pub const MOV_CONST_HIGH: u8 = 0b01_011_000;
pub const MOV_R_FROM_RAMPAGE: u8 = 0b01_101_000;
pub const MOV_R_FROM_IR: u8 = 0b01_111_000;

// ALL or Nothing
pub const ALL_ZEROS: u8 = 0b00_000_000;
pub const ALL_ONES: u8 = 0b11_111_111;

// Operand limits
pub const LIMIT_ADD: u16 = 1023;
pub const LIMIT_MOV: u16 = 255;
pub const LIMIT_PORT: u16 = 255;
pub const LIMIT_JMP_DIR: u16 = 1023;
pub const LIMIT_JMP_FLG: u16 = 127;
pub const LIMIT_MOV_ADDR: u16 = 255;

const slice = [_]struct { []const u8, u8 }{
    .{ NOP, 0b00_000_000 },
    .{ NOTEY, 0b00_000_000 },
    .{ NAND, 0b00_001_000 },
    .{ LS, 0b00_010_000 },
    .{ LSW, 0b00_010_010 },
    .{ RS, 0b00_011_000 },
    .{ RSW, 0b00_011_010 },
    .{ ADD, 0b00_100_000 },
    .{ ADDC, 0b00_100_100 },
    .{ TCOM, 0b00_110_000 },
    .{ BSWP, 0b00_111_000 },
    .{ MOV, 0b01_000_000 },
    .{ STPG, 0b10_010_000 },
    .{ RAMPAGE, 0b10_010_000 },
    .{ ROMA, 0b10_011_000 },
    .{ PORT, 0b10_100_000 },
    .{ JMP, 0b11_000_000 },
    .{ JMPR, 0b11_001_000 },
    .{ JCR, 0b11_010_100 },
    .{ JOV, 0b11_010_010 },
    .{ JEVN, 0b11_010_001 },
    .{ JLZ, 0b11_011_100 },
    .{ JLEZ, 0b11_011_110 },
    .{ JEZ, 0b11_011_010 },
    .{ JNZ, 0b11_011_101 },
    .{ JGZ, 0b11_011_001 },
    .{ JGEZ, 0b11_011_011 },
    .{ END, 0b11_111_000 },
};

pub const lkup = std.StaticStringMap(u8).initComptime(slice);

pub fn contains(code_fragment: []const u8) ?u8 {
    return lkup.get(code_fragment);
}

pub fn isALUOperation(code_fragment: []const u8) bool {
    if (lkup.get(code_fragment)) |code| {
        return if (code & 0b11_000_000 == 0 and code & 0b00_111_000 != 0) true else false;
    }
    return false;
}

pub fn isJumpOperation(code_fragment: []const u8) bool {
    if (lkup.get(code_fragment)) |code| {
        return if (code & 0b11_000_000 == 0b11_000_000 and code & 0b00_111_000 != 0b00_111_000) true else false;
    }
    return false;
}

test "opcode lookup initialization" {
    var opcodeA = "ADD";
    const sliceA = opcodeA[0..opcodeA.len];
    try std.testing.expectEqual(0b00_100_000, contains(sliceA));

    var opcodeB = "ADHD";
    const sliceB = opcodeB[0..opcodeB.len];
    try std.testing.expectEqual(null, contains(sliceB));
}

test "opcode lookup is alu operation check" {
    try std.testing.expectEqual(true, isALUOperation(NAND));
    try std.testing.expectEqual(true, isALUOperation(LS));
    try std.testing.expectEqual(true, isALUOperation(TCOM));
    try std.testing.expectEqual(true, isALUOperation(BSWP));

    try std.testing.expectEqual(false, isALUOperation(NOP));
    try std.testing.expectEqual(false, isALUOperation(MOV));
    try std.testing.expectEqual(false, isALUOperation(END));
}

test "opcode lookup is jump operation check" {
    try std.testing.expectEqual(true, isJumpOperation(JMP));
    try std.testing.expectEqual(true, isJumpOperation(JMPR));
    try std.testing.expectEqual(true, isJumpOperation(JGZ));
    try std.testing.expectEqual(true, isJumpOperation(JGEZ));

    try std.testing.expectEqual(false, isJumpOperation(NOP));
    try std.testing.expectEqual(false, isJumpOperation(MOV));
    try std.testing.expectEqual(false, isJumpOperation(END));
}
