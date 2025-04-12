const std = @import("std");

const clock = @import("clock.zig");
const platform = @import("platform.zig");

const RepititionTester = @This();

pub const Result = struct {
    fastest_run: ?Run = null,
    slowest_run: ?Run = null,

    // Add tracking for average calculation
    total_cpu_time: u64 = 0,
    total_page_faults: u64 = 0,
    total_byte_count: u64 = 0,
    run_count: u32 = 0,

    // Function to get the average run
    pub fn getAverageRun(self: @This(), cpu_freq: u64) ?Run {
        if (self.run_count == 0) return null;

        return Run{
            .cpu_freq = cpu_freq,
            .cpu_time = self.total_cpu_time / self.run_count,
            .page_faults = @intCast(self.total_page_faults / self.run_count),
            .byte_count = self.total_byte_count / self.run_count,
            .begin_time_calls = 1,
            .end_time_calls = 1,
        };
    }
};

const Run = struct {
    cpu_freq: u64,
    cpu_time: u64 = 0,
    page_faults: u32 = 0,
    byte_count: u64 = 0,
    begin_time_calls: u32 = 0,
    end_time_calls: u32 = 0,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const millis = clock.toMilliseconds(self.cpu_time, self.cpu_freq);
        try writer.print("{d} ({d:.2}ms)", .{ self.cpu_time, millis });
        if (self.byte_count > 0) {
            const kb = @as(f64, @floatFromInt(self.byte_count)) / 1024.0;
            const mb = kb / 1024.0;
            const gb = mb / 1024.0;
            const gbps = gb / (millis / 1000.0);
            try writer.print(", {d:.3}MB @ {d:.3}GB/s, {d} page faults", .{ mb, gbps, self.page_faults });
            if (self.page_faults > 0) {
                const kbppf = kb / @as(f64, @floatFromInt(self.page_faults));
                try writer.print(" @ {d:.3}KB per page fault", .{kbppf});
            }
        }
    }
};

const State = enum {
    testing,
    done,
};

start_time: std.time.Instant,
try_for_s: u64,

state: State,
run: Run,

result: Result = .{},
cpu_freq: u64,

pub fn init(cpu_freq: u64, try_for_s: u64) !@This() {
    return .{
        .start_time = try std.time.Instant.now(),
        .try_for_s = try_for_s,
        .state = .testing,
        .run = Run{
            .cpu_freq = cpu_freq,
        },
        .cpu_freq = cpu_freq,
    };
}

pub fn restart(self: *@This()) void {
    self.state = .testing;
    self.run = .{
        .cpu_freq = self.cpu_freq,
    };
    self.start_time = std.time.Instant.now() catch unreachable;
}

pub fn continueTesting(self: *@This()) bool {
    switch (self.state) {
        .done => return false,
        .testing => {
            const last_run = self.run;
            self.run = .{
                .cpu_freq = self.cpu_freq,
            };

            if (last_run.begin_time_calls == 0) {
                return true;
            }

            if (last_run.begin_time_calls != last_run.end_time_calls) {
                @panic("unbalanced begin / end calls");
            }

            const is_first_iteration = self.result.fastest_run == null;
            if (is_first_iteration) {
                self.result.fastest_run = last_run;
                self.result.slowest_run = last_run;

                // Initialize average tracking with first run
                self.result.total_cpu_time += last_run.cpu_time;
                self.result.total_page_faults += last_run.page_faults;
                self.result.total_byte_count += last_run.byte_count;
                self.result.run_count += 1;

                return true;
            }

            // Fix naming to be consistent with what the variables represent
            const fastest = self.result.fastest_run orelse unreachable;
            const slowest = self.result.slowest_run orelse unreachable;
            std.debug.assert(fastest.byte_count == slowest.byte_count);

            if (last_run.byte_count != fastest.byte_count) {
                std.debug.print("{any} vs {any}", .{ last_run.byte_count, fastest.byte_count });
                @panic("Byte count changed between iterations. Can't compare.");
            }

            const now = std.time.Instant.now() catch unreachable;

            // Correct comparison logic: smallest time is fastest, largest time is slowest
            if (last_run.cpu_time > slowest.cpu_time) {
                self.result.slowest_run = last_run;
            } else if (last_run.cpu_time < fastest.cpu_time) {
                self.result.fastest_run = last_run;
                self.start_time = now;
                self.updateMinPrint();
            }

            // Update average tracking
            self.result.total_cpu_time += last_run.cpu_time;
            self.result.total_page_faults += last_run.page_faults;
            self.result.total_byte_count += last_run.byte_count;
            self.result.run_count += 1;

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
    page_faults_start: u32,
    tester: *RepititionTester,

    pub fn end(self: *@This()) !void {
        const now = clock.rdtsc();
        const page_faults_end = try platform.readPageFaultCount();
        self.tester.run.cpu_time = now - self.ts_start;
        self.tester.run.page_faults += (page_faults_end - self.page_faults_start);
        self.tester.run.end_time_calls += 1;
    }
};

pub fn beginTime(self: *@This()) !ScopedTime {
    self.run.begin_time_calls += 1;
    return .{
        .ts_start = clock.rdtsc(),
        .page_faults_start = try platform.readPageFaultCount(),
        .tester = self,
    };
}

pub fn countBytes(self: *@This(), byte_count: u64) void {
    self.run.byte_count += byte_count;
}

fn updateMinPrint(self: @This()) void {
    std.debug.print("\r                                                                                \r", .{});
    std.debug.print(" Min: {any}", .{self.result.fastest_run});
}

fn printResults(self: @This()) void {
    std.debug.print("\r                                                                                \r", .{});
    std.debug.print(" Min: {any}\n", .{self.result.fastest_run});
    std.debug.print(" Max: {any}\n", .{self.result.slowest_run});
    std.debug.print(" Avg: {any}\n", .{self.result.getAverageRun(self.cpu_freq)});
}
