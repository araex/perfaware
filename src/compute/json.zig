const std = @import("std");

pub const Error = error{ SyntaxError, UnexpectedEndOfInput };

/// Tokens emitted by Reader.nextWithAlloc follow this grammar:
/// ```
///  <document> = <value> .end_of_document
///  <value> =
///    | <object>
///    | <array>
///    | <number>
///    | <string>
///  <object> = .object_begin ( <string> <value> )* .object_end
///  <array> = .array_begin ( <value> )* .array_end
///  <number> =
///    | .number
///    | .allocated_number
///  <string> =
///    | .string
///    | .allocated_string
/// ```
pub const Token = union(enum) {
    object_begin,
    object_end,
    array_begin,
    array_end,

    number: []const u8,
    partial_number: []const u8,
    allocated_number: []u8,

    string: []const u8,
    partial_string: []const u8,
    partial_string_escaped_1: [1]u8,
    allocated_string: []u8,

    end_of_document,
};

pub const PeekTokenType = enum {
    object_begin,
    object_end,
    array_begin,
    array_end,

    number,
    string,

    end_of_document,
};

pub fn reader(alloc: std.mem.Allocator, io_reader: anytype) Reader(0x1000, @TypeOf(io_reader)) {
    return Reader(0x1000, @TypeOf(io_reader)).init(alloc, io_reader);
}

