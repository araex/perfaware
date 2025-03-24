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
        .name = "haversine",
        .root_module = gen_mod,
    });
    b.installArtifact(gen_exe);

    const gen_run_cmd = b.addRunArtifact(gen_exe);
    gen_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        gen_run_cmd.addArgs(args);
    }
    const gen_run_step = b.step("gen", "Generate json with haversine paths");
    gen_run_step.dependOn(&gen_run_cmd.step);
}
