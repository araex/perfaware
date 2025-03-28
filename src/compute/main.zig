const std = @import("std");

const clock = @import("util").clock;
const haversine = @import("haversine");
const span = @import("util").span;

const json = @import("json.zig");

const Error = error{UnexpectedToken};

const earth_radius = 6372.8;

var durations: std.BoundedArray(span.TraceDuration, 20) = .{};
fn pushDuration(dur: span.TraceDuration) void {
    durations.append(dur) catch unreachable;
}

fn printDurations() void {
    std.log.info("\nEstimating cpu frequency...", .{});
    const cpuFreq = clock.estimateCpuFreq(500) catch unreachable;
    std.log.info("{d}Hz", .{cpuFreq});

    var i = durations.len;
    while (i > 0) {
        i -= 1;
        const us = span.toMicroseconds(durations.buffer[i], cpuFreq);
        std.log.info("{d: >8}us {s}", .{ us.duration, us.id });
    }
}

pub fn main() !void {
    defer printDurations();

    const main_span = span.start("main");
    defer main_span.end(pushDuration);

    var gpa = std.heap.DebugAllocator(.{}).init;

    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} [pairs.json] [compare binary]", .{args[0]});
        return error.InvalidArgument;
    }

    const file_data = try openFiles(args);
    defer {
        file_data.json_file.close();
        if (file_data.result_file) |file| file.close();
    }

    const sum = try computeAvgHaversine(alloc, file_data.json_file.reader().any(), file_data.result_reader);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Computed sum: {d}\n", .{sum});

    if (file_data.result_reader) |expected_reader| {
        const raw = try expected_reader.readBoundedBytes(8);
        const expected_haversine = std.mem.bytesAsValue(f64, &raw.buffer);
        try stdout.print("Expected sum: {d}\n", .{expected_haversine.*});
    }
}

const FileData = struct {
    json_file: std.fs.File,
    result_file: ?std.fs.File,
    result_reader: ?std.io.AnyReader,
};

fn openFiles(args: []const []const u8) !FileData {
    const main_span = span.start("  openFiles");
    defer main_span.end(pushDuration);

    const json_file = try std.fs.cwd().openFile(args[1], .{});

    const result_file: ?std.fs.File = blk: {
        if (args.len > 2) {
            break :blk try std.fs.cwd().openFile(args[2], .{});
        }
        break :blk null;
    };
    const result_reader = if (result_file) |file| file.reader().any() else null;

    return .{
        .json_file = json_file,
        .result_file = result_file,
        .result_reader = result_reader,
    };
}

fn computeAvgHaversine(alloc_in: std.mem.Allocator, reader_in: std.io.AnyReader, expected: ?std.io.AnyReader) !f64 {
    const main_span = span.start("  computeAvgHaversine");
    defer main_span.end(pushDuration);
    var arena = std.heap.ArenaAllocator.init(alloc_in);
    defer arena.deinit();
    const alloc = arena.allocator();

    var reader = json.reader(alloc, reader_in);
    defer reader.deinit();

    {
        const inner_span = span.start("    skipUntilAfterArrayBegin");
        try skipUntilAfterArrayBegin(&reader, alloc);
        inner_span.end(pushDuration);
    }

    var sum: f64 = 0;
    var count: usize = 0;
    var rdtsc_read: u64 = 0;
    var rdtsc_compute: u64 = 0;
    while (try reader.peekNextTokenType() != .array_end) {
        const pair = blk: {
            const before = clock.rdtsc();
            defer rdtsc_read += (clock.rdtsc() - before);
            break :blk try readPair(&reader, alloc);
        };
        // std.debug.print("    {{\"x0\":{d:.16}, \"y0\":{d:.16}, \"x1\":{d:.16}, \"y1\":{d:.16}}}\n", .{ pair.x0, pair.y0, pair.x1, pair.y1 });

        const haversine_distance = blk: {
            const before = clock.rdtsc();
            defer rdtsc_compute += (clock.rdtsc() - before);
            break :blk haversine.compute_reference(pair.x0, pair.y0, pair.x1, pair.y1, earth_radius);
        };

        if (expected) |expected_reader| {
            const raw = try expected_reader.readBoundedBytes(8);
            const expected_haversine = std.mem.bytesAsValue(f64, &raw.buffer);
            try std.testing.expectApproxEqRel(expected_haversine.*, haversine_distance, 1e-8);
        }
        sum += haversine_distance;
        count += 1;
    }
    pushDuration(span.TraceDuration{
        .id = "    readPair",
        .duration = rdtsc_read,
    });
    pushDuration(span.TraceDuration{
        .id = "    haversine.compute_reference",
        .duration = rdtsc_compute,
    });
    return sum / @as(f64, @floatFromInt(count));
}

const Pair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

fn readPair(json_reader: anytype, alloc: std.mem.Allocator) !Pair {
    var token = try json_reader.nextWithAlloc(alloc);
    if (token != .object_begin) return Error.UnexpectedToken;

    try skipString(json_reader, alloc, "x0");
    const x0 = try readF64(json_reader, alloc);
    try skipString(json_reader, alloc, "y0");
    const y0 = try readF64(json_reader, alloc);
    try skipString(json_reader, alloc, "x1");
    const x1 = try readF64(json_reader, alloc);
    try skipString(json_reader, alloc, "y1");
    const y1 = try readF64(json_reader, alloc);

    token = try json_reader.nextWithAlloc(alloc);
    if (token != .object_end) return Error.UnexpectedToken;

    return .{
        .x0 = x0,
        .y0 = y0,
        .x1 = x1,
        .y1 = y1,
    };
}

fn skipString(json_reader: anytype, alloc: std.mem.Allocator, expected_string_val: []const u8) !void {
    switch (try json_reader.nextWithAlloc(alloc)) {
        .string, .allocated_string => |s| {
            if (!std.mem.eql(u8, expected_string_val, s)) return Error.UnexpectedToken;
        },
        else => return Error.UnexpectedToken,
    }
}

fn readF64(json_reader: anytype, alloc: std.mem.Allocator) !f64 {
    switch (try json_reader.nextWithAlloc(alloc)) {
        .number, .allocated_number => |num| return std.fmt.parseFloat(f64, num),
        else => return Error.UnexpectedToken,
    }
}

fn skipUntilAfterArrayBegin(json_reader: anytype, alloc: std.mem.Allocator) !void {
    var token = try json_reader.nextWithAlloc(alloc);
    if (token != .object_begin) return Error.UnexpectedToken;

    try skipString(json_reader, alloc, "pairs");

    token = try json_reader.nextWithAlloc(alloc);
    if (token != .array_begin) return Error.UnexpectedToken;
}
