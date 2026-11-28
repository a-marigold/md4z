const std = @import("std");
const math = std.math;
const testing = std.testing;
const md4c = @import("md4c");
const types = @import("types.zig");
const blocks = types.blocks;
const spans = types.spans;
const TextType = types.TextType;

/// `Visitor` is a namespace (`struct`, `enum`, `union`, `opaque`) with `pub fn` callbacks.
///
/// Callbacks are `enterBlock`, `leaveBlock`, `enterSpan`, `leaveSpan` and `text`.
///
/// 1. Block and span generic callbacks receive:
///    - A mutable pointer to the visitor.
///    - Block or span, which is `anytype`.
///      Types of blocks and spans are in `block` and `span` namespaces.
/// 2. `text` receives:
///    - A mutable poitner to the visitor.
///    - `TextType` (e.g `normal` or `code`).
///    - `data`, which is a **non**-null-terminated slice of text.
///
/// Callbacks may or may not return errors.
/// If a callback returns an error, `parse` stops and returns that error.
///
/// See the example in [README](https://github.com/a-marigold/md4z/blob/main/README.md).
pub fn Parser(comptime Visitor: type) type {
    return struct {
        inner: md4c.MD_PARSER,

        /// `Flags.dialect_commonmark` and `Flags.dialect_github` can be used as `flags`.
        pub fn init(flags: Flags) @This() {
            return .{
                .inner = .{
                    .enter_block = enterBlock,
                    .leave_block = leaveBlock,
                    .enter_span = enterSpan,
                    .leave_span = leaveSpan,
                    .text = text,

                    .flags = @backingInt(flags),

                    // Reserved and must be set to zero
                    .abi_version = 0,

                    .debug_log = null,
                    .syntax = null,
                },
            };
        }

        /// Parses Markdown of `input` and the calls the visitor callbacks.
        ///
        /// Returns `ParseError.InputTooLong` if `input.len` doesn't fit in `u32`.
        ///
        /// If a visitor callback returns an error (`CallbackError`),
        /// returns that error and stops parsing completely.
        ///
        /// If the `md4c` parser fails, `ParseError.ParseFailed` is returned.
        pub fn parse(self: *const @This(), visitor: *Visitor, input: []const u8) (ParseError || CallbackError(Visitor))!void {
            if (input.len > math.maxInt(md4c.MD_SIZE)) return ParseError.InputTooLong;
            const input_size: md4c.MD_SIZE = @intCast(input.len);

            const errno = md4c.md_parse(input.ptr, input_size, &self.inner, visitor);

            switch (errno) {
                0 => {},
                -1 => return ParseError.ParseFail,
                else => {
                    const AnyErrorInt = @Int(.unsigned, @bitSizeOf(anyerror));
                    const err = @errorFromInt(@as(AnyErrorInt, @intCast(errno)));
                    return @errorCast(err);
                },
            }
        }

        fn enterBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            return callBlock("enterBlock", block_type, detail, userdata);
        }
        fn leaveBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            return callBlock("leaveBlock", block_type, detail, userdata);
        }

        fn enterSpan(span_type: md4c.MD_SPANTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            return callSpan("enterSpan", span_type, detail, userdata);
        }
        fn leaveSpan(span_type: md4c.MD_SPANTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            return callSpan("leaveSpan", span_type, detail, userdata);
        }

        fn text(text_type: md4c.MD_TEXTTYPE, data: [*c]const md4c.MD_CHAR, size: md4c.MD_SIZE, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            const text_tag: TextType = @fromBackingInt(text_type);
            return callVisitor("text", .{ visitor, text_tag, data[0..size] });
        }

        fn callBlock(
            comptime callback_name: []const u8,
            block_type: md4c.MD_BLOCKTYPE,
            detail: ?*anyopaque,
            userdata: ?*anyopaque,
        ) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            const block_tag: types.BlockType = @fromBackingInt(block_type);
            return switch (block_tag) {
                inline else => |tag| callVisitor(callback_name, .{ visitor, types.blockFromType(tag, detail) }),
            };
        }

        fn callSpan(
            comptime callback_name: []const u8,
            span_type: md4c.MD_SPANTYPE,
            detail: ?*anyopaque,
            userdata: ?*anyopaque,
        ) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            const span_tag: types.SpanType = @fromBackingInt(span_type);
            return switch (span_tag) {
                inline else => |tag| callVisitor(callback_name, .{ visitor, types.spanFromType(tag, detail) }),
            };
        }

        /// Returns an errno that can be returned from a raw `md4c` callback.
        fn callVisitor(comptime callback_name: []const u8, args: anytype) c_int {
            const result = @call(.auto, @field(Visitor, callback_name), args);

            if (@typeInfo(@TypeOf(result)) == .error_union)
                result catch |err| return @intFromError(err);

            return 0;
        }
    };
}

/// All errors from `Visitor` callbacks.
pub fn CallbackError(comptime Visitor: type) type {
    var Error: type = error{};

    // Do || (merge) with all errors from callbacks
    for (.{ "enterBlock", "leaveBlock", "enterSpan", "leaveSpan", "text" }) |decl_name| {
        if (!@hasDecl(Visitor, decl_name))
            @compileError("`Visitor` must have " ++ decl_name ++ " callback");

        const callback = @field(Visitor, decl_name);
        const callback_info = @typeInfo(@TypeOf(callback)).@"fn";

        const CallbackReturnType = callback_info.return_type orelse
            @compileError(decl_name ++ " callback cannot have a generic return type");

        switch (@typeInfo(CallbackReturnType)) {
            .error_union => |info| Error = Error || info.error_set,
            else => {},
        }
    }

    return Error;
}

