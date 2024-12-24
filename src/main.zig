const std = @import("std");
const nfd = @import("nfd");
const string = @import("string").String;
const cls = @import("models/CodeLineSegment.zig");
const fl = @import("process/FileLoader.zig");
const mxh = @import("models/VOXCOMMachineCode.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("<!-- Skri-A Kaark -->", .{});

    const path_opt = try nfd.openFileDialog("txt", null);
    if (path_opt) |path| {
        defer nfd.freePath(path);
    }
}

test {
    _ = cls.CodeLineSegment();
    _ = fl.FileLoader();
    _ = mxh.VOXCOMMachineCode();

    std.testing.refAllDecls(@This());
}
