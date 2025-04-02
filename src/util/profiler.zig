const std = @import("std");

const clock = @import("clock.zig");

pub fn Profiler(comptime blocks: anytype) type {
    const BlockType: type = blocks;
    const enum_len = @typeInfo(BlockType).@"enum".fields.len;
    return struct {
        const ProfilerType = @This();
        const AnchorData = struct {
            elapsed_exclusive: i64 = 0, // NOT including children
            elapsed_inclusive: u64 = 0, // including children
            processed_bytes_exclusive: u64 = 0,
            hits: u64 = 0,
        };
        pub const SpanScoped = struct {
            block: BlockType,
            parent_block: BlockType,

            ts_start: u64,
            old_elapsed_inclusive: u64,

            profiler: *ProfilerType,

            processed_bytes: u64 = 0,

            pub fn end(self: @This()) void {
                self.profiler.pop(self);
            }

            pub fn endWithThroughput(self: *@This(), bytes: u64) void {
                self.processed_bytes = bytes;
                self.end();
            }
        };

        anchors: [enum_len]AnchorData = [_]AnchorData{.{}} ** enum_len,

        ts_start: u64 = 0,
        active_block: BlockType,

        pub fn init(comptime root_block: BlockType) @This() {
            comptime std.debug.assert(@intFromEnum(root_block) == 0); // root block must be the first entry in the blocks enum
            return .{
                .active_block = root_block,
            };
        }

        pub fn begin(self: *@This()) void {
            self.ts_start = clock.rdtsc();
        }

        pub fn endAndPrintSummary(self: *@This()) void {
            std.debug.assert(self.active_block == @as(BlockType, @enumFromInt(0)));

            const now = clock.rdtsc();
            const elapsed = now - self.ts_start;

            self.anchors[0].elapsed_exclusive += @intCast(elapsed);
            self.anchors[0].elapsed_inclusive += @intCast(elapsed);
            self.anchors[0].hits += 1;

            logSummary(BlockType, self) catch return;
        }

        fn push(self: *@This(), block: BlockType) SpanScoped {
            const now = clock.rdtsc();
            const parent = self.active_block;
            self.active_block = block;
            return .{
                .block = block,
                .parent_block = parent,
                .old_elapsed_inclusive = self.anchors[@intFromEnum(block)].elapsed_inclusive,
                .ts_start = now,
                .profiler = self,
            };
        }

        fn pop(self: *@This(), to_pop: SpanScoped) void {
            std.debug.assert(to_pop.block == self.active_block);

            const elapsed = clock.rdtsc() - to_pop.ts_start;
            const parent_block: usize = @intFromEnum(to_pop.parent_block);
            const block: usize = @intFromEnum(to_pop.block);

            self.anchors[parent_block].elapsed_exclusive -= @intCast(elapsed);

            self.anchors[block].elapsed_exclusive += @intCast(elapsed);
            self.anchors[block].elapsed_inclusive = @intCast(to_pop.old_elapsed_inclusive + elapsed);
            self.anchors[block].hits += 1;
            self.anchors[block].processed_bytes_exclusive += to_pop.processed_bytes;

            self.active_block = to_pop.parent_block;
        }

        pub fn timeBlock(self: *@This(), block: BlockType) SpanScoped {
            return self.push(block);
        }
    };
}

pub fn logSummary(comptime block_type: anytype, profiler: *const Profiler(block_type)) !void {
    const max_block_name_width = comptime blk: {
        var max: u8 = 0;
        for (@typeInfo(block_type).@"enum".fields) |enum_field| {
            max = @max(max, enum_field.name.len);
        }
        break :blk max;
    };

    const max_hit_count_digits = blk: {
        var max_hits: u64 = 0;
        for (profiler.anchors) |anchor| {
            max_hits = @max(max_hits, anchor.hits);
        }
        break :blk countDigits(max_hits);
    };

    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    try writer.print("Estimating cpu frequency... ", .{});
    const cpuFreq = clock.estimateCpuFreq(100) catch unreachable;
    try writer.print(" {d} MHz\n", .{cpuFreq / (1000 * 1000)});

    const elapsed_total: u64 = profiler.anchors[0].elapsed_inclusive;
    const total_ms = elapsed_total * std.time.ms_per_s / cpuFreq;
    try writer.print("Counted {d} ticks (~{d} ms)\n", .{ elapsed_total, total_ms });

    for (profiler.anchors, 0..) |anchor, i| {
        const percent: f64 = 100.0 * (@as(f64, @floatFromInt(anchor.elapsed_exclusive)) / @as(f64, @floatFromInt(elapsed_total)));

        nosuspend {
            try writer.print("{0d: >5.2}% {1s: <[2]} [{3d: >[4]}] ({5} exclusive ticks", .{
                percent,
                @tagName(@as(block_type, @enumFromInt(i))),
                max_block_name_width,
                anchor.hits,
                max_hit_count_digits,
                anchor.elapsed_exclusive,
            });
            if (anchor.elapsed_exclusive != anchor.elapsed_inclusive) {
                const precent_with_children: f64 = 100.0 * (@as(f64, @floatFromInt(anchor.elapsed_inclusive)) / @as(f64, @floatFromInt(elapsed_total)));
                try writer.print(", {0d: >5.2}% w/ children", .{
                    precent_with_children,
                });
            }
            try writer.print(")\n", .{});

            if (anchor.processed_bytes_exclusive != 0) {
                const processed_mb = @as(f64, @floatFromInt(anchor.processed_bytes_exclusive)) / (1024.0 * 1024.0);
                const elapsed_inclusive_s = @as(f64, @floatFromInt(anchor.elapsed_inclusive)) / @as(f64, @floatFromInt(cpuFreq));
                const gb_per_s = 1.0 / (processed_mb / 1024.0) * elapsed_inclusive_s;
                try writer.print(" " ** (8 + max_block_name_width) ++ "{d:.3}MB @ {d:.3}GB/s\n", .{ processed_mb, gb_per_s });
            }

            try bw.flush();
        }
    }
}

fn countDigits(val: u64) u8 {
    if (val == 0) {
        return 1;
    }
    var digits: u8 = 0;
    var n = val;
    while (n > 0) {
        n /= 10;
        digits += 1;
    }
    return digits;
}

const TestBlocks = enum(u8) {
    root,
    foo,
    bar,
    recursive,
    _,
};

fn testRecursiveBlock(profiler: *Profiler(TestBlocks), depth: u8) !void {
    var span = profiler.timeBlock(.recursive);
    if (depth > 0) {
        try testRecursiveBlock(profiler, depth - 1);
    }
    span.end();
}

test "TestBlocks" {
    var profiler = Profiler(TestBlocks).init(.root);
    profiler.begin();
    try std.testing.expectEqual(@typeInfo(TestBlocks).@"enum".fields.len, profiler.anchors.len);

    try std.testing.expectEqual(.root, profiler.active_block);
    {
        var span_foo = profiler.timeBlock(.foo);
        try std.testing.expectEqual(.foo, profiler.active_block);
        {
            var span_bar = profiler.timeBlock(.bar);
            try std.testing.expectEqual(.bar, profiler.active_block);

            try testRecursiveBlock(&profiler, 2);

            span_bar.end();
        }
        try std.testing.expectEqual(.foo, profiler.active_block);
        span_foo.end();
    }
    try std.testing.expectEqual(.root, profiler.active_block);

    profiler.endAndPrintSummary();
}
