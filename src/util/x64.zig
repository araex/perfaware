const std = @import("std");

pub const PointerAnatomy = struct {
    // Packed structs are in order lsb to msb
    pub const Decomposed = packed struct {
        page_offset: u12,
        page_table: u9,
        page_dir_table: u9,
        page_dir_ptr_table: u9,
        page_map_lvl4_table: u9,
        unused: u16,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("{b:0>16}|{b:0>9}|{b:0>9}|{b:0>9}|{b:0>9}|{b:0>9}\n", .{
                self.unused,
                self.page_map_lvl4_table,
                self.page_dir_ptr_table,
                self.page_dir_table,
                self.page_table,
                self.page_offset,
            });
            try writer.print("{d: >16}|{d: >9}|{d: >9}|{d: >9}|{d: >9}|{d: >9}", .{
                self.unused,
                self.page_map_lvl4_table,
                self.page_dir_ptr_table,
                self.page_dir_table,
                self.page_table,
                self.page_offset,
            });
        }
    };

    pub fn decompose(in: anytype) Decomposed {
        comptime std.debug.assert(@sizeOf(@TypeOf(in)) == 8);
        const val = if (comptime @typeInfo(@TypeOf(in)) == .pointer) @intFromPtr(in) else in;
        return @as(Decomposed, @bitCast(val));
    }
};

test "pointer decompose" {
    // https://blog.xenoscr.net/2021/09/06/Exploring-Virtual-Memory-and-Page-Structures.html
    const ptr: u64 = 0x00007FF6_0BF40190;
    const decomposed = PointerAnatomy.decompose(ptr);
    try std.testing.expectEqual(0x0, decomposed.unused);
    try std.testing.expectEqual(0xFF, decomposed.page_map_lvl4_table);
    try std.testing.expectEqual(0x1D8, decomposed.page_dir_ptr_table);
    try std.testing.expectEqual(0x5F, decomposed.page_dir_table);
    try std.testing.expectEqual(0x140, decomposed.page_table);
    try std.testing.expectEqual(0x190, decomposed.page_offset);
    std.debug.print("\n{}\n", .{decomposed});
}
