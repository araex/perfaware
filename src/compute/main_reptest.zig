const std = @import("std");

const clock = @import("util").clock;
const Tester = @import("util").RepetitionTester;

const json = @import("json.zig");

const seconds_to_try = 10;
const json_file_name = "haversine_pairs_10000000.json";

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const alloc = gpa.allocator();

    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    var arena_preheated = false;

    for (0..10) |i| {
        const alloc_for_this_loop = blk: {
            if (@mod(i, 2) == 0) {
                std.debug.print("using gpa\n", .{});
                break :blk alloc;
            } else {
                std.debug.print("using arena", .{});
                if (arena_preheated) {
                    std.debug.print(" (preheated)", .{});
                } else {
                    std.debug.print(" (preheating...)", .{});
                }
                std.debug.print("\n", .{});

                _ = arena.reset(.retain_capacity);
                arena_preheated = true;
                break :blk arena.allocator();
            }
        };
        // try testReaderBufferSize(2048, alloc_for_this_loop, cpu_freq);
        try testReaderBufferSize(4096, alloc_for_this_loop, cpu_freq);
        // try testReaderBufferSize(8192, alloc_for_this_loop, cpu_freq);
        try testReaderBufferSize(16384, alloc_for_this_loop, cpu_freq);
        // try testReaderBufferSize(32768, alloc_for_this_loop, cpu_freq);
        try testReaderBufferFullFile(alloc_for_this_loop, cpu_freq);
    }
}

fn testReaderBufferSize(
    size: comptime_int,
    alloc: std.mem.Allocator,
    cpu_freq: u64,
) !void {
    var tester = try Tester.init(cpu_freq, seconds_to_try);

    std.debug.print("json_reader buffer size {d}\n", .{size});
    tester.restart();
    while (tester.continueTesting()) {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();

        const file = try std.fs.cwd().openFile(json_file_name, .{});
        defer file.close();
        const file_reader = file.reader().any();
        var timer = tester.beginTime();

        var reader = json.Reader(size, @TypeOf(file_reader)).init(alloc, file_reader);
        while (try reader.nextWithAlloc(arena.allocator()) != .end_of_document) {}
        tester.countBytes(reader.bytesRead());

        timer.end();
    }
}

fn testReaderBufferFullFile(
    alloc: std.mem.Allocator,
    cpu_freq: u64,
) !void {
    var tester = try Tester.init(cpu_freq, seconds_to_try);

    std.debug.print("json_reader read whole file first\n", .{});
    tester.restart();
    while (tester.continueTesting()) {
        const file_size = blk: {
            const file = try std.fs.cwd().openFile(json_file_name, .{});
            defer file.close();
            break :blk try file.getEndPos();
        };

        var timer = tester.beginTime();
        const file_content = try std.fs.cwd().readFileAlloc(alloc, json_file_name, file_size);
        defer alloc.free(file_content);

        var scanner = json.Scanner.initCompleteInput(alloc, file_content);
        defer scanner.deinit();
        while (try scanner.next() != .end_of_document) {}

        tester.countBytes(file_content.len);
        timer.end();
    }
}
