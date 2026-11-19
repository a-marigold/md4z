const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    const test_exe = b.addTest(.{ .root_module = root_mod });

    const check_step = b.step("check", "Build on save");
    check_step.dependOn(&test_exe.step);
}