/// `parse` function error.
pub const ParseError = error{
    /// General error in `md4c` parser.
    ParseFail,

    /// Markdown input in `md4c` must fit `u32`.
    InputTooLong,
};

pub const Flags = packed struct(u32) {
    /// In MD_TEXT_NORMAL, collapse non-trivial whitespace into single ' '
    collapse_whitespace: bool = false,

    /// Do not require space in ATX headers ( ###header )
    permissive_atx_headers: bool = false,

    /// Recognize URLs as autolinks even without '<', '>'
    permissive_url_autolinks: bool = false,

    /// Recognize e-mails as autolinks even without '<', '>' and 'mailto:'
    permissive_email_autolinks: bool = false,

    /// Disable indented code blocks. (Only fenced code works.)
    no_indented_code_blocks: bool = false,

    /// Disable raw HTML blocks.
    no_html_blocks: bool = false,

    /// Disable raw HTML (inline).
    no_html_spans: bool = false,

    /// Enable tables extension.
    tables: bool = false,

    /// Enable strikethrough extension.
    strike_through: bool = false,

    /// Enable WWW autolinks (even without any scheme prefix, if they begin with 'www.')
    permissive_www_autolinks: bool = false,

    /// Enable task list extension.
    tasklists: bool = false,

    /// Enable $ and $$ containing LaTeX equations.
    latex_math_spans: bool = false,

    /// Enable wiki links extension.
    wikilinks: bool = false,

    /// Enable underline extension (and disables '_' for normal emphasis).
    underline: bool = false,

    /// Force all soft breaks to act as hard breaks.
    hard_soft_breaks: bool = false,

    /// Enable ||hidden text|| spoiler spans.
    spoilers: bool = false,

    /// Enable ^superscript^ spans.
    superscripts: bool = false,

    /// Enable ~subscript~ spans.
    subscripts: bool = false,

    /// Enable admonitions extension.
    admonitions: bool = false,

    /// Enable [^label] footnote references.
    footnotes: bool = false,

    /// Enable ==highlight== spans.
    highlight: bool = false,

    /// Report blank line runs as MD_BLOCK_BLANK.
    preserve_blank_lines: bool = false,

    /// Enable insert extension.
    insert: bool = false,

    _: u9 = 0,

    pub const dialect_commonmark: @This() = @fromBackingInt(md4c.MD_DIALECT_COMMONMARK);
    pub const dialect_github: @This() = @fromBackingInt(md4c.MD_DIALECT_GITHUB);
};

test "`parse` returns errors from callbacks" {
    const BlockError = error{SomeBlockFail};
    const SpanError = error{SomeSpanFail};
    const TextError = error{SomeTextFail};

    const Visitor = struct {
        enter_block_return_value: BlockError!void,
        leave_block_return_value: BlockError!void,
        enter_span_return_value: SpanError!void,
        leave_span_return_value: SpanError!void,
        text_return_value: TextError!void,

        pub fn enterBlock(self: *@This(), _: anytype) BlockError!void {
            return self.enter_block_return_value;
        }
        pub fn leaveBlock(self: *@This(), _: anytype) BlockError!void {
            return self.leave_block_return_value;
        }

        pub fn enterSpan(self: *@This(), _: anytype) SpanError!void {
            return self.enter_span_return_value;
        }
        pub fn leaveSpan(self: *@This(), _: anytype) SpanError!void {
            return self.leave_span_return_value;
        }

        pub fn text(self: *@This(), _: TextType, _: []const u8) TextError!void {
            return self.text_return_value;
        }
    };

    const ParserType = Parser(Visitor);
    const ParseReturnType = @typeInfo(@TypeOf(ParserType.parse)).@"fn".return_type.?;
    const ParseReturnTypeError = @typeInfo(ParseReturnType).error_union.error_set;

    try testing.expectEqual(ParseReturnTypeError, ParseError || BlockError || SpanError || TextError);

    var parser: ParserType = .init(.{});

    const cases = .{
        .{ .field_name = "enter_block_return_value", .err = BlockError.SomeBlockFail },
        .{ .field_name = "leave_block_return_value", .err = BlockError.SomeBlockFail },
        .{ .field_name = "enter_span_return_value", .err = SpanError.SomeSpanFail },
        .{ .field_name = "leave_span_return_value", .err = SpanError.SomeSpanFail },
        .{ .field_name = "text_return_value", .err = TextError.SomeTextFail },
    };

    inline for (cases) |case| {
        var visitor: Visitor = .{
            .enter_block_return_value = {},
            .leave_block_return_value = {},
            .enter_span_return_value = {},
            .leave_span_return_value = {},
            .text_return_value = {},
        };
        @field(visitor, case.field_name) = case.err;

        const result = parser.parse(&visitor,
            \\# **Hello**
            \\> Quote
        );

        try testing.expectError(case.err, result);
    }
}
