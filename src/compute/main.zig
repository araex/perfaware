const std = @import("std");

const haversine = @import("haversine");

const json = @import("json.zig");

const Error = error{UnexpectedToken};

const earth_radius = 6372.8;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;

    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} [pairs.json] [compare binary]", .{args[0]});
        return error.InvalidArgument;
    }

    const json_file = try std.fs.cwd().openFile(args[1], .{});
    defer json_file.close();

    const result_file: ?std.fs.File = blk: {
        if (args.len > 2) {
            break :blk try std.fs.cwd().openFile(args[2], .{});
        }
        break :blk null;
    };
    defer if (result_file) |file| file.close();
    const result_reader = if (result_file) |file| file.reader().any() else null;

    const sum = try computeAvgHaversine(alloc, json_file.reader().any(), result_reader);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Computed sum: {d}\n", .{sum});

    if (result_reader) |expected_reader| {
        const raw = try expected_reader.readBoundedBytes(8);
        const expected_haversine = std.mem.bytesAsValue(f64, &raw.buffer);
        try stdout.print("Expected sum: {d}\n", .{expected_haversine.*});
    }
}

fn computeAvgHaversine(alloc_in: std.mem.Allocator, reader_in: std.io.AnyReader, expected: ?std.io.AnyReader) !f64 {
    var arena = std.heap.ArenaAllocator.init(alloc_in);
    defer arena.deinit();
    const alloc = arena.allocator();

    var reader = json.reader(alloc, reader_in);
    defer reader.deinit();

    try skipUntilAfterArrayBegin(&reader, alloc);

    var sum: f64 = 0;
    var count: usize = 0;
    while (try reader.peekNextTokenType() != .array_end) {
        const pair = try readPair(&reader, alloc);
        // std.debug.print("    {{\"x0\":{d:.16}, \"y0\":{d:.16}, \"x1\":{d:.16}, \"y1\":{d:.16}}}\n", .{ pair.x0, pair.y0, pair.x1, pair.y1 });
        const haversine_distance = haversine.compute_reference(pair.x0, pair.y0, pair.x1, pair.y1, earth_radius);
        if (expected) |expected_reader| {
            const raw = try expected_reader.readBoundedBytes(8);
            const expected_haversine = std.mem.bytesAsValue(f64, &raw.buffer);
            try std.testing.expectApproxEqRel(expected_haversine.*, haversine_distance, 1e-8);
        }
        // std.debug.print("  -> {d:.16}\n", .{haversine_distance});
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

test "json parser" {
    const in =
        \\{
        \\  "string": "foo",
        \\  "int": 42,
        \\  "float": 3.14,
        \\  "object": {
        \\      "nested string": "bar"
        \\  }
        \\}
    ;

    const alloc = std.testing.allocator;

    var buffer = std.io.fixedBufferStream(in);
    const reader = buffer.reader();
    var json_reader = json.reader(alloc, reader.any());
    defer json_reader.deinit();

    try std.testing.expectEqualDeep(.object_begin, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(json.Token{
        .string = "string",
    }, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(json.Token{
        .string = "foo",
    }, try json_reader.nextWithAlloc(alloc));

    try std.testing.expectEqualDeep(json.Token{
        .string = "int",
    }, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(json.Token{
        .number = "42",
    }, try json_reader.nextWithAlloc(alloc));

    try std.testing.expectEqualDeep(json.Token{
        .string = "float",
    }, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(json.Token{
        .number = "3.14",
    }, try json_reader.nextWithAlloc(alloc));

    // nested object
    try std.testing.expectEqualDeep(json.Token{
        .string = "object",
    }, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(.object_begin, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(json.Token{
        .string = "nested string",
    }, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(json.Token{
        .string = "bar",
    }, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(.object_end, try json_reader.nextWithAlloc(alloc));

    try std.testing.expectEqualDeep(.object_end, try json_reader.nextWithAlloc(alloc));
    try std.testing.expectEqualDeep(.end_of_document, try json_reader.nextWithAlloc(alloc));
}
