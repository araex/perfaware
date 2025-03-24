const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const gen_exe = b.addExecutable(.{
        .name = "gen_haversine",
        .root_module = gen_mod,
    });
    b.installArtifact(gen_exe);

    const exe_check = b.addExecutable(.{
        .name = "zls build check",
        .root_module = gen_mod,
    });
    const check = b.step("check", "Check if gen_haversine compiles");
    check.dependOn(&exe_check.step);
}
