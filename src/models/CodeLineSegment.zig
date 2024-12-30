const std = @import("std");
const String = @import("string").String;
const Opcodes = @import("VoxcomLkup.zig");
const utils = @import("../process/CompilerUtils.zig");

pub fn CodeLineSegment() type {
    return struct {
        const Self = @This();

        raw_code_line: ?String, // retain the original assembly line, for error prompting
        prelabels: std.ArrayList(String), // location of the labels
        opcode: ?String, // the operation type
        operands: std.ArrayList(String), // the properties for the opcode
        postlabel: ?String, // the labels that is going to jump into
        file_ref_index: u32, // index of the file, used for error prompting
        compile_index: u32, // index of the compiled program, used for generating machine codes
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .raw_code_line = null,
                .prelabels = std.ArrayList(String).init(allocator),
                .opcode = null,
                .operands = std.ArrayList(String).init(allocator),
                .postlabel = null,
                .file_ref_index = 0,
                .compile_index = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            // raw code line
            if (self.raw_code_line != null) {
                self.raw_code_line.?.deinit();
            }

            // opcodes
            if (self.opcode != null) {
                self.opcode.?.deinit();
            }

            // post-label
            if (self.postlabel != null) {
                self.postlabel.?.deinit();
            }

            // pre-labels
            for (0..self.prelabels.items.len) |i| {
                self.prelabels.items[i].deinit();
            }
            self.prelabels.deinit();

            // oprands
            for (0..self.operands.items.len) |i| {
                self.operands.items[i].deinit();
            }
            self.operands.deinit();
        }

        pub fn loadRawCodeLine(self: *Self, raw_code_line: String, file_ref_index: u32, compile_index: u32) !void {
            self.raw_code_line = try raw_code_line.clone();
            self.file_ref_index = file_ref_index;
            self.compile_index = compile_index;
        }

        pub fn splitCodes(self: *Self) !void {
            var raw_cloned = try self.raw_code_line.?.clone();
            defer raw_cloned.deinit();
            _ = try raw_cloned.replace(",", " ");
            _ = try raw_cloned.replace("\t", " ");
            _ = try raw_cloned.replace("\r", " ");

            const split_raw_cloned = try raw_cloned.splitAll(" ");
            var found_opcode = false;
            for (split_raw_cloned) |code_frag| {
                const code_frag_str = try String.init_with_contents(self.allocator, code_frag);

                // ignore any empty strings, as they have no effect on the programs
                if (std.mem.eql(u8, code_frag, "")) continue;

                // identify if the current code fragment is an opcode,
                if (Opcodes.lkup.has(code_frag)) {
                    found_opcode = true;
                    self.opcode = code_frag_str;
                    continue;
                }

                // everything before opcodes must be a label
                if (!found_opcode) {
                    try self.prelabels.append(code_frag_str);
                    continue;
                }

                // every non numerical value after jump operations except Register Indirect Jump must be a post label
                if (self.isPostLabel(code_frag)) {
                    self.postlabel = code_frag_str;
                    continue;
                }

                // otherwise, they are all operands
                try self.operands.append(code_frag_str);
            }
        }

        fn isPostLabel(self: *Self, code_frag: []const u8) bool {
            // Register Indirect Jump is the only jump that doesn't use a label, thus exclude that.
            const jmpr_code = Opcodes.JMPR;

            if (self.opcode == null) return false;

            const is_jump: bool = if (self.opcode.?.str()[0] == 'J') true else false;

            if (is_jump and !std.mem.eql(u8, self.opcode.?.str(), jmpr_code) and !utils.is_number(code_frag)) {
                return true;
            } else {
                return false;
            }
        }
    };
}

test "Code Line Segment Init" {
    var command = try String.init_with_contents(std.testing.allocator, "ADD A B");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 0, 1);
    try std.testing.expectEqual(0, line.file_ref_index);
    try std.testing.expectEqual(1, line.compile_index);
    try std.testing.expectEqualStrings("ADD A B", line.raw_code_line.?.str());
}

test "Code Line Segment - Single Prelabels" {
    var command = try String.init_with_contents(std.testing.allocator, "LABEL:");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 2, 3);
    try line.splitCodes();

    try std.testing.expectEqual(1, line.prelabels.items.len);
    try std.testing.expectEqualStrings("LABEL:", line.prelabels.items[0].str());
}

