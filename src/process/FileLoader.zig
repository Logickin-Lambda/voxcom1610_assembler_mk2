const std = @import("std");
const String = @import("string").String;
const cls = @import("../models/CodeLineSegment.zig");

const white_spaces = [_]u8{ ' ', '\t', '\r' };

pub fn FileLoader() type {
    return struct {
        const Self = @This();
        file_path: ?[]const u8,
        program_lines: std.ArrayList(?cls.CodeLineSegment()),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, path: []const u8) Self {
            return Self{
                .allocator = allocator,
                .program_lines = std.ArrayList(?cls.CodeLineSegment()).init(allocator),
                .file_path = path,
            };
        }

        pub fn deinit(self: *Self) void {
            for (0..self.program_lines.items.len) |i| {
                if (self.program_lines.items[i] != null) {
                    self.program_lines.items[i].?.deinit();
                }
            }
            self.program_lines.deinit();
        }

        pub fn loadAssemblyFile(self: *Self) !void {
            var file = try std.fs.openFileAbsolute(self.file_path.?, .{});
            defer file.close();
            const stat = try file.stat();

            const raw_file_data = try file.readToEndAlloc(self.allocator, @as(usize, @intCast(stat.size)));

            var iter = std.mem.split(u8, raw_file_data, "\n");

            var file_ref_index: u32 = 1;
            var compile_index: u32 = 0;

            while (iter.next()) |line| {
                // file_ref_index += 1;

                var line_str = try String.init_with_contents(self.allocator, line);

                line_str.trim(white_spaces[0..]);
                line_str.toUppercase(); // VOXASM is case insensitive, so you can do things like: LaBeL: aDd A B

                // if the line is empty or only containing white spaces,
                // or if the line starting with a # after trimming,
                // assign a null row since they have no effect to the compiled program
                if (line_str.find("#")) |char_index| {
                    line_str = try line_str.substr(0, char_index);
                }

                if (line_str.size == 0) {
                    try self.program_lines.append(null);
                    file_ref_index += 1;
                } else {
                    var segment = cls.CodeLineSegment().init(self.allocator);
                    try segment.loadRawCodeLine(line_str, file_ref_index, compile_index);
                    try segment.splitCodes();
                    try self.program_lines.append(segment);
                    file_ref_index += 1;
                    compile_index += 1;
                }
            }
        }
    };
}

test "File Loader Init Test" {
    var file_loader = FileLoader().init(std.testing.allocator, "");
    defer file_loader.deinit();
}

test "File Loader read file Test" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const path: []u8 = try std.fs.cwd().realpathAlloc(arena.allocator(), ".");
    const file_path = try std.fmt.allocPrint(arena.allocator(), "{s}{s}", .{ path, "\\src\\test_data\\voxcom_test_file.txt" });

    var file_loader = FileLoader().init(arena.allocator(), file_path);
    defer file_loader.deinit();

    try file_loader.loadAssemblyFile();
}

test "File Loader full test" {
    const test_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const path: []u8 = try std.fs.cwd().realpathAlloc(arena.allocator(), ".");
    const file_path = try std.fmt.allocPrint(arena.allocator(), "{s}{s}", .{ path, "\\src\\test_data\\voxcom_test_file.txt" });

    var file_loader = FileLoader().init(arena.allocator(), file_path);
    defer file_loader.deinit();

    try file_loader.loadAssemblyFile();

    try std.testing.expectEqual(65, file_loader.program_lines.items.len);
    try std.testing.expectEqual(null, file_loader.program_lines.items[0]); // comment
    try std.testing.expectEqual(null, file_loader.program_lines.items[2]); // empty line
    try std.testing.expectEqualStrings("LABEL:", file_loader.program_lines.items[3].?.raw_code_line.?.str()); // Label
    try std.testing.expectEqualStrings("TEST1: TEST2:", file_loader.program_lines.items[4].?.raw_code_line.?.str()); // Double Label
    try std.testing.expectEqualStrings("MOV\t\tAB \t\tR0\t\tR1", file_loader.program_lines.items[19].?.raw_code_line.?.str()); // Complex Move Operation

    // test if actual split result being correct with the file loader
    // TEST1: TEST2:
    const line5 = file_loader.program_lines.items[4].?;
    try std.testing.expectEqual(5, line5.file_ref_index);
    try std.testing.expectEqual(1, line5.compile_index);
    try std.testing.expectEqual(2, line5.prelabels.items.len);
    try std.testing.expectEqualStrings("TEST1:", line5.prelabels.items[0].str());
    try std.testing.expectEqualStrings("TEST2:", line5.prelabels.items[1].str());

    // TEST3:	MOV		AB 		R7		R7
    const line50 = file_loader.program_lines.items[49].?;
    try std.testing.expectEqual(50, line50.file_ref_index);
    try std.testing.expectEqual(41, line50.compile_index);
    try std.testing.expectEqual(1, line50.prelabels.items.len);
    try std.testing.expectEqualStrings("MOV", line50.opcode.?.str());
    try std.testing.expectEqual(3, line50.operands.items.len);
    try std.testing.expectEqualStrings("AB", line50.operands.items[0].str());
    try std.testing.expectEqualStrings("R7", line50.operands.items[1].str());
    try std.testing.expectEqualStrings("R7", line50.operands.items[2].str());
}
