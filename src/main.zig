const std = @import("std");
const nfd = @import("nfd");
const string = @import("string").String;
const sv = @import("process/Sunvox.zig");
const fl = @import("process/FileLoader.zig");
const cpl = @import("process/Compiler.zig");
const rom = @import("process/VoxcomBasicTemplateRomBuilder.zig");

// these are for the testing purposes
const cls = @import("models/CodeLineSegment.zig");
const mxh = @import("models/VOXCOMMachineCode.zig");
const cpl_utl = @import("process/CompilerUtils.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("<!-- Skri-A Kaark -->", .{});

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

        // _ = try sv.init(0, 44100, 2, 0);
        // try sv.openSlot(0);
        // try sv.load(0, path);
        // try sv.playFromBeginning(0);

        // while (!sv.endOfSong(0)) {
        //     std.time.sleep(1000 * 1000 * 1000);
        // }

        try rom_export.deinit();
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

// ============================================== //
//            _          _                        //
//           / \        / \                       //
//    _____ _____       \_/   ___  _____ _____    //
//       /     /       |   | |   |    /     /     //
//      /|    /        |   | |   |   /|    /      //
//    _/_|_ _/___ ____  \ /  |___| _/_|_ _/___    //
//       |               |            |           //
//      /                |           /            //
//    _/                 |         _/             //
//                                                //
// ============================================== //
