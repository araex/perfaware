const std = @import("std");
const builtin = @import("builtin");

const clock = @import("clock.zig");

const enable_trace = true;

ts_start: if (enable_trace) TracePoint else struct {},

pub fn start(comptime id: []const u8) @This() {
    if (enable_trace) {
        const now = clock.rdtsc();
        return .{
            .ts_start = .{
                .id = id,
                .timestamp = now,
            },
        };
    } else return .{ .ts_start = .{} };
}

pub fn end(self: @This(), comptime writer: fn (dur: TraceDuration) void) void {
    if (!enable_trace) {
        return;
    }

    const now = clock.rdtsc();
    const duration = TraceDuration{
        .id = self.ts_start.id,
        .duration = now - self.ts_start.timestamp,
    };
    writer(duration);
}

pub const TracePoint = struct {
    id: []const u8,
    timestamp: u64,
};

pub const TraceDuration = struct {
    id: []const u8,
    duration: u64,
};

pub fn toMicroseconds(dur: TraceDuration, cpuFreq: u64) TraceDuration {
    // 1.0 / @as(f64, @floatFromInt(cpuFreq)) * @as(f64, @floatFromInt(dur.duration))

    return TraceDuration{
        .id = dur.id,
        .duration = dur.duration * std.time.us_per_s / cpuFreq,
    };
}
