const std = @import("std");

const clock = @import("util").clock;
const platform = @import("util").platform;
const RepTester = @import("util").RepetitionTester;
const x64 = @import("util").x64;

const manual_asm = @import("asm.zig");

pub noinline fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    // var rng = std.Random.DefaultPrng.init(42);

    if (args.len == 2) {
        const command = args[1];
        if (std.mem.eql(u8, command, "pagefault")) {
            try pagefault();
            return;
        }
        if (std.mem.eql(u8, command, "bytes")) {
            const data = try alloc.alloc(u8, 1024 * 1024 * 1024);
            defer alloc.free(data);

            try writeAllBytes(data);
            // Make sure the whole thing is not optimized away
            // std.debug.print("{any}\n", .{data[rng.random().intRangeAtMost(usize, 0, data.len - 1)]});
        }
    }
}

fn writeAllBytes(data: []u8) !void {
    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

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

    std.debug.print("MOV all bytes: asm loop\n", .{});
    var tester_asm_mov = try RepTester.init(cpu_freq, 10);
    while (tester_asm_mov.continueTesting()) {
        var timer = try tester_asm_mov.beginTime();

        manual_asm.MOVAllBytesASM(data.len, data.ptr);

        tester_asm_mov.countBytes(data.len);
        try timer.end();
    }

    std.debug.print("NOP all bytes: asm loop\n", .{});
    var tester_asm_nop = try RepTester.init(cpu_freq, 10);
    while (tester_asm_nop.continueTesting()) {
        var timer = try tester_asm_nop.beginTime();

        manual_asm.NOPAllBytesASM(data.len);

        tester_asm_nop.countBytes(data.len);
        try timer.end();
    }

    std.debug.print("CMP all bytes: asm loop\n", .{});
    var tester_asm_cmp = try RepTester.init(cpu_freq, 10);
    while (tester_asm_cmp.continueTesting()) {
        var timer = try tester_asm_cmp.beginTime();

        manual_asm.CMPAllBytesASM(data.len);

        tester_asm_cmp.countBytes(data.len);
        try timer.end();
    }

    std.debug.print("DEC all bytes: asm loop\n", .{});
    var tester_asm_dec = try RepTester.init(cpu_freq, 10);
    while (tester_asm_dec.continueTesting()) {
        var timer = try tester_asm_dec.beginTime();

        manual_asm.DECAllBytesASM(data.len);

        tester_asm_dec.countBytes(data.len);
        try timer.end();
    }
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
