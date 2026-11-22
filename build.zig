const std = @import("std");
const Build = std.Build;

const Translator = @import("translate_c").Translator;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const md4c = b.dependency("md4c", .{});

    const translate_c = b.dependency("translate_c", .{});

    const c_translator: Translator = .init(translate_c, .{
        .c_source_file = md4c.path("src/md4c.h"),
        .target = target,
        .optimize = optimize,
    });
    const md4c_mod = c_translator.mod;

    const root_mod = b.addModule("md4z", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "md4c", .module = md4c_mod },
        },
    });
    root_mod.addCSourceFile(.{ .file = md4c.path("src/md4c.c"), .flags = &.{} });

    const test_exe = b.addTest(.{ .root_module = root_mod });

    const run_test_exe = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Build on save");
    test_step.dependOn(&run_test_exe.step);

    const check_step = b.step("check", "Build on save");
    check_step.dependOn(&test_exe.step);
}
