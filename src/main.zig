const std = @import("std");
const nfd = @import("nfd");
const string = @import("string").String;
const sv = @import("process/Sunvox.zig");
const fl = @import("process/FileLoader.zig");
const cpl = @import("process/Compiler.zig");
const rom = @import("process/VoxcomBasicTemplateRomBuilder.zig");
const exp = @import("process/VoxcomProgramExporter.zig");

// these are for the testing purposes
const cls = @import("models/CodeLineSegment.zig");
const mxh = @import("models/VOXCOMMachineCode.zig");
const cpl_utl = @import("process/CompilerUtils.zig");

pub fn main() !void {
    // std.log.info("              ██████╗ ██████╗ ██████╗ ██╗ ██████╗ ██╗  ██████╗ ██████╗ ██████╗", .{});
    // std.log.info("              ██╔═██║ ██╔═══╝ ██╔═══╝ ██║ ██╔═██║ ██║    ██╔═╝ ██╔═══╝ ██╔═██║", .{});
    // std.log.info("              ██████║ ██║     ██║     ██║ ██████║ ██║    ██║   ████╗   ████╔═╝", .{});
    // std.log.info("              ██║ ██║ ██║     ██║     ██║ ██╔═══╝ ██║    ██║   ██╔═╝   ██╔═██╗", .{});
    // std.log.info("              ██║ ██║ ██████╗ ██████╗ ██║ ██║     ██║    ██║   ██████╗ ██║ ██║", .{});
    // std.log.info("              ╚═╝ ╚═╝ ╚═════╝ ╚═════╝ ╚═╝ ╚═╝     ╚═╝    ╚═╝   ╚═════╝ ╚═╝ ╚═╝", .{});
    // std.log.info("                              ██████╗ ██████╗  ██╗ ██╗ ██████╗", .{});
    // std.log.info("                              ██╔═██║ ██╔═██║  ██║ ██║ ██╔═██║", .{});
    // std.log.info("                              ██║ ██║ ██║ ██║  ██║ ██║ ██████║", .{});
    // std.log.info("                              ██║ ██║ ██║ ██║  ██║ ██║ ██║ ██║", .{});
    // std.log.info("                              ██║ ██║ ██████║  ╚═██╔═╝ ██║ ██║", .{});
    // std.log.info("                              ╚═╝ ╚═╝ ╚═════╝    ╚═╝   ╚═╝ ╚═╝           ", .{});
    // std.log.info("_  _ ____ _  _ ____ ____ _  _      __     __    ____ ____ ____ ____ _  _ ___  _    ____ ____", .{});
    // std.log.info("|  | |  |  \\/  |    |  | |\\/|   | |__  | | /|   |__| [__  [__  |___ |\\/| |__] |    |___ |__/", .{});
    // std.log.info(" \\/  |__| _/\\_ |___ |__| |  |   | |__] | |/_|   |  | ___] ___] |___ |  | |__] |___ |___ |  \\", .{});
    // std.log.info("", .{});

    const path_opt = try nfd.openFileDialog("txt,voxasm", null);
    if (path_opt) |path| {
        defer nfd.freePath(path);

        const page = std.heap.page_allocator;
        var arena = std.heap.ArenaAllocator.init(page);
        defer arena.deinit();

        var file_loader = fl.FileLoader().init(arena.allocator(), path);
        defer file_loader.deinit();
        try file_loader.loadAssemblyFile();

        var compiler = cpl.Compiler().init(arena.allocator(), &file_loader.program_lines);
        defer compiler.deinit();
        try compiler.compile();

        var rom_export = try rom.RomGenerator().init(arena.allocator(), &compiler.compiled_programs);
        try rom_export.generate();
        try rom_export.deinit();

        var exporter = try exp.Exporter().init(arena.allocator());
        try exporter.constructRomBank();
        try exporter.deinit();
    }
}

test {
    _ = cls.CodeLineSegment();
    _ = fl.FileLoader();
    _ = mxh.VOXCOMMachineCode();
    _ = cpl.Compiler();
    _ = cpl_utl;

    std.testing.refAllDecls(@This());
}

//               ██████╗ ██████╗ ██████╗ ██╗ ██████╗ ██╗  ██████╗ ██████╗ ██████╗
//               ██╔═██║ ██╔═══╝ ██╔═══╝ ██║ ██╔═██║ ██║    ██╔═╝ ██╔═══╝ ██╔═██║
//               ██████║ ██║     ██║     ██║ ██████║ ██║    ██║   ████╗   ████╔═╝
//               ██║ ██║ ██║     ██║     ██║ ██╔═══╝ ██║    ██║   ██╔═╝   ██╔═██╗
//               ██║ ██║ ██████╗ ██████╗ ██║ ██║     ██║    ██║   ██████╗ ██║ ██║
//               ╚═╝ ╚═╝ ╚═════╝ ╚═════╝ ╚═╝ ╚═╝     ╚═╝    ╚═╝   ╚═════╝ ╚═╝ ╚═╝
//                               ██████╗ ██████╗  ██╗ ██╗ ██████╗
//                               ██╔═██║ ██╔═██║  ██║ ██║ ██╔═██║
//                               ██║ ██║ ██║ ██║  ██║ ██║ ██████║
//                               ██║ ██║ ██║ ██║  ██║ ██║ ██║ ██║
//                               ██║ ██║ ██████║  ╚═██╔═╝ ██║ ██║
//                               ╚═╝ ╚═╝ ╚═════╝    ╚═╝   ╚═╝ ╚═╝
// _  _ ____ _  _ ____ ____ _  _      __     __    ____ ____ ____ ____ _  _ ___  _    ____ ____
// |  | |  |  \/  |    |  | |\/|   | |__  | | /|   |__| [__  [__  |___ |\/| |__] |    |___ |__/
//  \/  |__| _/\_ |___ |__| |  |   | |__] | |/_|   |  | ___] ___] |___ |  | |__] |___ |___ |  \
