const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nfd_mod = b.addModule("nfd", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const cflags = [_][]const u8{"-Wall"};
    nfd_mod.addIncludePath(b.path("lib/nfd/include"));
    nfd_mod.addCSourceFile(.{ .file = b.path("lib/nfd/nfd_common.c"), .flags = &cflags });
    switch (target.result.os.tag) {
        .macos => nfd_mod.addCSourceFile(.{ .file = b.path("lib/nfd/nfd_cocoa.m"), .flags = &cflags }),
        .windows => nfd_mod.addCSourceFile(.{ .file = b.path("lib/nfd/nfd_win.cpp"), .flags = &cflags }),
        .linux => nfd_mod.addCSourceFile(.{ .file = b.path("lib/nfd/nfd_gtk.c"), .flags = &cflags }),
        else => @panic("unsupported OS"),
    }

    switch (target.result.os.tag) {
        .macos => nfd_mod.linkFramework("AppKit", .{}),
        .windows => {
            nfd_mod.linkSystemLibrary("shell32", .{});
            nfd_mod.linkSystemLibrary("ole32", .{});
            nfd_mod.linkSystemLibrary("uuid", .{}); // needed by MinGW
        },
        .linux => {
            nfd_mod.linkSystemLibrary("atk-1.0", .{});
            nfd_mod.linkSystemLibrary("gdk-3", .{});
            nfd_mod.linkSystemLibrary("gtk-3", .{});
            nfd_mod.linkSystemLibrary("glib-2.0", .{});
            nfd_mod.linkSystemLibrary("gobject-2.0", .{});
        },
        else => @panic("unsupported OS"),
    }

    // String library
    const string = b.dependency("string", .{
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    const exe = b.addExecutable(.{
        .name = "voxcom1610_assembler_mk2",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .cwd_relative = "lib/nfd/include" });
    exe.addIncludePath(.{ .cwd_relative = "lib/sunvox" });
    exe.root_module.addImport("nfd", nfd_mod);
    exe.root_module.addImport("string", string.module("string"));
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.addIncludePath(.{ .cwd_relative = "lib/nfd/include" });
    exe_unit_tests.addIncludePath(.{ .cwd_relative = "lib/sunvox" });
    exe_unit_tests.root_module.addImport("nfd", nfd_mod);
    exe_unit_tests.root_module.addImport("string", string.module("string"));
    exe_unit_tests.linkLibC();

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
