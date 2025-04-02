const std = @import("std");
const root = @import("root");

pub fn estimateCpuFreq(millisToWait: u64) error{Unsupported}!u64 {
    if (millisToWait == 0) {
        return 0;
    }

    const cpuStart = rdtsc();
    const osStart = try std.time.Instant.now();
    var osEnd: std.time.Instant = undefined;
    var elapsedNanos: u64 = 0;
    while ((elapsedNanos / std.time.ns_per_ms) < millisToWait) {
        osEnd = try std.time.Instant.now();
        elapsedNanos = osEnd.since(osStart);
    }
    const cpuEnd = rdtsc();
    const cpuElapsed = cpuEnd - cpuStart;
    // std.debug.print("Elapsed while waiting {d}ms:\n", .{millisToWait});
    // std.debug.print("rdtsc:    {d:.11} -> {d:.11} = {d:.11}\n", .{ cpuStart, cpuEnd, cpuElapsed });
    const osElapsedMillis = osEnd.since(osStart) / std.time.ns_per_ms;
    // std.debug.print("OS:       {d:.11} -> {d:.11} = {d:.11}ms\n", .{ osStart.timestamp, osEnd.timestamp, osElapsedMillis });
    const cpuFreq = cpuElapsed / osElapsedMillis * 1000;
    // std.debug.print("Cpu Freq: {d:.11} (guessed)\n", .{cpuFreq});
    return cpuFreq;
}

pub fn rdtsc() u64 {
    var hi: u64 = 0;
    var lo: u64 = 0;
    asm volatile ("rdtsc"
        : [a] "={eax}" (lo),
          [b] "={edx}" (hi),
    );
    return (hi << 32) | lo;
}

pub fn toSeconds(cpu_time: u64, cpu_freq: u64) f64 {
    return @as(f64, @floatFromInt(cpu_time)) / @as(f64, @floatFromInt(cpu_freq));
}

pub fn toMilliseconds(cpu_time: u64, cpu_freq: u64) f64 {
    return toSeconds(cpu_time, cpu_freq) * std.time.ms_per_s;
}
