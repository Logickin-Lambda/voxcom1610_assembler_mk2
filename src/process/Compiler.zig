const std = @import("std");
const String = @import("string").String;
const cls = @import("../models/CodeLineSegment.zig");
const mxhc = @import("../models/VOXCOMMachineCode.zig");
const lkup = @import("../models/VoxcomLkup.zig");
const util = @import("CompilerUtils.zig");

pub const COMPILER_ERR = error{
    DUPLICATED_LABELS,
    UNMATCHED_LABEL_FOR_JUMP,
    INVALID_OPCODE,
    WRONG_NUMBER_OF_OPERANDS,
    INVALID_NUMBER,
    JUMP_STEP_EXCEEDED,
    NUMBER_FORMAT_NOT_SUPPORTED,
    INVALID_REGISTER,
    UNKNOWN_ADDRESSING_MODE,
};

pub fn Compiler() type {
    return struct {
        const Self = @This();
        // we don't need a copy for the CodeLineSegment because it is read only,
        // so I decided to pass a reference rather than the whole object.
        source_codes: *std.ArrayList(cls.CodeLineSegment()),
        compiled_programs: std.ArrayList(mxhc.VOXCOMMachineCode()),
        label_lkup: std.StringHashMap(u32),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, source_codes: *std.ArrayList(cls.CodeLineSegment())) Self {
            return Self{
                .allocator = allocator,
                .compiled_programs = std.ArrayList(mxhc.VOXCOMMachineCode()).init(allocator),
                .source_codes = source_codes,
                .label_lkup = std.StringHashMap(u32).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.compiled_programs.deinit();
            self.label_lkup.deinit();
        }

        pub fn compile(self: *Self) !void {
            try self.generateLabelLkup();

            var compileResult = true;

            for (self.source_codes.items) |code_line| {
                if (self.translateCodeLine(code_line)) continue else |_| {
                    compileResult = false;
                }
            }
        }

        fn translateCodeLine(self: *Self, code_line: cls.CodeLineSegment()) !void {
            if (code_line.opcode) |opcode| {
                if (lkup.isALUOperation(opcode.str())) {
                    try self.compiled_programs.append(try self.translateALUtypeOperation(code_line));
                } else if (lkup.isJumpOperation(opcode.str())) {
                    try self.compiled_programs.append(try self.translateJumpTypeOperation(code_line));
                } else if (opcode.cmp(lkup.MOV)) {
                    try self.compiled_programs.append(try self.translateMovTypeOperation(code_line));
                } else if (opcode.cmp(lkup.PORT)) {
                    try self.compiled_programs.append(try self.translatePortTypeOperation(code_line));
                } else if (opcode.cmp(lkup.ROMA)) {
                    try self.compiled_programs.append(try self.translateRomAddressExtractionOperation(code_line));
                } else if (opcode.cmp(lkup.STPG) or opcode.cmp(lkup.RAMPAGE)) {
                    try self.compiled_programs.append(try self.unlashRAMPAGEOperation(code_line));
                } else if (opcode.cmp(lkup.NOP) or opcode.cmp(lkup.NOTEY)) {
                    try self.compiled_programs.append(mxhc.VOXCOMMachineCode().init(&code_line.raw_code_line.?, lkup.NOP));
                } else if (opcode.cmp(lkup.END)) {
                    try self.compiled_programs.append(mxhc.VOXCOMMachineCode().init(&code_line.raw_code_line.?, lkup.END));
                }
            } else {
                // if apparently not presents on the line, check if they only contains labels
                for (code_line.prelabels.items) |prelabel| {
                    if (prelabel.find(":") == null) {
                        std.log.err("Invalid Opcode or Label: {s} at line {d}: {s}\n", .{ prelabel.str(), code_line.file_ref_index, code_line.raw_code_line.?.str() });
                        return COMPILER_ERR.INVALID_OPCODE;
                    }
                }

                // If they are all proper label, insert a NOP operation
                try self.compiled_programs.append(mxhc.VOXCOMMachineCode().init(&code_line.raw_code_line.?, lkup.NOP));
            }
        }

        fn translateALUtypeOperation(_: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {

            // Non-Add operation are simple, which we only need the opcode
            // VOXASM has larger margin of error which any operand after these ALU opcode are ignored.
            // Thus even if you have added something after these opcodes, it is still a pass for the assembler (except for ADD and ADDC)
            if (!(code_line.opcode.?.cmp(lkup.ADDC) or code_line.opcode.?.cmp(lkup.ADD))) {
                return mxhc.VOXCOMMachineCode().init(&code_line.raw_code_line.?, code_line.opcode.?.str());
            }

            // For ADDC and ADD, we need to ensure:
            // - there must be two operands: A B or A Constant
            // - the constant is never goes beyond 1023
            // - wrong number of operand leads to an error
            const opcode_str = code_line.opcode.?.str();
            const operands_cnt = code_line.operands.items.len;
            if (operands_cnt != 2) {
                std.log.err(
                    "Invalid Oprands for {s} at line {d}: {s}\nPlease Ensure the format for {s} is either:\n{s} A B\n{s} A 69\n",
                    .{ opcode_str, code_line.file_ref_index, code_line.raw_code_line.?.str(), opcode_str, opcode_str, opcode_str },
                );
                return COMPILER_ERR.WRONG_NUMBER_OF_OPERANDS;
            }

            const constant_str: String = code_line.operands.items[1];

            if (constant_str.cmp("B")) {
                return mxhc.VOXCOMMachineCode().init(&code_line.raw_code_line.?, opcode_str);
            } else if (!util.is_number(constant_str.str())) {
                std.log.err("Invaild {s} constant for {s} at line {d}: {s}\n", .{ constant_str.str(), opcode_str, code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_NUMBER;
            }

            const constant = try std.fmt.parseInt(u16, constant_str.str(), 0);

            if (constant > lkup.LIMIT_ADD) {
                std.log.err("Value {d} is too large for {s} (0-1023) at line {d}: {s}\n", .{ constant, opcode_str, code_line.file_ref_index, code_line.raw_code_line.?.str() });
            }

            const high_byte = lkup.contains(opcode_str).? + lkup.ADD_CONST_MODE + @as(u8, @intCast(constant >> 8));
            const low_byte = @as(u8, @intCast(constant & lkup.ALL_ONES));

            return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
        }

        fn translateJumpTypeOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            if (!((code_line.operands.items.len == 1 and code_line.postlabel == null) or (code_line.operands.items.len == 0 and code_line.postlabel != null))) {
                const opcode_str = code_line.opcode.?.str();
                std.log.err(
                    "Invalid Oprands for {s} at line {d}: {s}\nPlease Ensure the format for {s} is either:\n{s} LABEL\n{s} 69\nJMPR R0 (for indirect register jump only)\n",
                    .{ opcode_str, code_line.file_ref_index, code_line.raw_code_line.?.str(), opcode_str, opcode_str, opcode_str },
                );
                return COMPILER_ERR.UNMATCHED_LABEL_FOR_JUMP;
            }

            // Since the operation can be complex, I have break these into multiple types as shown:
            if (code_line.opcode.?.cmp(lkup.JMPR)) {
                return self.translateJumpByRegisterTypeOperation(code_line);
            }

            // After that, we may determine if the operation is based on labels or absolute mode
            if (code_line.postlabel != null) {
                // Label Mode
                return self.translateJumpByLabelTypeOperation(code_line);
            } else {
                // Absolute Mode
                return self.translateJumpByAbsoluteTypeOperation(code_line);
            }
        }

        fn translateJumpByRegisterTypeOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            // if the operand is not started from "R", throw error
            const opcode_str = code_line.opcode.?.str();
            const register_index = try self.isValidRegister(code_line, code_line.operands.items[0]);

            const high_byte = lkup.contains(opcode_str).? + register_index;
            const low_byte = lkup.ALL_ZEROS;

            return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
        }

        fn translateJumpByLabelTypeOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            // non-existent label is skipped
            const label_index = self.label_lkup.get(code_line.postlabel.?.str());
            if (label_index == null) {
                std.log.err("Cannot find the destination for Label {s} at line {d}: {s}\n", .{ code_line.postlabel.?.str(), code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.UNMATCHED_LABEL_FOR_JUMP;
            }

            // calculate the step size, and because the jump step also includes the natural program counter step,
            // we need to subtract 1 to cancel the program counter.
            var jump_step = @as(i32, @intCast(label_index.?)) - @as(i32, @intCast(code_line.compile_index)) - 1;
            return self.constructJumpMachineCode(code_line, &jump_step);
        }

        fn translateJumpByAbsoluteTypeOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            // to reduce confusion, Hex and binary is not allowed for jump command, for example
            // is 0b10000000 -128 in signed or 128 in unsigned?
            var jump_step_str = code_line.operands.items[0];
            if (jump_step_str.startsWith("0B") or jump_step_str.startsWith("0X") or jump_step_str.startsWith("0O")) {
                std.log.err("Binary and Hexadecimal number doesn't support for {s} at line {d}: {s}\n", .{ code_line.opcode.?.str(), code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.NUMBER_FORMAT_NOT_SUPPORTED;
            }

            if (!util.is_number(jump_step_str.str())) {
                std.log.err("Invaild {s} constant for {s} at line {d}: {s}\n", .{ jump_step_str.str(), code_line.opcode.?.str(), code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_NUMBER;
            }

            var jump_step = try std.fmt.parseInt(i32, jump_step_str.str(), 0);
            return self.constructJumpMachineCode(code_line, &jump_step);
        }

        fn constructJumpMachineCode(_: *Self, code_line: cls.CodeLineSegment(), jump_step: *i32) !mxhc.VOXCOMMachineCode() {
            const opcode_str = code_line.opcode.?;
            var is_negative: bool = false;

            if (jump_step.* < 0) {
                is_negative = true;
                jump_step.* *= -1;
            }

            // JMP require special handling because it is the only jump operation that has a 10 bit jump size
            if (opcode_str.cmp(lkup.JMP)) {
                if (jump_step.* > lkup.LIMIT_JMP_DIR) {
                    std.log.err("Jump step for JMP exceeded (-1023 - 1023) at line {d}: {s}\n", .{ code_line.file_ref_index, code_line.raw_code_line.?.str() });
                    return COMPILER_ERR.JUMP_STEP_EXCEEDED;
                }

                const neg_flag = if (is_negative) lkup.NEG_JMP_DIR else lkup.ALL_ZEROS;

                const high_byte = lkup.contains(opcode_str.str()).? + @as(u8, @intCast(jump_step.* >> 8)) + neg_flag;
                const low_byte = @as(u8, @intCast(jump_step.* & lkup.ALL_ONES));

                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            } else {
                if (jump_step.* > lkup.LIMIT_JMP_FLG) {
                    std.log.err("Jump step for {s} exceeded (-127 - 127) at line {d}: {s}\n", .{ code_line.opcode.?.str(), code_line.file_ref_index, code_line.raw_code_line.?.str() });
                    return COMPILER_ERR.JUMP_STEP_EXCEEDED;
                }

                const neg_flag = if (is_negative) lkup.NEG_JMP_FLG else lkup.ALL_ZEROS;

                const high_byte = lkup.contains(opcode_str.str()).?;
                const low_byte = @as(u8, @intCast(jump_step.*)) + neg_flag;

                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            }
        }

        fn translateMovTypeOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            if (code_line.operands.items.len != 2 and code_line.operands.items.len != 3) {
                std.log.err(
                    "Invalid Oprands for MOV at line {d}: {s}\nPlease Ensure the format for MOV is either:\nMOV AB R0 R1\nMOV R0 S\nMOV R1 L255\nMOV R2 H255\nMOV @255 R3\nMOV R4 @255\nMOV @R5 R6\nMOV R7 @R0\n",
                    .{ code_line.file_ref_index, code_line.raw_code_line.?.str() },
                );
                return COMPILER_ERR.WRONG_NUMBER_OF_OPERANDS;
            }

            // if the first operand is start from R, it is a Register Write operation which
            // the first operand is the destination of the data write
            if (code_line.operands.items[0].startsWith("R")) {
                return self.translateRegWriteOperation(code_line);
            } else {
                return self.translateRegReadOperation(code_line);
            }
        }

        fn translateRegWriteOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {

            // validate and get the register index
            const register_index = try self.isValidRegister(code_line, code_line.operands.items[0]);

            // handle different addressing mode based on the prefix of the operand, starting from Solution Register Mode:
            // Solution Register to Register Bank [0..7]
            var source_oprand = code_line.operands.items[1];
            if (source_oprand.cmp("S")) {
                const high_byte = lkup.MOV_R_FROM_S + register_index;
                const low_byte = lkup.ALL_ZEROS;
                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            }

            // Constant Byte to Register Mode
            if (source_oprand.startsWith("L") or source_oprand.startsWith("H")) {
                const addr_str = source_oprand.str()[1..];
                const const_mode = if (source_oprand.startsWith("L")) lkup.MOV_CONST_LOW else lkup.MOV_CONST_HIGH;

                const addr = try self.isValidAddress(code_line, addr_str);

                const high_byte = const_mode + register_index;
                const low_byte = addr;
                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            }

            // Register Indirect Mode
            if (source_oprand.startsWith("@R")) {
                var register_operand: String = try source_oprand.clone();
                defer register_operand.deinit();

                _ = try register_operand.replace("@", "");

                const high_byte = lkup.MOV_R_FROM_IR + register_index;
                const low_byte = try self.isValidRegister(code_line, register_operand) << 5; // 00000111 -> 11100000;

                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            }

            // RAMPAGE Mode
            if (source_oprand.startsWith("@")) {
                var rampage_operand: String = try source_oprand.clone();
                defer rampage_operand.deinit();

                _ = try rampage_operand.replace("@", "");

                const high_byte = lkup.MOV_R_FROM_RAMPAGE + register_index;
                const low_byte = try self.isValidAddress(code_line, rampage_operand.str());

                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            } else {
                std.log.err("Unknown Addressing Mode at line {d}: {s}\n", .{ code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.UNKNOWN_ADDRESSING_MODE;
            }
        }

        fn translateRegReadOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {

            // validate and get the register index
            const register_index = try self.isValidRegister(code_line, code_line.operands.items[1]);
            var dest_operand = code_line.operands.items[0];

            // Register Bank to ALU Register
            if (dest_operand.cmp("AB")) {
                // for ALU B register, only
                const register_index_b = try self.isValidRegister(code_line, code_line.operands.items[2]);

                const high_byte = lkup.MOV_AB_FROM_R + register_index;
                const low_byte = register_index_b << 5; // 00000111 -> 11100000

                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            }

            // Register Indirect Mode
            if (dest_operand.startsWith("@R")) {
                var register_operand: String = try dest_operand.clone();
                defer register_operand.deinit();

                _ = try register_operand.replace("@", "");

                const high_byte = lkup.MOV_IR_FROM_R + register_index;
                const low_byte = try self.isValidRegister(code_line, register_operand) << 5; // 00000111 -> 11100000

                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            }

            // RAMPAGE Mode
            if (dest_operand.startsWith("@")) {
                var rampage_operand: String = try dest_operand.clone();
                defer rampage_operand.deinit();

                _ = try rampage_operand.replace("@", "");

                const high_byte = lkup.MOV_RAMPAGE_FROM_R + register_index;
                const low_byte = try self.isValidAddress(code_line, rampage_operand.str());

                return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
            } else {
                std.log.err("Unknown Addressing Mode at line {d}: {s}\n", .{ code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.UNKNOWN_ADDRESSING_MODE;
            }
        }

        fn translatePortTypeOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            const opcode_str = code_line.opcode;

            if (code_line.operands.items.len != 2) {
                std.log.err(
                    "Invalid Oprands for PORT at line {d}: {s}\nPlease Ensure the format for PORT is either:\nPORT 95 R0\nPORT R1 16\n",
                    .{ code_line.file_ref_index, code_line.raw_code_line.?.str() },
                );
                return COMPILER_ERR.WRONG_NUMBER_OF_OPERANDS;
            }

            // xnor comparison, if both of them prepend by R or none of them, both considered as invalid
            if (code_line.operands.items[0].startsWith("R") and code_line.operands.items[1].startsWith("R")) {
                std.log.err(
                    "Missing Port Address at line {d}: {s}",
                    .{ code_line.file_ref_index, code_line.raw_code_line.?.str() },
                );
                return COMPILER_ERR.INVALID_REGISTER;
            } else if (!code_line.operands.items[0].startsWith("R") and !code_line.operands.items[1].startsWith("R")) {
                std.log.err(
                    "Missing Register at line {d}: {s}",
                    .{ code_line.file_ref_index, code_line.raw_code_line.?.str() },
                );
                return COMPILER_ERR.INVALID_REGISTER;
            }

            const is_write = code_line.operands.items[0].startsWith("R");
            const source: usize = if (is_write) 0 else 1;
            const dest: usize = if (is_write) 1 else 0;
            const mode: u8 = if (is_write) 8 else 0;

            const register_index = try self.isValidRegister(code_line, code_line.operands.items[source]);

            const high_byte = lkup.contains(opcode_str.?.str()).? + mode + register_index;
            const low_byte = try self.isValidAddress(code_line, code_line.operands.items[dest].str());

            return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
        }

        fn translateRomAddressExtractionOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            const opcode_str = code_line.opcode;

            if (code_line.operands.items.len != 1) {
                std.log.err(
                    "Invalid Oprands for ROMA at line {d}: {s}\nPlease Ensure the format for ROMA:\nSTPG R7\n",
                    .{ code_line.file_ref_index, code_line.raw_code_line.?.str() },
                );

                return COMPILER_ERR.WRONG_NUMBER_OF_OPERANDS;
            }

            const high_byte = lkup.contains(opcode_str.?.str()).? + try self.isValidRegister(code_line, code_line.operands.items[0]);
            const low_byte = lkup.ALL_ZEROS;

            return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
        }

        fn unlashRAMPAGEOperation(self: *Self, code_line: cls.CodeLineSegment()) !mxhc.VOXCOMMachineCode() {
            const opcode_str = code_line.opcode;

            if (code_line.operands.items.len != 1) {
                std.log.err(
                    "Invalid Oprands for STPG/RAMPAGE at line {d}: {s}\nPlease Ensure the format for STPG/RAMPAGE is either:\nSTPG 19\nRAMPAGE 84\n",
                    .{ code_line.file_ref_index, code_line.raw_code_line.?.str() },
                );

                return COMPILER_ERR.WRONG_NUMBER_OF_OPERANDS;
            }

            const high_byte = lkup.contains(opcode_str.?.str()).?;
            const low_byte = try self.isValidAddress(code_line, code_line.operands.items[0].str());

            return mxhc.VOXCOMMachineCode().init_raw(&code_line.raw_code_line.?, high_byte, low_byte);
        }

        fn isValidAddress(_: *Self, code_line: cls.CodeLineSegment(), addr_str: []const u8) !u8 {
            if (!util.is_number(addr_str)) {
                std.log.err("Invaild Address Index {s} for {s} at line {d}: {s}\n", .{ addr_str, code_line.opcode.?.str(), code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_NUMBER;
            }

            if (std.fmt.parseInt(u8, addr_str, 0)) |addr| {
                return addr;
            } else |_| {
                std.log.err("Index out of bound for Constant Byte Mode (0..255) at line {d}: {s}\n", .{ code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_NUMBER;
            }
        }

        fn isValidRegister(_: *Self, code_line: cls.CodeLineSegment(), register_operand: String) !u8 {
            // if the operand is not started from "R", throw error
            var register = register_operand;
            const opcode_str = code_line.opcode.?.str();
            if (!register.startsWith("R")) {
                std.log.err("Missing Register for {s} at line {d}: {s}\n", .{ opcode_str, code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_REGISTER;
            } else if (register.size < 2) {
                std.log.err("Missing Register index for {s} at line {d}: {s}\n", .{ opcode_str, code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_REGISTER;
            }

            const register_index_str = register.str()[1..];
            if (!util.is_number(register_index_str)) {
                std.log.err("Invaild Register Index {s} for {s} at line {d}: {s}\n", .{ register_index_str, opcode_str, code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_REGISTER;
            }

            const register_index = std.fmt.parseInt(u8, register_index_str, 0) catch 255;
            if (register_index > 7) {
                std.log.err("Register {s} is not available for VOXCOM 1610 (R0-R7) at line {d}: {s}\n", .{ register_index_str, code_line.file_ref_index, code_line.raw_code_line.?.str() });
                return COMPILER_ERR.INVALID_REGISTER;
            }

            return register_index;
        }

        fn generateLabelLkup(self: *Self) !void {
            for (self.source_codes.items) |code_line_segements| {
                for (code_line_segements.prelabels.items) |prelabel| {

                    // remove the colon for the lookup
                    // Every labels must end with a colon, so this can used for detect
                    // if the line contains a mistyped opcode
                    var prelabel_clone: String = try prelabel.clone();
                    _ = try prelabel_clone.replace(":", "");

                    if (prelabel_clone.isEmpty()) return;

                    // throws an error there is a duplicated labels
                    if (self.label_lkup.contains(prelabel_clone.str())) {
                        std.log.err("Duplicated label found: {s} at line {d}: {s}\n", .{ prelabel_clone.str(), code_line_segements.file_ref_index, code_line_segements.raw_code_line.?.str() });
                        return COMPILER_ERR.DUPLICATED_LABELS;
                    } else {
                        try self.label_lkup.put(prelabel_clone.str(), code_line_segements.compile_index);
                    }
                }
            }
        }
    };
}

test "Compilier Init test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var line1 = cls.CodeLineSegment().init(arena.allocator());
    defer line1.deinit();

    var line1_raw = try String.init_with_contents(arena.allocator(), "MOV AB R0 R1");
    defer line1_raw.deinit();

    try line1.loadRawCodeLine(line1_raw, 0, 0);
    try line1.splitCodes();

    var source_code = std.ArrayList(cls.CodeLineSegment()).init(arena.allocator());
    defer source_code.deinit();

    try source_code.append(line1);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();
}

fn generateSource(allocator: std.mem.Allocator, assembly_lines: []String) !std.ArrayList(cls.CodeLineSegment()) {
    var source_code = std.ArrayList(cls.CodeLineSegment()).init(allocator);

    for (0..assembly_lines.len) |i| {
        var code_line_seg = cls.CodeLineSegment().init(allocator);

        try code_line_seg.loadRawCodeLine(assembly_lines[i], @as(u32, @intCast(i)), @as(u32, @intCast(i)));
        try code_line_seg.splitCodes();

        try source_code.append(code_line_seg);
    }

    return source_code;
}

test "Compilier Label test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    // Load the raw asm codes for testing
    var raw_code_line = [_]String{ undefined, undefined };

    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "LABEL:");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "TEST1: TEST2: TEST3:");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..raw_code_line.len]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // verify keys
    try std.testing.expect(compiler.label_lkup.contains("LABEL"));
    try std.testing.expect(compiler.label_lkup.contains("TEST1"));
    try std.testing.expect(compiler.label_lkup.contains("TEST2"));
    try std.testing.expect(compiler.label_lkup.contains("TEST3"));

    // verify values
    try std.testing.expectEqual(0, compiler.label_lkup.get("LABEL").?);
    try std.testing.expectEqual(1, compiler.label_lkup.get("TEST1").?);
    try std.testing.expectEqual(1, compiler.label_lkup.get("TEST2").?);
    try std.testing.expectEqual(1, compiler.label_lkup.get("TEST3").?);

    // verify machine code: both high and low byte should be 0 (NOP)
    try std.testing.expectEqual(0, compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(0, compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(0, compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(0, compiler.compiled_programs.items[1].low_byte);
}

test "Compilier Duplicated Label test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line = [2]String{ undefined, undefined };
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "LABEL:");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "LABEL:");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try std.testing.expectError(COMPILER_ERR.DUPLICATED_LABELS, compiler.compile());
}

// No longer need for now because instead of throwing error out right after finding an error,
// the compiler log all the errors all at once, and throw an generic error at the end.
// test "Compilier Unknown Failing Opcode test" {
//     // Initialization
//     const testing_allocator = std.testing.allocator;
//     var arena = std.heap.ArenaAllocator.init(testing_allocator);
//     defer arena.deinit();

//     var raw_code_line = [2]String{ undefined, undefined };
//     raw_code_line[0] = try String.init_with_contents(arena.allocator(), "LABEL: ");
//     raw_code_line[1] = try String.init_with_contents(arena.allocator(), "WHAT A B");

//     var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

//     // Test starts from here
//     var compiler = Compiler().init(arena.allocator(), &source_code);
//     defer compiler.deinit();

//     try std.testing.expectError(COMPILER_ERR.INVALID_OPCODE, compiler.compile());
// }

test "Compilier NOP test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line = [_]String{undefined};
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "NOP ");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    try std.testing.expectEqual(0, compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(0, compiler.compiled_programs.items[0].low_byte);
}

test "Compilier ALU Operations test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [20]String = .{undefined} ** 20;
    // Operand-less operations
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "NAND ");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "NAND A B");
    raw_code_line[2] = try String.init_with_contents(arena.allocator(), "LS A B");
    raw_code_line[3] = try String.init_with_contents(arena.allocator(), "LSW ");
    raw_code_line[4] = try String.init_with_contents(arena.allocator(), "RS ");
    raw_code_line[5] = try String.init_with_contents(arena.allocator(), "RSW A B ");
    raw_code_line[6] = try String.init_with_contents(arena.allocator(), "TCOM ");
    raw_code_line[7] = try String.init_with_contents(arena.allocator(), "BSWP ");
    // ADD operations
    raw_code_line[8] = try String.init_with_contents(arena.allocator(), "ADD A B");
    raw_code_line[9] = try String.init_with_contents(arena.allocator(), "ADD A 0");
    raw_code_line[10] = try String.init_with_contents(arena.allocator(), "ADD A 202");
    raw_code_line[11] = try String.init_with_contents(arena.allocator(), "ADD A 0B10101100");
    raw_code_line[12] = try String.init_with_contents(arena.allocator(), "ADD A 0x5A");
    raw_code_line[13] = try String.init_with_contents(arena.allocator(), "ADD A 1023");
    // ADDC operations
    raw_code_line[14] = try String.init_with_contents(arena.allocator(), "ADDC A B");
    raw_code_line[15] = try String.init_with_contents(arena.allocator(), "ADDC A 0");
    raw_code_line[16] = try String.init_with_contents(arena.allocator(), "ADDC A 202");
    raw_code_line[17] = try String.init_with_contents(arena.allocator(), "ADDC A 0B10101100");
    raw_code_line[18] = try String.init_with_contents(arena.allocator(), "ADDC A 0x5A");
    raw_code_line[19] = try String.init_with_contents(arena.allocator(), "ADDC A 1023");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // Operand-less operations
        .{ 0b00_001_000, 0b00_000_000 }, // NAND
        .{ 0b00_001_000, 0b00_000_000 }, // NAND A B
        .{ 0b00_010_000, 0b00_000_000 }, // LS A B
        .{ 0b00_010_010, 0b00_000_000 }, // LSW
        .{ 0b00_011_000, 0b00_000_000 }, // RS
        .{ 0b00_011_010, 0b00_000_000 }, // RSW A B
        .{ 0b00_110_000, 0b00_000_000 }, // TCOM
        .{ 0b00_111_000, 0b00_000_000 }, // BSWP
        // ADD operations
        .{ 0b00_100_000, 0b00_000_000 }, // ADD A B
        .{ 0b00_101_000, 0b00_000_000 }, // ADD A 0
        .{ 0b00_101_000, 0b11_001_010 }, // ADD A 202
        .{ 0b00_101_000, 0b10_101_100 }, // ADD A 0B10101100
        .{ 0b00_101_000, 0b01_011_010 }, // ADD A 0x5A
        .{ 0b00_101_011, 0b11_111_111 }, // ADD A 1023
        // ADDC operations
        .{ 0b00_100_100, 0b00_000_000 }, // ADDC A B
        .{ 0b00_101_100, 0b00_000_000 }, // ADDC A 0
        .{ 0b00_101_100, 0b11_001_010 }, // ADDC A 202
        .{ 0b00_101_100, 0b10_101_100 }, // ADDC A 0B10101100
        .{ 0b00_101_100, 0b01_011_010 }, // ADDC A 0x5A
        .{ 0b00_101_111, 0b11_111_111 }, // ADDC A 1023
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    // Operand-less operations
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
    try std.testing.expectEqual(control_result[2][0], compiler.compiled_programs.items[2].high_byte);
    try std.testing.expectEqual(control_result[2][1], compiler.compiled_programs.items[2].low_byte);
    try std.testing.expectEqual(control_result[3][0], compiler.compiled_programs.items[3].high_byte);
    try std.testing.expectEqual(control_result[3][1], compiler.compiled_programs.items[3].low_byte);
    try std.testing.expectEqual(control_result[4][0], compiler.compiled_programs.items[4].high_byte);
    try std.testing.expectEqual(control_result[4][1], compiler.compiled_programs.items[4].low_byte);
    try std.testing.expectEqual(control_result[5][0], compiler.compiled_programs.items[5].high_byte);
    try std.testing.expectEqual(control_result[5][1], compiler.compiled_programs.items[5].low_byte);
    try std.testing.expectEqual(control_result[6][0], compiler.compiled_programs.items[6].high_byte);
    try std.testing.expectEqual(control_result[6][1], compiler.compiled_programs.items[6].low_byte);
    try std.testing.expectEqual(control_result[7][0], compiler.compiled_programs.items[7].high_byte);
    try std.testing.expectEqual(control_result[7][1], compiler.compiled_programs.items[7].low_byte);
    // ADD operations
    try std.testing.expectEqual(control_result[8][0], compiler.compiled_programs.items[8].high_byte);
    try std.testing.expectEqual(control_result[8][1], compiler.compiled_programs.items[8].low_byte);
    try std.testing.expectEqual(control_result[9][0], compiler.compiled_programs.items[9].high_byte);
    try std.testing.expectEqual(control_result[9][1], compiler.compiled_programs.items[9].low_byte);
    try std.testing.expectEqual(control_result[10][0], compiler.compiled_programs.items[10].high_byte);
    try std.testing.expectEqual(control_result[10][1], compiler.compiled_programs.items[10].low_byte);
    try std.testing.expectEqual(control_result[11][0], compiler.compiled_programs.items[11].high_byte);
    try std.testing.expectEqual(control_result[11][1], compiler.compiled_programs.items[11].low_byte);
    try std.testing.expectEqual(control_result[12][0], compiler.compiled_programs.items[12].high_byte);
    try std.testing.expectEqual(control_result[12][1], compiler.compiled_programs.items[12].low_byte);
    try std.testing.expectEqual(control_result[13][0], compiler.compiled_programs.items[13].high_byte);
    try std.testing.expectEqual(control_result[13][1], compiler.compiled_programs.items[13].low_byte);
    // ADDC operations
    try std.testing.expectEqual(control_result[14][0], compiler.compiled_programs.items[14].high_byte);
    try std.testing.expectEqual(control_result[14][1], compiler.compiled_programs.items[14].low_byte);
    try std.testing.expectEqual(control_result[15][0], compiler.compiled_programs.items[15].high_byte);
    try std.testing.expectEqual(control_result[15][1], compiler.compiled_programs.items[15].low_byte);
    try std.testing.expectEqual(control_result[16][0], compiler.compiled_programs.items[16].high_byte);
    try std.testing.expectEqual(control_result[16][1], compiler.compiled_programs.items[16].low_byte);
    try std.testing.expectEqual(control_result[17][0], compiler.compiled_programs.items[17].high_byte);
    try std.testing.expectEqual(control_result[17][1], compiler.compiled_programs.items[17].low_byte);
    try std.testing.expectEqual(control_result[18][0], compiler.compiled_programs.items[18].high_byte);
    try std.testing.expectEqual(control_result[18][1], compiler.compiled_programs.items[18].low_byte);
    try std.testing.expectEqual(control_result[19][0], compiler.compiled_programs.items[19].high_byte);
    try std.testing.expectEqual(control_result[19][1], compiler.compiled_programs.items[19].low_byte);
}

test "Compilier Direct Jump Operations test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [17]String = .{undefined} ** 17;
    // Direct LABEL Jump
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "BACKWARD:");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "JMP BACKWARD");
    raw_code_line[2] = try String.init_with_contents(arena.allocator(), "LOCK: JMP LOCK");
    raw_code_line[3] = try String.init_with_contents(arena.allocator(), "JMP FORWARD");
    raw_code_line[4] = try String.init_with_contents(arena.allocator(), "FORWARD:");

    raw_code_line[5] = try String.init_with_contents(arena.allocator(), "LOOPBACK:");
    raw_code_line[6] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[7] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[8] = try String.init_with_contents(arena.allocator(), "JMP LOOPBACK");

    raw_code_line[9] = try String.init_with_contents(arena.allocator(), "JMP AHEAD");
    raw_code_line[10] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[11] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[12] = try String.init_with_contents(arena.allocator(), "AHEAD:");

    // Direct Absolute Jump
    raw_code_line[13] = try String.init_with_contents(arena.allocator(), "JMP 45");
    raw_code_line[14] = try String.init_with_contents(arena.allocator(), "JMP -26");
    raw_code_line[15] = try String.init_with_contents(arena.allocator(), "JMP 1023");
    raw_code_line[16] = try String.init_with_contents(arena.allocator(), "JMP -1023");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // Edge case jump
        .{ 0b00_000_000, 0b00_000_000 }, // BACKWARD:
        .{ 0b11_000_100, 0b00_000_010 }, // JMP BACKWARD
        .{ 0b11_000_100, 0b00_000_001 }, // LOCK: JMP LOCK
        .{ 0b11_000_000, 0b00_000_000 }, // JMP FORWARD
        .{ 0b00_000_000, 0b00_000_000 }, // FORWARD:
        // Backward jump
        .{ 0b00_000_000, 0b00_000_000 }, // LOOPBACK:
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b11_000_100, 0b00_000_100 }, // JMP LOOPBACK
        // Forward jump
        .{ 0b11_000_000, 0b00_000_010 }, // JMP AHEAD
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // AHEAD:
        // Absolute indexed jump
        .{ 0b11_000_000, 0b00_101_101 }, // JMP 45
        .{ 0b11_000_100, 0b00_011_010 }, // JMP -26
        .{ 0b11_000_011, 0b11_111_111 }, // JMP 1023
        .{ 0b11_000_111, 0b11_111_111 }, // JMP -1023
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
    try std.testing.expectEqual(control_result[2][0], compiler.compiled_programs.items[2].high_byte);
    try std.testing.expectEqual(control_result[2][1], compiler.compiled_programs.items[2].low_byte);
    try std.testing.expectEqual(control_result[3][0], compiler.compiled_programs.items[3].high_byte);
    try std.testing.expectEqual(control_result[3][1], compiler.compiled_programs.items[3].low_byte);
    try std.testing.expectEqual(control_result[4][0], compiler.compiled_programs.items[4].high_byte);
    try std.testing.expectEqual(control_result[4][1], compiler.compiled_programs.items[4].low_byte);
    try std.testing.expectEqual(control_result[5][0], compiler.compiled_programs.items[5].high_byte);
    try std.testing.expectEqual(control_result[5][1], compiler.compiled_programs.items[5].low_byte);
    try std.testing.expectEqual(control_result[6][0], compiler.compiled_programs.items[6].high_byte);
    try std.testing.expectEqual(control_result[6][1], compiler.compiled_programs.items[6].low_byte);
    try std.testing.expectEqual(control_result[7][0], compiler.compiled_programs.items[7].high_byte);
    try std.testing.expectEqual(control_result[7][1], compiler.compiled_programs.items[7].low_byte);
    try std.testing.expectEqual(control_result[8][0], compiler.compiled_programs.items[8].high_byte);
    try std.testing.expectEqual(control_result[8][1], compiler.compiled_programs.items[8].low_byte);
    try std.testing.expectEqual(control_result[9][0], compiler.compiled_programs.items[9].high_byte);
    try std.testing.expectEqual(control_result[9][1], compiler.compiled_programs.items[9].low_byte);
    try std.testing.expectEqual(control_result[10][0], compiler.compiled_programs.items[10].high_byte);
    try std.testing.expectEqual(control_result[10][1], compiler.compiled_programs.items[10].low_byte);
    try std.testing.expectEqual(control_result[11][0], compiler.compiled_programs.items[11].high_byte);
    try std.testing.expectEqual(control_result[11][1], compiler.compiled_programs.items[11].low_byte);
    try std.testing.expectEqual(control_result[12][0], compiler.compiled_programs.items[12].high_byte);
    try std.testing.expectEqual(control_result[12][1], compiler.compiled_programs.items[12].low_byte);
    try std.testing.expectEqual(control_result[13][0], compiler.compiled_programs.items[13].high_byte);
    try std.testing.expectEqual(control_result[13][1], compiler.compiled_programs.items[13].low_byte);
    try std.testing.expectEqual(control_result[14][0], compiler.compiled_programs.items[14].high_byte);
    try std.testing.expectEqual(control_result[14][1], compiler.compiled_programs.items[14].low_byte);
    try std.testing.expectEqual(control_result[15][0], compiler.compiled_programs.items[15].high_byte);
    try std.testing.expectEqual(control_result[15][1], compiler.compiled_programs.items[15].low_byte);
    try std.testing.expectEqual(control_result[16][0], compiler.compiled_programs.items[16].high_byte);
    try std.testing.expectEqual(control_result[16][1], compiler.compiled_programs.items[16].low_byte);
}

test "Compilier flag Jump Operations test" {

    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [17]String = .{undefined} ** 17;
    // Flag LABEL Jump
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "BACKWARD:");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "JCR BACKWARD");
    raw_code_line[2] = try String.init_with_contents(arena.allocator(), "LOCK: JOV LOCK");
    raw_code_line[3] = try String.init_with_contents(arena.allocator(), "JEVN FORWARD");
    raw_code_line[4] = try String.init_with_contents(arena.allocator(), "FORWARD:");

    raw_code_line[5] = try String.init_with_contents(arena.allocator(), "LOOPBACK:");
    raw_code_line[6] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[7] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[8] = try String.init_with_contents(arena.allocator(), "JCR LOOPBACK");

    raw_code_line[9] = try String.init_with_contents(arena.allocator(), "JOV AHEAD");
    raw_code_line[10] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[11] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[12] = try String.init_with_contents(arena.allocator(), "AHEAD:");

    // Flag Absolute Jump
    raw_code_line[13] = try String.init_with_contents(arena.allocator(), "JEVN 45");
    raw_code_line[14] = try String.init_with_contents(arena.allocator(), "JCR -26");
    raw_code_line[15] = try String.init_with_contents(arena.allocator(), "JOV 127");
    raw_code_line[16] = try String.init_with_contents(arena.allocator(), "JEVN -127");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // Edge case jump
        .{ 0b00_000_000, 0b00_000_000 }, // BACKWARD:
        .{ 0b11_010_100, 0b10_000_010 }, // JCR BACKWARD
        .{ 0b11_010_010, 0b10_000_001 }, // LOCK: JOV LOCK
        .{ 0b11_010_001, 0b00_000_000 }, // JEVN FORWARD
        .{ 0b00_000_000, 0b00_000_000 }, // FORWARD:
        // Backward jump
        .{ 0b00_000_000, 0b00_000_000 }, // LOOPBACK:
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b11_010_100, 0b10_000_100 }, // JCR LOOPBACK
        // Forward jump
        .{ 0b11_010_010, 0b00_000_010 }, // JOV AHEAD
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // AHEAD:
        // Absolute indexed jump
        .{ 0b11_010_001, 0b00_101_101 }, // JEVN 45
        .{ 0b11_010_100, 0b10_011_010 }, // JCR -26
        .{ 0b11_010_010, 0b01_111_111 }, // JOV 127
        .{ 0b11_010_001, 0b11_111_111 }, // JEVN -127
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
    try std.testing.expectEqual(control_result[2][0], compiler.compiled_programs.items[2].high_byte);
    try std.testing.expectEqual(control_result[2][1], compiler.compiled_programs.items[2].low_byte);
    try std.testing.expectEqual(control_result[3][0], compiler.compiled_programs.items[3].high_byte);
    try std.testing.expectEqual(control_result[3][1], compiler.compiled_programs.items[3].low_byte);
    try std.testing.expectEqual(control_result[4][0], compiler.compiled_programs.items[4].high_byte);
    try std.testing.expectEqual(control_result[4][1], compiler.compiled_programs.items[4].low_byte);
    try std.testing.expectEqual(control_result[5][0], compiler.compiled_programs.items[5].high_byte);
    try std.testing.expectEqual(control_result[5][1], compiler.compiled_programs.items[5].low_byte);
    try std.testing.expectEqual(control_result[6][0], compiler.compiled_programs.items[6].high_byte);
    try std.testing.expectEqual(control_result[6][1], compiler.compiled_programs.items[6].low_byte);
    try std.testing.expectEqual(control_result[7][0], compiler.compiled_programs.items[7].high_byte);
    try std.testing.expectEqual(control_result[7][1], compiler.compiled_programs.items[7].low_byte);
    try std.testing.expectEqual(control_result[8][0], compiler.compiled_programs.items[8].high_byte);
    try std.testing.expectEqual(control_result[8][1], compiler.compiled_programs.items[8].low_byte);
    try std.testing.expectEqual(control_result[9][0], compiler.compiled_programs.items[9].high_byte);
    try std.testing.expectEqual(control_result[9][1], compiler.compiled_programs.items[9].low_byte);
    try std.testing.expectEqual(control_result[10][0], compiler.compiled_programs.items[10].high_byte);
    try std.testing.expectEqual(control_result[10][1], compiler.compiled_programs.items[10].low_byte);
    try std.testing.expectEqual(control_result[11][0], compiler.compiled_programs.items[11].high_byte);
    try std.testing.expectEqual(control_result[11][1], compiler.compiled_programs.items[11].low_byte);
    try std.testing.expectEqual(control_result[12][0], compiler.compiled_programs.items[12].high_byte);
    try std.testing.expectEqual(control_result[12][1], compiler.compiled_programs.items[12].low_byte);
    try std.testing.expectEqual(control_result[13][0], compiler.compiled_programs.items[13].high_byte);
    try std.testing.expectEqual(control_result[13][1], compiler.compiled_programs.items[13].low_byte);
    try std.testing.expectEqual(control_result[14][0], compiler.compiled_programs.items[14].high_byte);
    try std.testing.expectEqual(control_result[14][1], compiler.compiled_programs.items[14].low_byte);
    try std.testing.expectEqual(control_result[15][0], compiler.compiled_programs.items[15].high_byte);
    try std.testing.expectEqual(control_result[15][1], compiler.compiled_programs.items[15].low_byte);
    try std.testing.expectEqual(control_result[16][0], compiler.compiled_programs.items[16].high_byte);
    try std.testing.expectEqual(control_result[16][1], compiler.compiled_programs.items[16].low_byte);
}

