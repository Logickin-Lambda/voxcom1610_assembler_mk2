const std = @import("std");
const nfd = @import("nfd");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("<!-- Skri-A Kaark -->", .{});

    const path_opt = try nfd.openFileDialog("txt", null);
    if (path_opt) |path| {
        defer nfd.freePath(path);
    }
}
