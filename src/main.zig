const std = @import("std");
const nfd = @import("nfd");
const string = @import("string").String;
const sv = @import("process/Sunvox.zig");

// these are for the testing purposes
const cls = @import("models/CodeLineSegment.zig");
const fl = @import("process/FileLoader.zig");
const mxh = @import("models/VOXCOMMachineCode.zig");
const cpl = @import("process/Compiler.zig");
const cpl_utl = @import("process/CompilerUtils.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("<!-- Skri-A Kaark -->", .{});

    const path_opt = try nfd.openFileDialog("sunvox", null);
    if (path_opt) |path| {
        defer nfd.freePath(path);

        _ = try sv.init(0, 44100, 2, 0);
        try sv.openSlot(0);
        try sv.load(0, path);
        try sv.playFromBeginning(0);

        while (!sv.endOfSong(0)) {
            std.time.sleep(1000 * 1000 * 1000);
        }
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