test "Compilier Comp Jump Operations test" {

    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [17]String = .{undefined} ** 17;
    // Comparison LABEL Jump
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "BACKWARD:");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "JLZ BACKWARD");
    raw_code_line[2] = try String.init_with_contents(arena.allocator(), "LOCK: JLEZ LOCK");
    raw_code_line[3] = try String.init_with_contents(arena.allocator(), "JEZ FORWARD");
    raw_code_line[4] = try String.init_with_contents(arena.allocator(), "FORWARD:");

    raw_code_line[5] = try String.init_with_contents(arena.allocator(), "LOOPBACK:");
    raw_code_line[6] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[7] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[8] = try String.init_with_contents(arena.allocator(), "JNZ LOOPBACK");

    raw_code_line[9] = try String.init_with_contents(arena.allocator(), "JGZ AHEAD");
    raw_code_line[10] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[11] = try String.init_with_contents(arena.allocator(), "NOP");
    raw_code_line[12] = try String.init_with_contents(arena.allocator(), "AHEAD:");

    // Comparison Absolute Jump
    raw_code_line[13] = try String.init_with_contents(arena.allocator(), "JGEZ 45");
    raw_code_line[14] = try String.init_with_contents(arena.allocator(), "JLZ -26");
    raw_code_line[15] = try String.init_with_contents(arena.allocator(), "JLEZ 127");
    raw_code_line[16] = try String.init_with_contents(arena.allocator(), "JEZ -127");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // Edge case jump
        .{ 0b00_000_000, 0b00_000_000 }, // BACKWARD:
        .{ 0b11_011_100, 0b10_000_010 }, // JLZ BACKWARD
        .{ 0b11_011_110, 0b10_000_001 }, // LOCK: JLEZ LOCK
        .{ 0b11_011_010, 0b00_000_000 }, // JEZ FORWARD
        .{ 0b00_000_000, 0b00_000_000 }, // FORWARD:
        // Backward jump
        .{ 0b00_000_000, 0b00_000_000 }, // LOOPBACK:
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b11_011_101, 0b10_000_100 }, // JNZ LOOPBACK
        // Forward jump
        .{ 0b11_011_001, 0b00_000_010 }, // JGZ AHEAD
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // NOP
        .{ 0b00_000_000, 0b00_000_000 }, // AHEAD:
        // Absolute indexed jump
        .{ 0b11_011_011, 0b00_101_101 }, // JGEZ 45
        .{ 0b11_011_100, 0b10_011_010 }, // JLZ -26
        .{ 0b11_011_110, 0b01_111_111 }, // JLEZ 127
        .{ 0b11_011_010, 0b11_111_111 }, // JEZ -127
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
    try std.testing.expectEqual(control_result[2][0], compiler.compiled_programs.items[2].high_byte);
    try std.testing.expectEqual(control_result[2][1], compiler.compiled_programs.items[2].low_byte);
    try std.testing.expectEqual(control_result[3][0], compiler.compiled_programs.items[3].high_byte);
    try std.testing.expectEqual(control_result[3][1], compiler.compiled_programs.items[3].low_byte);
    try std.testing.expectEqual(control_result[4][0], compiler.compiled_programs.items[4].high_byte);
    try std.testing.expectEqual(control_result[4][1], compiler.compiled_programs.items[4].low_byte);
    try std.testing.expectEqual(control_result[5][0], compiler.compiled_programs.items[5].high_byte);
    try std.testing.expectEqual(control_result[5][1], compiler.compiled_programs.items[5].low_byte);
    try std.testing.expectEqual(control_result[6][0], compiler.compiled_programs.items[6].high_byte);
    try std.testing.expectEqual(control_result[6][1], compiler.compiled_programs.items[6].low_byte);
    try std.testing.expectEqual(control_result[7][0], compiler.compiled_programs.items[7].high_byte);
    try std.testing.expectEqual(control_result[7][1], compiler.compiled_programs.items[7].low_byte);
    try std.testing.expectEqual(control_result[8][0], compiler.compiled_programs.items[8].high_byte);
    try std.testing.expectEqual(control_result[8][1], compiler.compiled_programs.items[8].low_byte);
    try std.testing.expectEqual(control_result[9][0], compiler.compiled_programs.items[9].high_byte);
    try std.testing.expectEqual(control_result[9][1], compiler.compiled_programs.items[9].low_byte);
    try std.testing.expectEqual(control_result[10][0], compiler.compiled_programs.items[10].high_byte);
    try std.testing.expectEqual(control_result[10][1], compiler.compiled_programs.items[10].low_byte);
    try std.testing.expectEqual(control_result[11][0], compiler.compiled_programs.items[11].high_byte);
    try std.testing.expectEqual(control_result[11][1], compiler.compiled_programs.items[11].low_byte);
    try std.testing.expectEqual(control_result[12][0], compiler.compiled_programs.items[12].high_byte);
    try std.testing.expectEqual(control_result[12][1], compiler.compiled_programs.items[12].low_byte);
    try std.testing.expectEqual(control_result[13][0], compiler.compiled_programs.items[13].high_byte);
    try std.testing.expectEqual(control_result[13][1], compiler.compiled_programs.items[13].low_byte);
    try std.testing.expectEqual(control_result[14][0], compiler.compiled_programs.items[14].high_byte);
    try std.testing.expectEqual(control_result[14][1], compiler.compiled_programs.items[14].low_byte);
    try std.testing.expectEqual(control_result[15][0], compiler.compiled_programs.items[15].high_byte);
    try std.testing.expectEqual(control_result[15][1], compiler.compiled_programs.items[15].low_byte);
    try std.testing.expectEqual(control_result[16][0], compiler.compiled_programs.items[16].high_byte);
    try std.testing.expectEqual(control_result[16][1], compiler.compiled_programs.items[16].low_byte);
}

