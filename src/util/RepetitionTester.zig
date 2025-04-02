const std = @import("std");

const clock = @import("clock.zig");

const RepititionTester = @This();

pub const Result = struct {
    min: u64 = std.math.maxInt(u64),
    max: u64 = 0,
    byte_count: ?u64 = null,
};

const State = enum {
    testing,
    done,
};

start_time: std.time.Instant,
try_for_s: u64,

state: State,
curr_iter_cpu_time: u64 = 0,
curr_iter_byte_count: ?u64 = null,
curr_begin_time_calls: u32 = 0,
curr_end_time_calls: u32 = 0,

result: Result = .{},
cpu_freq: u64,

pub fn init(cpu_freq: u64, try_for_s: u64) !@This() {
    return .{
        .start_time = try std.time.Instant.now(),
        .try_for_s = try_for_s,
        .state = .testing,
        .cpu_freq = cpu_freq,
    };
}

pub fn restart(self: *@This()) void {
    self.state = .testing;
    self.start_time = std.time.Instant.now() catch unreachable;
}

pub fn continueTesting(self: *@This()) bool {
    switch (self.state) {
        .done => return false,
        .testing => {
            if (self.curr_begin_time_calls == 0) {
                return true;
            }

            if (self.curr_begin_time_calls != self.curr_end_time_calls) {
                @panic("unbalanced begin / end calls");
            }

            if (self.curr_iter_byte_count != null and self.result.byte_count == null) {
                // First iteration
                self.result.byte_count = self.curr_iter_byte_count;
            } else if (self.curr_iter_byte_count != self.result.byte_count) {
                std.debug.print("{any} vs {any}", .{ self.curr_iter_byte_count, self.result.byte_count });
                @panic("Byte count changed between iterations. Can't compare.");
            }

            var found_new_best: bool = false;
            self.result.max = @max(self.result.max, self.curr_iter_cpu_time);
            if (self.curr_iter_cpu_time < self.result.min) {
                found_new_best = true;
                self.result.min = self.curr_iter_cpu_time;
                self.start_time = std.time.Instant.now() catch unreachable;
            }

            self.curr_iter_cpu_time = 0;
            self.curr_iter_byte_count = null;
            self.curr_begin_time_calls = 0;
            self.curr_end_time_calls = 0;

            if (found_new_best) {
                self.updateMin();
            }

            const now = std.time.Instant.now() catch unreachable;
            if (now.since(self.start_time) / std.time.ns_per_s > self.try_for_s) {
                self.state = .done;
                std.debug.print("\r", .{});
                self.printResults();
                return false;
            }

            return true;
        },
    }
}

pub const ScopedTime = struct {
    ts_start: u64,
    tester: *RepititionTester,

    pub fn end(self: *@This()) void {
        const now = clock.rdtsc();
        self.tester.curr_iter_cpu_time = now - self.ts_start;
        self.tester.curr_end_time_calls += 1;
    }
};

pub fn beginTime(self: *@This()) ScopedTime {
    self.curr_begin_time_calls += 1;
    return .{
        .ts_start = clock.rdtsc(),
        .tester = self,
    };
}

pub fn countBytes(self: *@This(), byte_count: u64) void {
    self.curr_iter_byte_count = byte_count;
}

fn printCPUTime(prefix: []const u8, val: u64, byte_count: ?u64, cpu_freq: u64) void {
    const millis = clock.toMilliseconds(val, cpu_freq);
    std.debug.print("{s}{d:.2}ms", .{ prefix, millis });
    if (byte_count) |b| {
        const mb = @as(f64, @floatFromInt(b)) / (1024.0 * 1024.0);
        const gb = mb / 1024.0;
        const gbps = gb / (millis / 1000.0);
        std.debug.print(", {d:.3}MB @ {d:.3}GB/s", .{ mb, gbps });
    }
}

fn updateMin(self: @This()) void {
    printCPUTime("\r Min: ", self.result.min, self.result.byte_count, self.cpu_freq);
}

fn printResults(self: @This()) void {
    printCPUTime(" Min: ", self.result.min, self.result.byte_count, self.cpu_freq);
    printCPUTime("\n Max: ", self.result.max, self.result.byte_count, self.cpu_freq);
    std.debug.print("\n", .{});
}
