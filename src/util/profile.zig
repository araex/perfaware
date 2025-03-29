const std = @import("std");
const builtin = @import("builtin");

const clock = @import("clock.zig");

const enable_trace = true;

const capacity = if (enable_trace) 50 else 0;
var duration_storage: std.BoundedArray(Duration, capacity) = .{};

pub fn timeFunction(comptime src: std.builtin.SourceLocation) Span {
    return Span.init(src.fn_name, false);
}

pub fn timeBlock(comptime src: std.builtin.SourceLocation, comptime name: []const u8) Span {
    return Span.init(std.fmt.comptimePrint("{s}:{s}", .{ src.fn_name, name }), false);
}

pub fn pausedSpan(comptime src: std.builtin.SourceLocation, comptime name: []const u8) Span {
    return Span.init(std.fmt.comptimePrint("{s}:{s}", .{ src.fn_name, name }), true);
}

pub fn logSummary() void {
    if (!enable_trace) {
        return;
    }

    std.log.info("Estimating cpu frequency...", .{});
    const cpuFreq = clock.estimateCpuFreq(100) catch unreachable;
    std.log.info("Guess: {d} MHz", .{cpuFreq / (1000 * 1000)});

    const total_elapsed = blk: {
        var sum: u64 = 0;
        for (duration_storage.slice()) |dur| {
            sum += dur.duration;
        }
        break :blk sum;
    };
    const total_ms = total_elapsed * std.time.ms_per_s / cpuFreq;

    const time_header = "[ms]";
    const max_time_digits: u8 = blk: {
        var digits: u8 = 1;
        var value = total_ms;
        while (value >= 10) : (value /= 10) {
            digits += 1;
        }
        break :blk @max(digits, time_header.len);
    };

    std.log.info("{[header]s: >[max_digits]} |        | Name", .{
        .header = time_header,
        .max_digits = max_time_digits,
    });
    std.log.info("------------------------------", .{});

    var i = duration_storage.len;
    while (i > 0) {
        i -= 1;

        const dur = duration_storage.buffer[i];
        const ms = dur.duration * std.time.ms_per_s / cpuFreq;
        const percentage = @as(f64, @floatFromInt(dur.duration)) * 100.0 / @as(f64, @floatFromInt(total_elapsed));
        std.log.info("{[time]: >[max_digits]} | {[percentage]d: >5.2}% | {[id]s}", .{
            .time = ms,
            .percentage = percentage,
            .max_digits = max_time_digits,
            .id = dur.id,
        });
    }

    std.log.info("------------------------------", .{});
}

pub const Span = if (enable_trace) SpanImpl else SpanDisabled;
pub const SpanImpl = struct {
    id: []const u8,
    paused: bool,
    ts_start: u64 = 0,
    duration: u64 = 0,

    fn init(comptime id: []const u8, comptime start_paused: bool) @This() {
        const now = clock.rdtsc();
        return .{
            .id = id,
            .paused = start_paused,
            .ts_start = now,
        };
    }

    pub fn start(self: *@This()) void {
        self.ts_start = clock.rdtsc();
        self.paused = false;
    }

    pub fn pause(self: *@This()) void {
        if (self.paused) return;
        const now = clock.rdtsc();
        self.duration += (now - self.ts_start);
        self.paused = true;
    }

    pub fn deinit(self: *@This()) void {
        self.pause();
        duration_storage.append(Duration{
            .id = self.id,
            .duration = self.duration,
        }) catch unreachable;
    }
};

pub const SpanDisabled = struct {
    fn init(comptime id: []const u8, comptime start_paused: bool) @This() {
        _ = id;
        _ = start_paused;
        return .{};
    }

    pub fn start(self: *@This()) void {
        _ = self;
    }

    pub fn pause(self: *@This()) void {
        _ = self;
    }

    pub fn deinit(self: @This()) void {
        _ = self;
    }
};

pub const Duration = struct {
    id: []const u8,
    duration: u64,
};