test "Compilier Register Jump Operations test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [2]String = .{undefined} ** 2;
    // Comparison LABEL Jump
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "JMPR R0");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "JMPR R7");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // Edge case jump
        .{ 0b11_001_000, 0b00_000_000 }, // JMPR R0
        .{ 0b11_001_111, 0b00_000_000 }, // JMPR R7
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
}

test "Compilier Register Move Operations test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [18]String = .{undefined} ** 18;
    // MOV between resigters and ALU
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "MOV AB R0 R1");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "MOV R2 S");

    // MOV Constant to Resigters
    raw_code_line[2] = try String.init_with_contents(arena.allocator(), "MOV R3 L4");
    raw_code_line[3] = try String.init_with_contents(arena.allocator(), "MOV R5 L0B1100_0101");
    raw_code_line[4] = try String.init_with_contents(arena.allocator(), "MOV R6 L255");

    raw_code_line[5] = try String.init_with_contents(arena.allocator(), "MOV R7 H0");
    raw_code_line[6] = try String.init_with_contents(arena.allocator(), "MOV R0 H0B1010_0011");
    raw_code_line[7] = try String.init_with_contents(arena.allocator(), "MOV R1 H255");

    // RAMPAGE Mode
    raw_code_line[8] = try String.init_with_contents(arena.allocator(), "MOV @0 R2");
    raw_code_line[9] = try String.init_with_contents(arena.allocator(), "MOV @122 R3");
    raw_code_line[10] = try String.init_with_contents(arena.allocator(), "MOV @255 R4");

    raw_code_line[11] = try String.init_with_contents(arena.allocator(), "MOV R5 @0");
    raw_code_line[12] = try String.init_with_contents(arena.allocator(), "MOV R6 @133");
    raw_code_line[13] = try String.init_with_contents(arena.allocator(), "MOV R7 @255");

    // MOV Register Indirect
    raw_code_line[14] = try String.init_with_contents(arena.allocator(), "MOV @R0 R1");
    raw_code_line[15] = try String.init_with_contents(arena.allocator(), "MOV @R2 R3");
    raw_code_line[16] = try String.init_with_contents(arena.allocator(), "MOV R4 @R5");
    raw_code_line[17] = try String.init_with_contents(arena.allocator(), "MOV R6 @R7");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // MOV between resigters and ALU
        .{ 0b01_000_000, 0b00_100_000 }, // MOV AB R0 R1
        .{ 0b01_001_010, 0b00_000_000 }, // MOV R2 S

        // MOV Constant to Resigters
        .{ 0b01_010_011, 0b00_000_100 }, // MOV R3 L4
        .{ 0b01_010_101, 0b11_000_101 }, // MOV R5 L0B1100_0101
        .{ 0b01_010_110, 0b11_111_111 }, // MOV R6 L255
        .{ 0b01_011_111, 0b00_000_000 }, // MOV R7 H0
        .{ 0b01_011_000, 0b10_100_011 }, // MOV R0 H0B1010_0011
        .{ 0b01_011_001, 0b11_111_111 }, // MOV R1 H255

        // RAMPAGE Mode
        .{ 0b01_100_010, 0b00_000_000 }, // MOV @0 R2
        .{ 0b01_100_011, 0b01_111_010 }, // MOV @122 R3
        .{ 0b01_100_100, 0b11_111_111 }, // MOV @255 R4
        .{ 0b01_101_101, 0b00_000_000 }, // MOV R5 @0
        .{ 0b01_101_110, 0b10_000_101 }, // MOV R6 @133
        .{ 0b01_101_111, 0b11_111_111 }, // MOV R7 @255

        // MOV Register Indirect
        .{ 0b01_110_001, 0b00_000_000 }, // "MOV @R0 R1
        .{ 0b01_110_011, 0b01_000_000 }, // "MOV @R2 R3
        .{ 0b01_111_100, 0b10_100_000 }, // "MOV R4 @R5
        .{ 0b01_111_110, 0b11_100_000 }, // "MOV R6 @R7
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
    try std.testing.expectEqual(control_result[2][0], compiler.compiled_programs.items[2].high_byte);
    try std.testing.expectEqual(control_result[2][1], compiler.compiled_programs.items[2].low_byte);
    try std.testing.expectEqual(control_result[3][0], compiler.compiled_programs.items[3].high_byte);
    try std.testing.expectEqual(control_result[3][1], compiler.compiled_programs.items[3].low_byte);
    try std.testing.expectEqual(control_result[4][0], compiler.compiled_programs.items[4].high_byte);
    try std.testing.expectEqual(control_result[4][1], compiler.compiled_programs.items[4].low_byte);
    try std.testing.expectEqual(control_result[5][0], compiler.compiled_programs.items[5].high_byte);
    try std.testing.expectEqual(control_result[5][1], compiler.compiled_programs.items[5].low_byte);
    try std.testing.expectEqual(control_result[6][0], compiler.compiled_programs.items[6].high_byte);
    try std.testing.expectEqual(control_result[6][1], compiler.compiled_programs.items[6].low_byte);
    try std.testing.expectEqual(control_result[7][0], compiler.compiled_programs.items[7].high_byte);
    try std.testing.expectEqual(control_result[7][1], compiler.compiled_programs.items[7].low_byte);
    try std.testing.expectEqual(control_result[8][0], compiler.compiled_programs.items[8].high_byte);
    try std.testing.expectEqual(control_result[8][1], compiler.compiled_programs.items[8].low_byte);
    try std.testing.expectEqual(control_result[9][0], compiler.compiled_programs.items[9].high_byte);
    try std.testing.expectEqual(control_result[9][1], compiler.compiled_programs.items[9].low_byte);
    try std.testing.expectEqual(control_result[10][0], compiler.compiled_programs.items[10].high_byte);
    try std.testing.expectEqual(control_result[10][1], compiler.compiled_programs.items[10].low_byte);
    try std.testing.expectEqual(control_result[11][0], compiler.compiled_programs.items[11].high_byte);
    try std.testing.expectEqual(control_result[11][1], compiler.compiled_programs.items[11].low_byte);
    try std.testing.expectEqual(control_result[12][0], compiler.compiled_programs.items[12].high_byte);
    try std.testing.expectEqual(control_result[12][1], compiler.compiled_programs.items[12].low_byte);
    try std.testing.expectEqual(control_result[13][0], compiler.compiled_programs.items[13].high_byte);
    try std.testing.expectEqual(control_result[13][1], compiler.compiled_programs.items[13].low_byte);
    try std.testing.expectEqual(control_result[14][0], compiler.compiled_programs.items[14].high_byte);
    try std.testing.expectEqual(control_result[14][1], compiler.compiled_programs.items[14].low_byte);
    try std.testing.expectEqual(control_result[15][0], compiler.compiled_programs.items[15].high_byte);
    try std.testing.expectEqual(control_result[15][1], compiler.compiled_programs.items[15].low_byte);
    try std.testing.expectEqual(control_result[16][0], compiler.compiled_programs.items[16].high_byte);
    try std.testing.expectEqual(control_result[16][1], compiler.compiled_programs.items[16].low_byte);
    try std.testing.expectEqual(control_result[17][1], compiler.compiled_programs.items[17].low_byte);
    try std.testing.expectEqual(control_result[17][1], compiler.compiled_programs.items[17].low_byte);
}