test "Code Line Segment - Multi Prelabels" {
    var command = try String.init_with_contents(std.testing.allocator, "TEST1: TEST2:");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 2, 3);
    try line.splitCodes();

    try std.testing.expectEqual(2, line.prelabels.items.len);
    try std.testing.expectEqualStrings("TEST1:", line.prelabels.items[0].str());
    try std.testing.expectEqualStrings("TEST2:", line.prelabels.items[1].str());
}

test "Code Line Segment - Standard Operation" {
    var command = try String.init_with_contents(std.testing.allocator, "NAND \tA B");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqualStrings("NAND", line.opcode.?.str());

    try std.testing.expectEqual(2, line.operands.items.len);
    try std.testing.expectEqualStrings("A", line.operands.items[0].str());
    try std.testing.expectEqualStrings("B", line.operands.items[1].str());
}

test "Code Line Segment - Jump With Index" {
    var command = try String.init_with_contents(std.testing.allocator, "JEZ -127");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqualStrings("JEZ", line.opcode.?.str());

    try std.testing.expectEqual(1, line.operands.items.len);
    try std.testing.expectEqualStrings("-127", line.operands.items[0].str());
}

test "Code Line Segment - Jump With Label" {
    var command = try String.init_with_contents(std.testing.allocator, "JEVN TEST3");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqualStrings("JEVN", line.opcode.?.str());
    try std.testing.expectEqual(0, line.operands.items.len);
    try std.testing.expectEqualStrings("TEST3", line.postlabel.?.str());
}

test "Code Line Segment - Jump With Label B" {
    var command = try String.init_with_contents(std.testing.allocator, "JMP BACKWARD");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqualStrings("JMP", line.opcode.?.str());
    try std.testing.expectEqual(0, line.operands.items.len);
    try std.testing.expectEqualStrings("BACKWARD", line.postlabel.?.str());
}

test "Code Line Segment - Complex" {
    var command = try String.init_with_contents(std.testing.allocator, "TEST3:\tTEST4:\tMOV  AB \t R7   \t\t  R7");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqual(2, line.prelabels.items.len);
    try std.testing.expectEqualStrings("TEST3:", line.prelabels.items[0].str());
    try std.testing.expectEqualStrings("TEST4:", line.prelabels.items[1].str());

    try std.testing.expectEqualStrings("MOV", line.opcode.?.str());
    try std.testing.expectEqual(3, line.operands.items.len);
    try std.testing.expectEqualStrings("AB", line.operands.items[0].str());
    try std.testing.expectEqualStrings("R7", line.operands.items[1].str());
    try std.testing.expectEqualStrings("R7", line.operands.items[2].str());
}

test "Code Line Segment - Binary Number" {
    var command = try String.init_with_contents(std.testing.allocator, "ADD\t\tA  0B00_0001_0100");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqualStrings("ADD", line.opcode.?.str());
    try std.testing.expectEqual(2, line.operands.items.len);
    try std.testing.expectEqualStrings("A", line.operands.items[0].str());
    try std.testing.expectEqualStrings("0B00_0001_0100", line.operands.items[1].str());
}

test "Code Line Segment - Hex Number" {
    var command = try String.init_with_contents(std.testing.allocator, "ADD  A\t\t0X28");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqualStrings("ADD", line.opcode.?.str());
    try std.testing.expectEqual(2, line.operands.items.len);
    try std.testing.expectEqualStrings("A", line.operands.items[0].str());
    try std.testing.expectEqualStrings("0X28", line.operands.items[1].str());
}

test "Code Line Segment - Garbage Data" { // this is necessary because
    var command = try String.init_with_contents(std.testing.allocator, "WHAT PLEASE ANSWER PLEASE");
    defer command.deinit();

    var line = CodeLineSegment().init(std.testing.allocator);
    defer line.deinit();

    try line.loadRawCodeLine(command, 3, 4);
    try line.splitCodes();

    try std.testing.expectEqual(null, line.opcode);
    try std.testing.expectEqual(0, line.operands.items.len);
    try std.testing.expectEqualStrings("WHAT", line.prelabels.items[0].str());
    try std.testing.expectEqualStrings("PLEASE", line.prelabels.items[1].str());
    try std.testing.expectEqualStrings("ANSWER", line.prelabels.items[2].str());
    try std.testing.expectEqualStrings("PLEASE", line.prelabels.items[3].str());
}
