const std = @import("std");
const windows = std.os.windows;
const linux = std.os.linux;
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const ProcessHandle = if (native_os == .windows) windows.HANDLE else void;
const process_handle: ProcessHandle = blk: {
    if (native_os == .windows) {
        break :blk windows.GetCurrentProcess();
    } else {
        break :blk;
    }
};

pub fn readPageFaultCount() !u32 {
    switch (native_os) {
        .windows => {
            const vm_counters = try windows.GetProcessMemoryInfo(process_handle);
            return vm_counters.PageFaultCount;
        },
        else => return error.PlatformNotSupported,
    }
}

pub fn rawAlloc(n: u64) ![]u8 {
    const addr: [*]u8 = blk: {
        switch (native_os) {
            .windows => {
                const addr = try windows.VirtualAlloc(null, n, windows.MEM_COMMIT | windows.MEM_RESERVE, windows.PAGE_READWRITE);
                std.debug.assert(std.mem.isAligned(@intFromPtr(addr), @alignOf(u8)));
                break :blk @as([*]u8, @ptrCast(addr));
            },
            else => break :blk std.heap.PageAllocator.map(n, .@"8") orelse return error.AllocationFailed,
        }
    };
    return addr[0..n];
}

pub fn rawFree(mem: []u8) void {
    switch (native_os) {
        .windows => {
            windows.VirtualFree(mem.ptr, 0, windows.MEM_RELEASE);
        },
        else => return error.PlatformNotSupported,
    }
}
