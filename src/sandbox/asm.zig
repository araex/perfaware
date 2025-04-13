pub extern fn MOVAllBytesASM(count: usize, data: [*]const u8) void;
pub extern fn NOPAllBytesASM(count: usize) void;
pub extern fn CMPAllBytesASM(count: usize) void;
pub extern fn DECAllBytesASM(count: usize) void;

pub extern fn Read_x1(count: usize, data: [*]const u8) void;
pub extern fn Read_x2(count: usize, data: [*]const u8) void;
pub extern fn Read_x3(count: usize, data: [*]const u8) void;
pub extern fn Read_x4(count: usize, data: [*]const u8) void;
pub extern fn Read_x5(count: usize, data: [*]const u8) void;

pub extern fn Write_x1(count: usize, data: [*]const u8) void;
pub extern fn Write_x2(count: usize, data: [*]const u8) void;
pub extern fn Write_x3(count: usize, data: [*]const u8) void;
pub extern fn Write_x4(count: usize, data: [*]const u8) void;
pub extern fn Write_x5(count: usize, data: [*]const u8) void;

pub extern fn Read_4x3(count: usize, data: [*]const u8) void;
pub extern fn Read_8x3(count: usize, data: [*]const u8) void;
pub extern fn Read_16x2(count: usize, data: [*]const u8) void;
pub extern fn Read_16x3(count: usize, data: [*]const u8) void;
pub extern fn Read_32x2(count: usize, data: [*]const u8) void;
pub extern fn Read_32x3(count: usize, data: [*]const u8) void;
