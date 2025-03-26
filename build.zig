const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib_module = addHaversineLib(b, target, optimize);

    // Generate executable
    const gen_module = b.createModule(.{
        .root_source_file = b.path("src/generate/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    gen_module.addImport("haversine", lib_module);
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
    compute_module.addImport("haversine", lib_module);
    const compute_exe = b.addExecutable(.{
        .name = "compute_haversine",
        .root_module = compute_module,
    });
    b.installArtifact(compute_exe);

    // Add tests for compute module
    const compute_tests = b.addTest(.{
        .root_source_file = b.path("src/compute/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    compute_tests.root_module.addImport("haversine", lib_module);

    const run_compute_tests = b.addRunArtifact(compute_tests);

    // Create a step for running compute tests
    const test_step = b.step("test", "Run compute module tests");
    test_step.dependOn(&run_compute_tests.step);

    // Check steps for both executables
    const check_generate = b.addExecutable(.{
        .name = "zls build check generate",
        .root_module = gen_module,
    });
    const check_compute = b.addExecutable(.{
        .name = "zls build check proc_haversine",
        .root_module = compute_module,
    });
    const check = b.step("check", "Check if all executables compile");
    check.dependOn(&check_generate.step);
    check.dependOn(&check_compute.step);
}

fn addHaversineLib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("src/haversine/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "haversine lib",
        .root_module = module,
    });
    b.installArtifact(lib);
    return module;
}