test "Compilier Port Operations test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [6]String = .{undefined} ** 6;
    // Comparison LABEL Jump
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "PORT R0 0");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "PORT R1 197");
    raw_code_line[2] = try String.init_with_contents(arena.allocator(), "PORT R2 255");
    raw_code_line[3] = try String.init_with_contents(arena.allocator(), "PORT 0 R3");
    raw_code_line[4] = try String.init_with_contents(arena.allocator(), "PORT 163 R4");
    raw_code_line[5] = try String.init_with_contents(arena.allocator(), "PORT 255 R5");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // Edge case jump
        .{ 0b10_101_000, 0b00_000_000 }, // PORT R0 0
        .{ 0b10_101_001, 0b11_000_101 }, // PORT R1 197
        .{ 0b10_101_010, 0b11_111_111 }, // PORT R2 255
        .{ 0b10_100_011, 0b00_000_000 }, // PORT 0 R3
        .{ 0b10_100_100, 0b10_100_011 }, // PORT 163 R4
        .{ 0b10_100_101, 0b11_111_111 }, // PORT 255 R5
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
    try std.testing.expectEqual(control_result[2][0], compiler.compiled_programs.items[2].high_byte);
    try std.testing.expectEqual(control_result[2][1], compiler.compiled_programs.items[2].low_byte);
    try std.testing.expectEqual(control_result[3][0], compiler.compiled_programs.items[3].high_byte);
    try std.testing.expectEqual(control_result[3][1], compiler.compiled_programs.items[3].low_byte);
    try std.testing.expectEqual(control_result[4][0], compiler.compiled_programs.items[4].high_byte);
    try std.testing.expectEqual(control_result[4][1], compiler.compiled_programs.items[4].low_byte);
    try std.testing.expectEqual(control_result[5][0], compiler.compiled_programs.items[5].high_byte);
    try std.testing.expectEqual(control_result[5][1], compiler.compiled_programs.items[5].low_byte);
}

