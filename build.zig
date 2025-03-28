const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib_util = b.createModule(.{
        .root_source_file = b.path("src/util/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_haversine = b.createModule(.{
        .root_source_file = b.path("src/haversine/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_haversine.addImport("util", lib_util);

    // Generate executable
    const gen_module = b.createModule(.{
        .root_source_file = b.path("src/generate/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    gen_module.addImport("haversine", lib_haversine);
    const gen_exe = b.addExecutable(.{
        .name = "generate_haversine_pairs",
        .root_module = gen_module,
    });
    b.installArtifact(gen_exe);

    // Compute executable
    const compute_module = b.createModule(.{
        .root_source_file = b.path("src/compute/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    compute_module.addImport("util", lib_util);
    compute_module.addImport("haversine", lib_haversine);
    const compute_exe = b.addExecutable(.{
        .name = "compute_haversine",
        .root_module = compute_module,
    });
    b.installArtifact(compute_exe);

    // Add tests for compute module
    const util_tests = b.addTest(.{
        .root_source_file = b.path("src/util/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_compute_tests = b.addRunArtifact(util_tests);

    // Create a step for running compute tests
    const test_util_step = b.step("test", "Run compute module tests");
    test_util_step.dependOn(&run_compute_tests.step);
}
