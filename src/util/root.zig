const std = @import("std");
const root = @import("root");

pub const clock = @import("clock.zig");
pub const platform = @import("platform.zig");
pub const Profiler = @import("profiler.zig").Profiler;
pub const RepetitionTester = @import("RepetitionTester.zig");
pub const x64 = @import("x64.zig");

// Profiler that only measures total execution time. Can be used to turn off profiling completely at compiletime
pub fn ProfilerNoop(comptime blocks: anytype) type {
    const BlockType: type = blocks;
    return struct {
        pub const SpanScopedNoop = struct {
            pub fn end(_: @This()) void {}
        };

        ts_start: u64 = 0,
        pub fn init(comptime _: BlockType) @This() {
            return .{};
        }

        pub fn begin(self: *@This()) void {
            self.ts_start = clock.rdtsc();
        }

        pub fn endAndPrintSummary(self: *@This()) void {
            const now = clock.rdtsc();
            const elapsed = now - self.ts_start;

            std.debug.print("Estimating cpu frequency... ", .{});
            const cpuFreq = clock.estimateCpuFreq(100) catch unreachable;
            std.debug.print(" {d} MHz\n", .{cpuFreq / (1000 * 1000)});
            const total_ms = elapsed * std.time.ms_per_s / cpuFreq;
            std.debug.print("Counted {d} ticks (~{d} ms)\n", .{ elapsed, total_ms });
        }

        pub fn timeBlock(_: *@This(), _: BlockType) SpanScopedNoop {
            return .{};
        }
    };
}
