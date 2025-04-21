const std = @import("std");

const clock = @import("util").clock;
const platform = @import("util").platform;
const RepTester = @import("util").RepetitionTester;
const x64 = @import("util").x64;

const cache_testing = @import("cache_testing.zig");
const manual_asm = @import("asm.zig");

pub noinline fn main() !void {
    // var gpa = std.heap.DebugAllocator(.{}).init;
    // defer std.debug.assert(gpa.deinit() == .ok);
    // const alloc = gpa.allocator();
    const alloc = std.heap.page_allocator;

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    // var rng = std.Random.DefaultPrng.init(42);

    if (args.len == 2) {
        const command = args[1];
        if (std.mem.eql(u8, command, "pagefault")) {
            try pagefault();
            return;
        }
        if (std.mem.eql(u8, command, "write-bytes")) {
            const data = try alloc.alloc(u8, 1024 * 1024 * 1024);
            defer alloc.free(data);

            try writeAllBytes(data);
        }
        if (std.mem.eql(u8, command, "read-unroll")) {
            const data = try alloc.alloc(u8, 4096);
            defer alloc.free(data);

            try readUnroll(data);
        }
        if (std.mem.eql(u8, command, "write-unroll")) {
            const data = try alloc.alloc(u8, 4096);
            defer alloc.free(data);

            try writeUnroll(data);
        }
        if (std.mem.eql(u8, command, "read-width")) {
            const data = try alloc.alloc(u8, 1024 * 1024 * 1024);
            defer alloc.free(data);

            try readWidth(data);
        }
        if (std.mem.eql(u8, command, "cache-test")) {
            const data = try alloc.alloc(u8, 1024 * 1024 * 1024);
            defer alloc.free(data);

            try cache_testing.run(alloc, data);
        }
    }
}

// Helper for benchmarking functions with same signature pattern
fn benchmarkFunction(
    name: []const u8,
    cpu_freq: u64,
    byte_count: u64,
    func: anytype,
    args: anytype,
) !void {
    std.debug.print("{s}\n", .{name});
    var tester = try RepTester.init(cpu_freq, 5);
    while (tester.continueTesting()) {
        var timer = try tester.beginTime();

        @call(.auto, func, args);

        tester.countBytes(byte_count);
        try timer.end();
    }
}

fn readWidth(data: []const u8) !void {
    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

    try benchmarkFunction(
        "Read_4x3",
        cpu_freq,
        data.len,
        manual_asm.Read_4x3,
        .{ data.len, data.ptr },
    );

    try benchmarkFunction(
        "Read_8x3",
        cpu_freq,
        data.len,
        manual_asm.Read_8x3,
        .{ data.len, data.ptr },
    );
    try benchmarkFunction(
        "Read_16x2",
        cpu_freq,
        data.len,
        manual_asm.Read_16x2,
        .{ data.len, data.ptr },
    );
    try benchmarkFunction(
        "Read_16x3",
        cpu_freq,
        data.len,
        manual_asm.Read_16x3,
        .{ data.len, data.ptr },
    );
    try benchmarkFunction(
        "Read_32x2",
        cpu_freq,
        data.len,
        manual_asm.Read_32x2,
        .{ data.len, data.ptr },
    );
    try benchmarkFunction(
        "Read_32x3",
        cpu_freq,
        data.len,
        manual_asm.Read_32x3,
        .{ data.len, data.ptr },
    );
}

fn writeUnroll(data: []const u8) !void {
    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

    const repeat_count = 1024 * 1024 * 1024;

    try benchmarkFunction(
        "Write_x1",
        cpu_freq,
        repeat_count,
        manual_asm.Write_x1,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Write_x2",
        cpu_freq,
        repeat_count,
        manual_asm.Write_x2,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Write_x3",
        cpu_freq,
        repeat_count,
        manual_asm.Write_x3,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Write_x4",
        cpu_freq,
        repeat_count,
        manual_asm.Write_x4,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Write_x5",
        cpu_freq,
        repeat_count,
        manual_asm.Write_x5,
        .{ repeat_count, data.ptr },
    );
}

fn readUnroll(data: []const u8) !void {
    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

    const repeat_count = 1024 * 1024 * 1024;

    try benchmarkFunction(
        "Read_x1",
        cpu_freq,
        repeat_count,
        manual_asm.Read_x1,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Read_x1 unaligned",
        cpu_freq,
        repeat_count,
        manual_asm.Read_x1,
        .{ repeat_count, data.ptr + 62 },
    );
    try benchmarkFunction(
        "Read_x2",
        cpu_freq,
        repeat_count,
        manual_asm.Read_x2,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Read_x3",
        cpu_freq,
        repeat_count,
        manual_asm.Read_x3,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Read_x3 unaligned",
        cpu_freq,
        repeat_count,
        manual_asm.Read_x3,
        .{ repeat_count, data.ptr + 62 },
    );
    try benchmarkFunction(
        "Read_x4",
        cpu_freq,
        repeat_count,
        manual_asm.Read_x4,
        .{ repeat_count, data.ptr },
    );
    try benchmarkFunction(
        "Read_x5",
        cpu_freq,
        repeat_count,
        manual_asm.Read_x5,
        .{ repeat_count, data.ptr },
    );
}

fn writeAllBytes(data: []u8) !void {
    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

    // Benchmark Zig loop manually since it has a unique implementation
    std.debug.print("Write all bytes: zig loop\n", .{});
    var tester_zig_loop = try RepTester.init(cpu_freq, 10);
    while (tester_zig_loop.continueTesting()) {
        var timer = try tester_zig_loop.beginTime();

        for (0..data.len) |i| {
            data[i] = @truncate(i);
        }

        tester_zig_loop.countBytes(data.len);
        try timer.end();
    }

    try benchmarkFunction(
        "MOV all bytes: asm loop",
        cpu_freq,
        data.len,
        manual_asm.MOVAllBytesASM,
        .{ data.len, data.ptr },
    );
    try benchmarkFunction(
        "NOP all bytes: asm loop",
        cpu_freq,
        data.len,
        manual_asm.NOPAllBytesASM,
        .{data.len},
    );
    try benchmarkFunction(
        "CMP all bytes: asm loop",
        cpu_freq,
        data.len,
        manual_asm.CMPAllBytesASM,
        .{data.len},
    );
    try benchmarkFunction(
        "DEC all bytes: asm loop",
        cpu_freq,
        data.len,
        manual_asm.DECAllBytesASM,
        .{data.len},
    );
}

fn pagefault() !void {
    const forward = true;
    const assumed_page_size = 4096;
    const page_count = 4096;

    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer bw.flush() catch unreachable;
    const stdout = bw.writer();

    try stdout.print("Page Count,Touch Count,Fault Count,Extra Faults\n", .{});

    for (1..page_count) |touch_count| {
        const alloc_size = touch_count * assumed_page_size;
        const data = try platform.rawAlloc(alloc_size);
        defer platform.rawFree(data);

        const page_faults_start = try platform.readPageFaultCount();
        for (0..data.len) |j| {
            const idx = if (forward) j else (data.len - 1 - j);
            data[idx] = @truncate(idx);
        }
        const page_faults_end = try platform.readPageFaultCount();

        const fault_count = page_faults_end - page_faults_start;
        const extra_faults = @as(i32, @intCast(fault_count)) - @as(i32, @intCast(touch_count));
        try stdout.print("{d},{d},{d},{d}\n", .{ page_count, touch_count, fault_count, extra_faults });
    }
}
