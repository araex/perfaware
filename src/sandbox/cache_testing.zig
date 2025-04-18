const std = @import("std");

const clock = @import("util").clock;
const RepTester = @import("util").RepetitionTester;

const manual_asm = @import("asm.zig");

const TestRun = struct {
    reads_per_rep: usize,
    tester: RepTester,
};

pub fn run(alloc: std.mem.Allocator, data: []const u8) !void {
    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

    var pending_tests = std.fifo.LinearFifo(TestRun, .{ .Static = 64 }).init();
    try pending_tests.writeItem(TestRun{
        .reads_per_rep = 4 * 1024,
        .tester = try RepTester.init(cpu_freq, 5),
    });
    try pending_tests.writeItem(TestRun{
        .reads_per_rep = 512 * 1024 * 1024,
        .tester = try RepTester.init(cpu_freq, 5),
    });

    var completed_tests = std.MultiArrayList(TestRun){};
    defer completed_tests.deinit(alloc);

    while (pending_tests.readItem()) |test_run_item| {
        var test_run = test_run_item;
        const kb = @as(f64, @floatFromInt(test_run.reads_per_rep)) / 1024.0;
        const rep_count = @divFloor(data.len, test_run.reads_per_rep);
        const actual_bytes_read = rep_count * test_run.reads_per_rep;
        std.debug.print("Testing {d}KB buffer, {d} reps, current queue {any}\n", .{
            kb,
            rep_count,
            pending_tests.count,
        });

        test_run.tester.restart();
        while (test_run.tester.continueTesting()) {
            var timer = try test_run.tester.beginTime();

            manual_asm.Read_32x8_RepCount(rep_count, data.ptr, test_run.reads_per_rep);
            test_run.tester.countBytes(actual_bytes_read);
            try timer.end();
        }

        const insert_at = blk: {
            var idx: usize = 0;
            for (completed_tests.items(.reads_per_rep)) |other| {
                if (other < test_run.reads_per_rep) {
                    idx += 1;
                } else {
                    break;
                }
            }
            break :blk idx;
        };

        try completed_tests.insert(alloc, insert_at, test_run);

        if (completed_tests.len == 1) {
            continue;
        }
        if (insert_at != 0) {
            if (try nextTest(completed_tests.get(insert_at - 1), test_run)) |next| {
                std.debug.print("      -> Adding test: {any}\n", .{next.reads_per_rep});
                try pending_tests.writeItem(next);
            }
        }
        if (insert_at + 2 < completed_tests.len) {
            if (try nextTest(completed_tests.get(insert_at + 1), test_run)) |next| {
                std.debug.print("      -> Adding test: {any}\n", .{next.reads_per_rep});
                try pending_tests.writeItem(next);
            }
        }
    }

    // print csv
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer bw.flush() catch unreachable;
    const stdout = bw.writer();
    try stdout.print("Buffer Size,GiB/s\n", .{});
    for (completed_tests.items(.reads_per_rep), completed_tests.items(.tester)) |reads_per_rep, tester| {
        const fastest = tester.result.fastest_run orelse unreachable;
        const millis = clock.toMilliseconds(fastest.cpu_time, fastest.cpu_freq);
        const kb = @as(f64, @floatFromInt(fastest.byte_count)) / 1024.0;
        const mb = kb / 1024.0;
        const gb = mb / 1024.0;
        const gbps = gb / (millis / 1000.0);
        try stdout.print("{d},{d:.3}\n", .{ reads_per_rep, gbps });
    }
}

fn nextTest(run_a: TestRun, run_b: TestRun) !?TestRun {
    const fastest_a = run_a.tester.result.fastest_run orelse unreachable;
    const fastest_b = run_b.tester.result.fastest_run orelse unreachable;

    const cpu_time_a = @as(f64, @floatFromInt(fastest_a.cpu_time));
    const cpu_time_b = @as(f64, @floatFromInt(fastest_b.cpu_time));

    const abs_diff: f64 = @abs(cpu_time_a - cpu_time_b);
    const rel_diff = abs_diff / ((cpu_time_a + cpu_time_b) / 2);
    if (rel_diff > 0.10) {
        const to_test = @divFloor(run_a.reads_per_rep + run_b.reads_per_rep, 2);
        std.debug.assert(to_test != 0);
        if (to_test == run_a.reads_per_rep or to_test == run_b.reads_per_rep) {
            std.debug.print("Unexpectedly high variance between: {any} and {any}\n", .{ run_a, run_b });
            return null;
        }
        return TestRun{
            .reads_per_rep = to_test,
            .tester = try RepTester.init(run_a.tester.cpu_freq, run_a.tester.try_for_s),
        };
    }
    return null;
}