test "Compilier ROMA and RAMPAGE Operations test" {
    // Initialization
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();

    var raw_code_line: [8]String = .{undefined} ** 8;
    // Comparison LABEL Jump
    raw_code_line[0] = try String.init_with_contents(arena.allocator(), "STPG 0");
    raw_code_line[1] = try String.init_with_contents(arena.allocator(), "STPG 0b10101100");
    raw_code_line[2] = try String.init_with_contents(arena.allocator(), "STPG 255");
    raw_code_line[3] = try String.init_with_contents(arena.allocator(), "RAMPAGE 0");
    raw_code_line[4] = try String.init_with_contents(arena.allocator(), "RAMPAGE 0b01010011");
    raw_code_line[5] = try String.init_with_contents(arena.allocator(), "RAMPAGE 255");
    raw_code_line[6] = try String.init_with_contents(arena.allocator(), "ROMA R0");
    raw_code_line[7] = try String.init_with_contents(arena.allocator(), "ROMA R5");

    var source_code = try generateSource(arena.allocator(), raw_code_line[0..]);

    // Test starts from here
    var compiler = Compiler().init(arena.allocator(), &source_code);
    defer compiler.deinit();

    try compiler.compile();

    // results:
    const control_result = [_][2]u8{
        // Edge case jump
        .{ 0b10_010_000, 0b00_000_000 }, // STPG 0
        .{ 0b10_010_000, 0b10_101_100 }, // STPG 0b10101100
        .{ 0b10_010_000, 0b11_111_111 }, // STPG 255
        .{ 0b10_010_000, 0b00_000_000 }, // RAMPAGE 0
        .{ 0b10_010_000, 0b01_010_011 }, // RAMPAGE 0b01010011
        .{ 0b10_010_000, 0b11_111_111 }, // RAMPAGE 255
        .{ 0b10_011_000, 0b00_000_000 }, // ROMA R0
        .{ 0b10_011_101, 0b00_000_000 }, // ROMA R5
    };

    // validations: sadly, I can't use a loop here because it has no way to tell which line has problem
    try std.testing.expectEqual(control_result[0][0], compiler.compiled_programs.items[0].high_byte);
    try std.testing.expectEqual(control_result[0][1], compiler.compiled_programs.items[0].low_byte);
    try std.testing.expectEqual(control_result[1][0], compiler.compiled_programs.items[1].high_byte);
    try std.testing.expectEqual(control_result[1][1], compiler.compiled_programs.items[1].low_byte);
    try std.testing.expectEqual(control_result[2][0], compiler.compiled_programs.items[2].high_byte);
    try std.testing.expectEqual(control_result[2][1], compiler.compiled_programs.items[2].low_byte);
    try std.testing.expectEqual(control_result[3][0], compiler.compiled_programs.items[3].high_byte);
    try std.testing.expectEqual(control_result[3][1], compiler.compiled_programs.items[3].low_byte);
    try std.testing.expectEqual(control_result[4][0], compiler.compiled_programs.items[4].high_byte);
    try std.testing.expectEqual(control_result[4][1], compiler.compiled_programs.items[4].low_byte);
    try std.testing.expectEqual(control_result[5][0], compiler.compiled_programs.items[5].high_byte);
    try std.testing.expectEqual(control_result[5][1], compiler.compiled_programs.items[5].low_byte);
    try std.testing.expectEqual(control_result[6][0], compiler.compiled_programs.items[6].high_byte);
    try std.testing.expectEqual(control_result[6][1], compiler.compiled_programs.items[6].low_byte);
    try std.testing.expectEqual(control_result[7][0], compiler.compiled_programs.items[7].high_byte);
    try std.testing.expectEqual(control_result[7][1], compiler.compiled_programs.items[7].low_byte);
}
