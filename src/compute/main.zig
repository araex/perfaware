const std = @import("std");

const haversine = @import("haversine");
const util = @import("util");

const json = @import("json.zig");

const Error = error{UnexpectedToken};

const earth_radius = 6372.8;

const Blocks = enum {
    main,
    open_files,
    compute,
    compute_read_pair_from_json,
    compute_haversine,
};
const enable_profiling = true;
var profiler = if (enable_profiling)
    util.Profiler(Blocks).init(.main)
else
    util.ProfilerNoop(Blocks).init(.main);

pub fn main() !void {
    profiler.begin();
    defer profiler.endAndPrintSummary();

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
    var span = profiler.timeBlock(.open_files);
    defer span.end();

    const json_file = blk: {
        break :blk try std.fs.cwd().openFile(args[1], .{});
    };

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
    var span = profiler.timeBlock(.compute);
    defer span.end();

    var arena = std.heap.ArenaAllocator.init(alloc_in);
    defer arena.deinit();
    const alloc = arena.allocator();

    var reader = json.reader(alloc, reader_in);
    defer reader.deinit();

    try skipUntilAfterArrayBegin(&reader, alloc);

    var sum: f64 = 0;
    var count: usize = 0;

    while (try reader.peekNextTokenType() != .array_end) {
        const pair = blk: {
            var span_read = profiler.timeBlock(.compute_read_pair_from_json);
            const bytes_before = reader.bytesRead();
            defer span_read.endWithThroughput(reader.bytesRead() - bytes_before);
            break :blk try readPair(&reader, alloc);
        };

        const haversine_distance = blk: {
            var span_compute = profiler.timeBlock(.compute_haversine);
            defer span_compute.endWithThroughput(@sizeOf(Pair));
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
