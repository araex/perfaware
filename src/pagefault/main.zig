const std = @import("std");

const platform = @import("util").platform;
const x64 = @import("util").x64;

const forward = true;
const assumed_page_size = 4096;
const page_count = 4096;

pub fn main() !void {
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer bw.flush() catch unreachable;
    const stdout = bw.writer();

    try stdout.print("Page Count,Touch Count,Fault Count,Extra Faults\n", .{});

    for (1..page_count) |touch_count| {
        const alloc_size = touch_count * assumed_page_size;
        const data = try platform.rawAlloc(alloc_size);
        defer platform.rawFree(data);

        const page_faults_start = try platform.readPageFaultCount();
        for (0..data.len) |j| {
            const idx = if (forward) j else (data.len - 1 - j);
            data[idx] = @truncate(@mod(j, @sizeOf(u8)));
        }
        const page_faults_end = try platform.readPageFaultCount();

        const fault_count = page_faults_end - page_faults_start;
        const extra_faults = @as(i32, @intCast(fault_count)) - @as(i32, @intCast(touch_count));
        try stdout.print("{d},{d},{d},{d}\n", .{ page_count, touch_count, fault_count, extra_faults });
    }
}
