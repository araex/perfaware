const std = @import("std");

const clock = @import("util").clock;
const haversine = @import("haversine");
const profile = @import("util").profile;

const json = @import("json.zig");

const Error = error{UnexpectedToken};

const earth_radius = 6372.8;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const alloc = gpa.allocator();
    var profile_arena = std.heap.ArenaAllocator.init(alloc);
    defer profile_arena.deinit();

    try profile.begin(profile_arena.allocator(), @src());

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

    try profile.endAndPrintSummary();
}

const FileData = struct {
    json_file: std.fs.File,
    result_file: ?std.fs.File,
    result_reader: ?std.io.AnyReader,
};

fn openFiles(args: []const []const u8) !FileData {
    var span = try profile.timeFunction(@src());
    defer span.end();

    const json_file = blk: {
        var span_inner = try profile.timeBlock(@src(), "openFile(json)");
        defer span_inner.end();
        break :blk try std.fs.cwd().openFile(args[1], .{});
    };

    const result_file: ?std.fs.File = blk: {
        var span_inner = try profile.timeBlock(@src(), "openFile(result)");
        defer span_inner.end();
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
    var span = try profile.timeFunction(@src());
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
            var span_read = try profile.timeBlock(@src(), "read pair from json");
            defer span_read.end();
            break :blk try readPair(&reader, alloc);
        };
        // std.debug.print("    {{\"x0\":{d:.16}, \"y0\":{d:.16}, \"x1\":{d:.16}, \"y1\":{d:.16}}}\n", .{ pair.x0, pair.y0, pair.x1, pair.y1 });

        const haversine_distance = blk: {
            var span_compute = try profile.timeBlock(@src(), "compute haversine");
            defer span_compute.end();
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
    var span = try profile.timeFunction(@src());
    defer span.end();

    var token = try json_reader.nextWithAlloc(alloc);
    if (token != .object_begin) return Error.UnexpectedToken;

    try skipString(json_reader, alloc, "pairs");

    token = try json_reader.nextWithAlloc(alloc);
    if (token != .array_begin) return Error.UnexpectedToken;
}