pub fn Reader(comptime buffer_size: usize, comptime ReaderType: type) type {
    return struct {
        scanner: Scanner,
        reader: ReaderType,

        buffer: [buffer_size]u8 = undefined,
        bytes_read_to_buffer: u64 = 0,

        pub const NextError = ReaderType.Error || Error || std.mem.Allocator.Error;
        pub const SkipError = NextError;
        pub const AllocError = NextError || error{ValueTooLong};
        pub const PeekError = ReaderType.Error || Error;

        pub fn init(alloc: std.mem.Allocator, io_reader: anytype) @This() {
            return .{
                .scanner = Scanner.init(alloc),
                .reader = io_reader,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.scanner.deinit();
            self.* = undefined;
        }

        /// Returns the current total bytes read: sum of buffer fills and scanner progress.
        pub fn bytesRead(self: *@This()) u64 {
            return self.bytes_read_to_buffer + self.scanner.cursor;
        }

        // Returns the next token. Allocates if necessary. If it allocated, returns
        // .allocated_number or .allocated_string. The caller is responsible to free
        // allocated memory.
        pub fn nextWithAlloc(self: *@This(), alloc: std.mem.Allocator) NextError!Token {
            const token_type = try self.peekNextTokenType();
            switch (token_type) {
                .number, .string => {
                    var value_list = std.ArrayList(u8).init(alloc);
                    errdefer {
                        value_list.deinit();
                    }
                    if (try self.allocNextIntoArrayListMax(&value_list)) |slice| {
                        return if (token_type == .number)
                            Token{ .number = slice }
                        else
                            Token{ .string = slice };
                    } else {
                        return if (token_type == .number)
                            Token{ .allocated_number = try value_list.toOwnedSlice() }
                        else
                            Token{ .allocated_string = try value_list.toOwnedSlice() };
                    }
                },

                // Simple tokens never alloc.
                .object_begin,
                .object_end,
                .array_begin,
                .array_end,
                .end_of_document,
                => return try self.next(),
            }
        }

        fn allocNextIntoArrayListMax(self: *@This(), value_list: *std.ArrayList(u8)) AllocError!?[]const u8 {
            while (true) {
                return self.scanner.allocNextIntoArrayListMax(value_list) catch |err| switch (err) {
                    error.BufferUnderrun => {
                        try self.refillBuffer();
                        continue;
                    },
                    else => |other_err| return other_err,
                };
            }
        }

        fn next(self: *@This()) NextError!Token {
            while (true) {
                return self.scanner.next() catch |err| switch (err) {
                    error.BufferUnderrun => {
                        try self.refillBuffer();
                        continue;
                    },
                    else => |other_err| return other_err,
                };
            }
        }

        pub fn peekNextTokenType(self: *@This()) PeekError!PeekTokenType {
            while (true) {
                return self.scanner.peekNextTokenType() catch |err| switch (err) {
                    error.BufferUnderrun => {
                        try self.refillBuffer();
                        continue;
                    },
                    else => |other_err| return other_err,
                };
            }
        }

        fn refillBuffer(self: *@This()) ReaderType.Error!void {
            self.bytes_read_to_buffer += self.scanner.cursor;
            const input = self.buffer[0..try self.reader.read(self.buffer[0..])];
            if (input.len > 0) {
                self.scanner.feedInput(input);
            } else {
                self.scanner.endInput();
            }
        }
    };
}

// This is a stripped down version of std.json.Scanner.
pub const Scanner = struct {
    state: State = .value,
    string_is_object_key: bool = false,
    value_start: usize = undefined,
    stack: std.BitStack,

    input: []const u8 = "",
    cursor: usize = 0,
    is_end_of_input: bool = false,

    pub fn init(alloc: std.mem.Allocator) @This() {
        return .{
            .stack = std.BitStack.init(alloc),
        };
    }

    pub fn initCompleteInput(alloc: std.mem.Allocator, complete_input: []const u8) @This() {
        return .{
            .stack = std.BitStack.init(alloc),
            .input = complete_input,
            .is_end_of_input = true,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.stack.deinit();
        self.* = undefined;
    }

    pub fn feedInput(self: *@This(), input: []const u8) void {
        self.input = input;
        self.cursor = 0;
        self.value_start = 0;
    }

    pub fn endInput(self: *@This()) void {
        self.is_end_of_input = true;
    }

    pub const NextError = Error || std.mem.Allocator.Error || error{BufferUnderrun};
    pub const AllocError = Error || std.mem.Allocator.Error || error{ValueTooLong};
    pub const PeekError = Error || error{BufferUnderrun};
    pub const AllocIntoArrayListError = AllocError || error{BufferUnderrun};

    fn allocNextIntoArrayListMax(self: *@This(), value_list: *std.ArrayList(u8)) AllocIntoArrayListError!?[]const u8 {
        while (true) {
            const token = try self.next();
            switch (token) {
                // Accumulate partial values.
                .partial_number, .partial_string => |slice| {
                    try value_list.appendSlice(slice);
                },
                .partial_string_escaped_1 => |buf| {
                    try value_list.appendSlice(buf[0..]);
                },

                // Return complete values.
                .number => |slice| {
                    if (value_list.items.len == 0) {
                        // No alloc necessary.
                        return slice;
                    }
                    try value_list.appendSlice(slice);
                    // The token is complete.
                    return null;
                },
                .string => |slice| {
                    if (value_list.items.len == 0) {
                        // No alloc necessary.
                        return slice;
                    }
                    try value_list.appendSlice(slice);
                    // The token is complete.
                    return null;
                },

                .object_begin,
                .object_end,
                .array_begin,
                .array_end,
                .end_of_document,
                => unreachable, // Only .number and .string token types are allowed here. Check peekNextTokenType() before calling this.

                .allocated_number, .allocated_string => unreachable,
            }
        }
    }

    pub fn next(self: *@This()) NextError!Token {
        state_loop: while (true) {
            switch (self.state) {
                // Start of a new value
                .value => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        // Object
                        '{' => {
                            try self.stack.push(OBJECT_MODE);
                            self.cursor += 1;
                            self.state = .object_start;
                            return .object_begin;
                        },
                        '[' => {
                            try self.stack.push(ARRAY_MODE);
                            self.cursor += 1;
                            self.state = .array_start;
                            return .array_begin;
                        },

                        // String
                        '"' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            continue :state_loop;
                        },

                        // Number
                        '1'...'9' => {
                            self.value_start = self.cursor;
                            self.cursor += 1;
                            self.state = .number_int;
                            continue :state_loop;
                        },
                        '0' => {
                            self.value_start = self.cursor;
                            self.cursor += 1;
                            self.state = .number_leading_zero;
                            continue :state_loop;
                        },
                        '-' => {
                            self.value_start = self.cursor;
                            self.cursor += 1;
                            self.state = .number_minus;
                            continue :state_loop;
                        },
                        else => return error.SyntaxError,
                    }
                },

                .post_value => {
                    if (try self.skipWhitespaceCheckEnd()) return .end_of_document;

                    const c = self.input[self.cursor];
                    if (self.string_is_object_key) {
                        self.string_is_object_key = false;
                        switch (c) {
                            ':' => {
                                self.cursor += 1;
                                self.state = .value;
                                continue :state_loop;
                            },
                            else => return error.SyntaxError,
                        }
                    }

                    switch (c) {
                        '}' => {
                            if (self.stack.pop() != OBJECT_MODE) return error.SyntaxError;
                            self.cursor += 1;
                            // stay in .post_value state.
                            return .object_end;
                        },
                        ']' => {
                            if (self.stack.pop() != ARRAY_MODE) return error.SyntaxError;
                            self.cursor += 1;
                            // stay in .post_value state.
                            return .array_end;
                        },
                        ',' => {
                            switch (self.stack.peek()) {
                                OBJECT_MODE => {
                                    self.state = .object_post_comma;
                                },
                                ARRAY_MODE => {
                                    self.state = .value;
                                },
                            }
                            self.cursor += 1;
                            continue :state_loop;
                        },
                        else => return error.SyntaxError,
                    }
                },

                .object_start => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        '"' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            self.string_is_object_key = true;
                            continue :state_loop;
                        },
                        '}' => {
                            self.cursor += 1;
                            _ = self.stack.pop();
                            self.state = .post_value;
                            return .object_end;
                        },
                        else => return error.SyntaxError,
                    }
                },

                .array_start => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        ']' => {
                            self.cursor += 1;
                            _ = self.stack.pop();
                            self.state = .post_value;
                            return .array_end;
                        },
                        else => {
                            self.state = .value;
                            continue :state_loop;
                        },
                    }
                },

                .object_post_comma => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        '"' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            self.string_is_object_key = true;
                            continue :state_loop;
                        },
                        else => return error.SyntaxError,
                    }
                },

                .number_minus => {
                    if (self.cursor >= self.input.len) return self.endOfBufferInNumber(false);
                    switch (self.input[self.cursor]) {
                        '0' => {
                            self.cursor += 1;
                            self.state = .number_leading_zero;
                            continue :state_loop;
                        },
                        '1'...'9' => {
                            self.cursor += 1;
                            self.state = .number_int;
                            continue :state_loop;
                        },
                        else => return error.SyntaxError,
                    }
                },

                .number_leading_zero => {
                    if (self.cursor >= self.input.len) return self.endOfBufferInNumber(true);
                    switch (self.input[self.cursor]) {
                        '.' => {
                            self.cursor += 1;
                            self.state = .number_post_dot;
                            continue :state_loop;
                        },
                        else => {
                            self.state = .post_value;
                            return Token{ .number = self.takeValueSlice() };
                        },
                    }
                },
                .number_int => {
                    while (self.cursor < self.input.len) : (self.cursor += 1) {
                        switch (self.input[self.cursor]) {
                            '0'...'9' => continue,
                            '.' => {
                                self.cursor += 1;
                                self.state = .number_post_dot;
                                continue :state_loop;
                            },
                            else => {
                                self.state = .post_value;
                                return Token{ .number = self.takeValueSlice() };
                            },
                        }
                    }
                    return self.endOfBufferInNumber(true);
                },
                .number_post_dot => {
                    if (self.cursor >= self.input.len) return self.endOfBufferInNumber(false);
                    switch (self.input[self.cursor]) {
                        '0'...'9' => {
                            self.cursor += 1;
                            self.state = .number_frac;
                            continue :state_loop;
                        },
                        else => return error.SyntaxError,
                    }
                },
                .number_frac => {
                    while (self.cursor < self.input.len) : (self.cursor += 1) {
                        switch (self.input[self.cursor]) {
                            '0'...'9' => continue,
                            else => {
                                self.state = .post_value;
                                return Token{ .number = self.takeValueSlice() };
                            },
                        }
                    }
                    return self.endOfBufferInNumber(true);
                },

                .string => {
                    while (self.cursor < self.input.len) : (self.cursor += 1) {
                        switch (self.input[self.cursor]) {
                            0...0x1f => return error.SyntaxError, // Bare ASCII control code in string.

                            // ASCII plain text.
                            0x20...('"' - 1), ('"' + 1)...('\\' - 1), ('\\' + 1)...0x7F => continue,

                            // Special characters.
                            '"' => {
                                const result = Token{ .string = self.takeValueSlice() };
                                self.cursor += 1;
                                self.state = .post_value;
                                return result;
                            },
                            '\\' => {
                                const slice = self.takeValueSlice();
                                self.cursor += 1;
                                self.state = .string_backslash;
                                if (slice.len > 0) return Token{ .partial_string = slice };
                                continue :state_loop;
                            },

                            else => return error.SyntaxError, // Unsupported character
                        }
                    }
                    if (self.is_end_of_input) return error.UnexpectedEndOfInput;
                    const slice = self.takeValueSlice();
                    if (slice.len > 0) return Token{ .partial_string = slice };
                    return error.BufferUnderrun;
                },

                .string_backslash => {
                    if (self.cursor >= self.input.len) return self.endOfBufferInString();
                    switch (self.input[self.cursor]) {
                        '"', '\\', '/' => {
                            // Since these characters now represent themselves literally,
                            // we can simply begin the next plaintext slice here.
                            self.value_start = self.cursor;
                            self.cursor += 1;
                            self.state = .string;
                            continue :state_loop;
                        },
                        'b' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            return Token{ .partial_string_escaped_1 = [_]u8{0x08} };
                        },
                        'f' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            return Token{ .partial_string_escaped_1 = [_]u8{0x0c} };
                        },
                        'n' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            return Token{ .partial_string_escaped_1 = [_]u8{'\n'} };
                        },
                        'r' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            return Token{ .partial_string_escaped_1 = [_]u8{'\r'} };
                        },
                        't' => {
                            self.cursor += 1;
                            self.value_start = self.cursor;
                            self.state = .string;
                            return Token{ .partial_string_escaped_1 = [_]u8{'\t'} };
                        },
                        else => return error.SyntaxError,
                    }
                },
            }
        }
    }

    pub fn peekNextTokenType(self: *@This()) PeekError!PeekTokenType {
        state_loop: while (true) {
            switch (self.state) {
                .value => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        '{' => return .object_begin,
                        '[' => return .array_begin,
                        '"' => return .string,
                        '-', '0'...'9' => return .number,
                        else => return error.SyntaxError,
                    }
                },

                .post_value => {
                    if (try self.skipWhitespaceCheckEnd()) return .end_of_document;

                    const c = self.input[self.cursor];
                    if (self.string_is_object_key) {
                        self.string_is_object_key = false;
                        switch (c) {
                            ':' => {
                                self.cursor += 1;
                                self.state = .value;
                                continue :state_loop;
                            },
                            else => return error.SyntaxError,
                        }
                    }

                    switch (c) {
                        '}' => return .object_end,
                        ']' => return .array_end,
                        ',' => {
                            switch (self.stack.peek()) {
                                OBJECT_MODE => {
                                    self.state = .object_post_comma;
                                },
                                ARRAY_MODE => {
                                    self.state = .value;
                                },
                            }
                            self.cursor += 1;
                            continue :state_loop;
                        },
                        else => return error.SyntaxError,
                    }
                },

                .object_start => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        '"' => return .string,
                        '}' => return .object_end,
                        else => return error.SyntaxError,
                    }
                },
                .object_post_comma => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        '"' => return .string,
                        else => return error.SyntaxError,
                    }
                },

                .array_start => {
                    switch (try self.skipWhitespaceExpectByte()) {
                        ']' => return .array_end,
                        else => {
                            self.state = .value;
                            continue :state_loop;
                        },
                    }
                },

                .number_minus,
                .number_leading_zero,
                .number_int,
                .number_post_dot,
                .number_frac,
                => return .number,

                .string,
                .string_backslash,
                => return .string,
            }
            unreachable;
        }
    }

    const State = enum {
        value,
        post_value,

        object_start,
        object_post_comma,

        array_start,

        number_minus,
        number_leading_zero,
        number_int,
        number_post_dot,
        number_frac,

        string,
        string_backslash,
    };

    const OBJECT_MODE = 0;
    const ARRAY_MODE = 1;

    fn expectByte(self: *const @This()) !u8 {
        if (self.cursor < self.input.len) {
            return self.input[self.cursor];
        }
        // No byte.
        if (self.is_end_of_input) return error.UnexpectedEndOfInput;
        return error.BufferUnderrun;
    }

    fn skipWhitespace(self: *@This()) void {
        while (self.cursor < self.input.len) : (self.cursor += 1) {
            switch (self.input[self.cursor]) {
                ' ', '\t', '\r', '\n' => continue,
                else => return,
            }
        }
    }

    fn skipWhitespaceExpectByte(self: *@This()) !u8 {
        self.skipWhitespace();
        return self.expectByte();
    }

    fn skipWhitespaceCheckEnd(self: *@This()) !bool {
        self.skipWhitespace();
        if (self.cursor >= self.input.len) {
            // End of buffer.
            if (self.is_end_of_input) {
                // End of everything.
                if (self.stack.bit_len == 0) {
                    // We did it!
                    return true;
                }
                return error.UnexpectedEndOfInput;
            }
            return error.BufferUnderrun;
        }
        if (self.stack.bit_len == 0) return error.SyntaxError;
        return false;
    }

    fn takeValueSlice(self: *@This()) []const u8 {
        const slice = self.input[self.value_start..self.cursor];
        self.value_start = self.cursor;
        return slice;
    }

    fn takeValueSliceMinusTrailingOffset(self: *@This(), trailing_negative_offset: usize) []const u8 {
        // Check if the escape sequence started before the current input buffer.
        // (The algebra here is awkward to avoid unsigned underflow,
        //  but it's just making sure the slice on the next line isn't UB.)
        if (self.cursor <= self.value_start + trailing_negative_offset) return "";
        const slice = self.input[self.value_start .. self.cursor - trailing_negative_offset];
        // When trailing_negative_offset is non-zero, setting self.value_start doesn't matter,
        // because we always set it again while emitting the .partial_string_escaped_*.
        self.value_start = self.cursor;
        return slice;
    }

    fn endOfBufferInNumber(self: *@This(), allow_end: bool) !Token {
        const slice = self.takeValueSlice();
        if (self.is_end_of_input) {
            if (!allow_end) return error.UnexpectedEndOfInput;
            self.state = .post_value;
            return Token{ .number = slice };
        }
        if (slice.len == 0) return error.BufferUnderrun;
        return Token{ .partial_number = slice };
    }

    fn endOfBufferInString(self: *@This()) !Token {
        if (self.is_end_of_input) return error.UnexpectedEndOfInput;
        const slice = self.takeValueSliceMinusTrailingOffset(switch (self.state) {
            // Don't include the escape sequence in the partial string.
            .string_backslash => 1,

            // Include everything up to the cursor otherwise.
            .string,
            => 0,

            else => unreachable,
        });
        if (slice.len == 0) return error.BufferUnderrun;
        return Token{ .partial_string = slice };
    }
};
