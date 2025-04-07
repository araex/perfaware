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
    const build_compute = b.step("compute", "Build the compute executable");
    build_compute.dependOn(&compute_exe.step);
    build_compute.dependOn(b.getInstallStep());

    b.installArtifact(compute_exe);
    const compute_run = b.addRunArtifact(compute_exe);
    if (b.args) |args| {
        compute_run.addArgs(args);
    }
    const compute_step = b.step("compute-run", "Build & run the compute executable");
    compute_step.dependOn(&compute_run.step);

    // Repetition test executable
    const reptest_module = b.createModule(.{
        .root_source_file = b.path("src/compute/main_reptest.zig"),
        .target = target,
        .optimize = optimize,
    });
    reptest_module.addImport("util", lib_util);
    reptest_module.addImport("haversine", lib_haversine);
    const reptest_exe = b.addExecutable(.{
        .name = "reptest",
        .root_module = reptest_module,
    });
    const reptest_run = b.addRunArtifact(reptest_exe);
    const reptest_run_step = b.step("reptest", "Build & run the repetition test exe");
    reptest_run_step.dependOn(&reptest_run.step);

    // Repetition test executable
    const sandbox_mod = b.createModule(.{
        .root_source_file = b.path("src/sandbox/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = false,
    });
    sandbox_mod.addImport("util", lib_util);
    const sandbox_exe = b.addExecutable(.{
        .name = "sandbox",
        .root_module = sandbox_mod,
    });
    b.installArtifact(sandbox_exe);
    const sandbox_run = b.addRunArtifact(sandbox_exe);
    if (b.args) |args| {
        sandbox_run.addArgs(args);
    }
    const sandbox_run_step = b.step("sandbox", "Build & run the sandbox testing exe");
    sandbox_run_step.dependOn(b.getInstallStep());
    sandbox_run_step.dependOn(&sandbox_run.step);

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
