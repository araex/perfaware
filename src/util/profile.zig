const std = @import("std");
const builtin = @import("builtin");

const clock = @import("clock.zig");

const Errors = error{SpanStillOpen};

var profiler: Profiler = undefined;
const Profiler = struct {
    const SpanId = []const u8;
    const SpanIndex = usize;
    const Span = struct {
        id: SpanId,
        parent_idx: SpanIndex,
        ts_start: u64,
        ts_end: u64 = 0,

        fn elapsed(self: @This()) u64 {
            return self.ts_end - self.ts_start;
        }
    };

    alloc: std.mem.Allocator,
    spans: std.ArrayList(Span),
    active_idx: SpanIndex,

    fn init(alloc: std.mem.Allocator, comptime root_id: SpanId) !@This() {
        const now = clock.rdtsc();
        var self = @This(){
            .alloc = alloc,
            .spans = std.ArrayList(Span).init(alloc),
            .active_idx = 0,
        };
        try self.spans.append(Span{
            .id = root_id,
            .parent_idx = 0,
            .ts_start = now,
        });
        return self;
    }

    fn end(self: *@This()) !std.ArrayList(Span) {
        const now = clock.rdtsc();
        if (self.active_idx != 0) return error.SpanStillOpen;

        self.spans.items[0].ts_end = now;
        const spans = self.spans;
        self.* = undefined;
        return spans;
    }

    fn push(self: *@This(), comptime id: SpanId) !SpanScope {
        const now = clock.rdtsc();
        try self.spans.append(Span{
            .id = id,
            .parent_idx = self.active_idx,
            .ts_start = now,
        });
        self.active_idx = (self.spans.items.len - 1);
        return .{
            .idx = self.active_idx,
        };
    }

    fn pop(self: *@This()) void {
        const now = clock.rdtsc();
        std.debug.assert(self.active_idx != 0); // internal error: can't pop the root node
        std.debug.assert(self.active_idx < self.spans.items.len);
        std.debug.assert(self.spans.items[self.active_idx].ts_end == 0);

        self.spans.items[self.active_idx].ts_end = now;
        const parent = self.spans.items[self.active_idx].parent_idx;
        self.active_idx = parent;
    }
};

pub const SpanScope = struct {
    idx: Profiler.SpanIndex,
    pub fn end(self: @This()) void {
        std.debug.assert(self.idx == profiler.active_idx);

        profiler.pop();
    }
};

pub fn begin(alloc: std.mem.Allocator, comptime src: std.builtin.SourceLocation) !void {
    profiler = try Profiler.init(alloc, src.fn_name);
}

pub fn endAndPrintSummary() !void {
    const alloc = profiler.alloc;
    const spans = try profiler.end();
    try logSummary(alloc, spans.items);
}

pub fn timeFunction(comptime src: std.builtin.SourceLocation) !SpanScope {
    return try profiler.push(src.fn_name);
}

pub fn timeBlock(comptime _: std.builtin.SourceLocation, comptime name: []const u8) !SpanScope {
    return try profiler.push(name);
}

pub fn logSummary(alloc: std.mem.Allocator, spans: []const Profiler.Span) !void {
    std.log.info("Estimating cpu frequency...", .{});
    const cpuFreq = clock.estimateCpuFreq(100) catch unreachable;
    std.log.info("Guess: {d} MHz", .{cpuFreq / (1000 * 1000)});

    const total_elapsed = spans[0].elapsed();
    const total_ms = total_elapsed * std.time.ms_per_s / cpuFreq;
    std.log.info("Counted {d} ticks (~{d} ms)", .{ total_elapsed, total_ms });

    // Merge spans with same parent & id into a single "group"
    var groups = std.ArrayList(Group).init(alloc);
    defer groups.deinit();
    var i: usize = 1;
    var max_depth: u8 = 0;
    while (i < spans.len) : (i += 1) {
        const span = spans[i];
        const elapsed = span.elapsed();
        var found = false;
        var j: usize = 0;
        while (j < groups.items.len) : (j += 1) {
            if (groups.items[j].parent_idx == span.parent_idx and std.mem.eql(u8, groups.items[j].id, span.id)) {
                groups.items[j].total_elapsed += elapsed;
                groups.items[j].hits += 1;
                found = true;
                break;
            }
        }
        if (!found) {
            const depth = computeDepth(spans, i);
            try groups.append(Group{
                .parent_idx = span.parent_idx,
                .id = span.id,
                .child_idx = i, // store this span's index for recursion
                .total_elapsed = elapsed,
                .hits = 1,
                .depth = depth,
            });
            max_depth = @max(max_depth, depth);
        }
    }

    // Indent for pretty printing
    var indent_buf = try std.ArrayList(u8).initCapacity(alloc, max_depth);
    indent_buf.appendNTimesAssumeCapacity(' ', max_depth);

    // Start printing from root
    print_children(0, 0, spans, &groups, indent_buf.items);

    // Memory consumption
    const total_size = spans.len * @sizeOf(Profiler.Span);
    std.log.info("Profiling used ~{d:.3}MB of memory", .{@as(f64, @floatFromInt(total_size)) / (1024.0 * 1024.0)});
}

const Group = struct {
    parent_idx: Profiler.SpanIndex,
    id: []const u8,
    child_idx: Profiler.SpanIndex,
    total_elapsed: u64,
    hits: u32,
    depth: u8,
};

fn print_children(
    parent_idx: Profiler.SpanIndex,
    depth: u8,
    spans: []const Profiler.Span,
    groups: *std.ArrayList(Group),
    indent_buf: []u8,
) void {
    const parent_elapsed = spans[parent_idx].elapsed();

    // Sum total elapsed for all groups whose parent is parent_idx
    var children_elapsed: u64 = 0;
    var m: usize = 0;
    while (m < groups.items.len) : (m += 1) {
        if (groups.items[m].parent_idx == parent_idx) {
            children_elapsed += groups.items[m].total_elapsed;
        }
    }
    // Print each child group and recursively print its own children.
    m = 0;
    while (m < groups.items.len) : (m += 1) {
        const grp = groups.items[m];
        if (grp.parent_idx == parent_idx) {
            const percent = if (children_elapsed != 0)
                @as(f64, @floatFromInt(grp.total_elapsed)) * 100.0 / @as(f64, @floatFromInt(parent_elapsed))
            else
                0.0;
            std.log.info("{s}┠─ {d: >5.2}% {s}, {d} hits, {d} ticks total", .{
                indent_buf[0..(depth + 1)],
                percent,
                grp.id,
                grp.hits,
                grp.total_elapsed,
            });
            // Recurse using grp.child_idx as the parent's span index for the next level.
            print_children(grp.child_idx, depth + 1, spans, groups, indent_buf);
        }
    }
    // Print parent's self ("other") time if parent has children.
    if (children_elapsed > 0) {
        const self_time = if (parent_elapsed > children_elapsed) parent_elapsed - children_elapsed else 0;
        const percent = if (parent_elapsed != 0)
            @as(f64, @floatFromInt(self_time)) * 100.0 / @as(f64, @floatFromInt(parent_elapsed))
        else
            0.0;
        std.log.info("{s}┖─ {d: >5.2}% other, {d} ticks", .{
            indent_buf[0..(depth + 1)],
            percent,
            self_time,
        });
    }
}

fn computeDepth(spans: []const Profiler.Span, idx: usize) u8 {
    var depth: u8 = 0;
    var curr = idx;
    while (curr != 0) : (curr = spans[curr].parent_idx) {
        depth += 1;
    }
    return depth;
}
