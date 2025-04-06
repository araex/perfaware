const std = @import("std");

const clock = @import("util").clock;
const Tester = @import("util").RepetitionTester;

const json = @import("json.zig");

const seconds_to_try = 10;
const json_file_name = "haversine_pairs_10000000.json";

const Case = struct {
    name: []const u8,
    tester: Tester,
    func: *const fn (*Tester, std.mem.Allocator) void,

    fn run(self: *@This(), alloc: std.mem.Allocator) void {
        self.func(&self.tester, alloc);
    }
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    std.debug.print("Calibrating...\n", .{});
    const cpu_freq = try clock.estimateCpuFreq(500);
    std.debug.print(" {d} MHz\n", .{cpu_freq / (1000 * 1000)});

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var cases = [_]Case{
        .{
            .name = "json_reader buffered 4096",
            .tester = try Tester.init(cpu_freq, seconds_to_try),
            .func = &caseReadBuffered4096,
        },
        .{
            .name = "json_reader buffered 16384",
            .tester = try Tester.init(cpu_freq, seconds_to_try),
            .func = &caseReadBuffered16384,
        },
        .{
            .name = "json_reader read whole file first",
            .tester = try Tester.init(cpu_freq, seconds_to_try),
            .func = &caseReadFullFile,
        },
    };

    for (0..10) |i| {
        const alloc_for_this_loop = blk: {
            if (@mod(i, 2) == 1) {
                std.debug.print("== using arena allocator\n", .{});
                _ = arena.reset(.retain_capacity);
                break :blk arena.allocator();
            } else {
                std.debug.print("== using gpa\n", .{});
                break :blk alloc;
            }
        };

        for (0..cases.len) |j| {
            std.debug.print("{s}\n", .{cases[j].name});
            cases[j].run(alloc_for_this_loop);
        }
    }
}

fn caseReadBuffered4096(tester: *Tester, alloc: std.mem.Allocator) void {
    testReadBuffered(4096, tester, alloc) catch @panic("wtf?");
}

fn caseReadBuffered16384(tester: *Tester, alloc: std.mem.Allocator) void {
    testReadBuffered(16384, tester, alloc) catch @panic("wtf?");
}

fn caseReadFullFile(tester: *Tester, alloc: std.mem.Allocator) void {
    testReaderBufferFullFile(tester, alloc) catch @panic("wtf?");
}

fn testReadBuffered(size: comptime_int, tester: *Tester, alloc: std.mem.Allocator) !void {
    tester.restart();
    while (tester.continueTesting()) {
        var timer = try tester.beginTime();

        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();

        const file = try std.fs.cwd().openFile(json_file_name, .{});
        defer file.close();
        const file_reader = file.reader().any();

        var reader = json.Reader(size, @TypeOf(file_reader)).init(alloc, file_reader);
        while (try reader.nextWithAlloc(arena.allocator()) != .end_of_document) {}
        tester.countBytes(reader.bytesRead());

        try timer.end();
    }
}

fn testReaderBufferFullFile(tester: *Tester, alloc: std.mem.Allocator) !void {
    tester.restart();
    while (tester.continueTesting()) {
        var timer = try tester.beginTime();

        const file_content = try std.fs.cwd().readFileAlloc(alloc, json_file_name, std.math.maxInt(usize));
        defer alloc.free(file_content);

        var scanner = json.Scanner.initCompleteInput(alloc, file_content);
        defer scanner.deinit();
        while (try scanner.next() != .end_of_document) {}

        tester.countBytes(file_content.len);
        try timer.end();
    }
}
