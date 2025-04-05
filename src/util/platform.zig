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
