const std = @import("std");

const platform = @import("platform.zig");
const x64 = @import("x64.zig");

test "4K blocks" {
    // Note that on Windows, it appears to always allocate at 64K boundaries
    // Zig page_allocator implementation points to this: https://devblogs.microsoft.com/oldnewthing/?p=42223
    const block_size = 4 * 1024;
    for (0..16) |_| {
        const data = try platform.rawAlloc(block_size);

        const decomposed = x64.PointerAnatomy.decompose(data.ptr);
        std.debug.print("\nAllocated {d} bytes at {*}. Decomposed:\n{}\n", .{ block_size, data.ptr, decomposed });
    }
}

test "1MB blocks" {
    const block_size = 1024 * 1024;
    for (0..16) |_| {
        const data = try platform.rawAlloc(block_size);

        const decomposed = x64.PointerAnatomy.decompose(data.ptr);
        std.debug.print("\nAllocated {d} bytes at {*}. Decomposed:\n{}\n", .{ block_size, data.ptr, decomposed });
    }
}
