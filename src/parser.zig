const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const md4c = @import("md4c");

/// `Visitor` is a namespace (struct, enum, etc) with public function declarations (callbacks).
///
/// Callbacks receive a mutable pointer to their visitor.
///
/// Callbacks can or can not return errors.
/// If a callback returns an error, `parse` stops and returns that error.
///
/// Example:
/// ```zig
/// const md4z = @import("md4z");
///
/// // Can be any namespace (struct, enum, union, opaque)
/// const Visitor = struct {
///     foo: Foo,
///     bar: *const Bar,
///
///     // Callbacks can or can not return errors
///
///     // It's guaranteed that `leaveBlock` is called
///     // for every span that appears in `enterBlock`
///     // (if there is no error)
///     pub fn enterBlock(self: *@This(), block: md4z.Block) SomeError!void {}
///     pub fn leaveBlock(self: *@This(), block: md4z.Block) !void {}
///
///     // It's guaranteed that `leaveSpan` is called
///     // for every span that appears in `enterSpan`
///     // (if there is no error)
///     pub fn enterSpan(self: *@This(), span: md4z.Span) void {}
///     pub fn leaveSpan(self: *@This(), span: md4z.Span) AnotherError!void {}
///
///     // Isn't called for the whole content of a block or a span at once.
///     // Instead, textual contents of blocks and spans can be
///     // sliced into parts so `text` is called multiple times for it
///     pub fn text(self: *@This(), text_type: md4z.TextType, data: []const u8) void {}
/// };
///
/// var visitor: Visitor = .{ .foo = ... };
/// const flags: md4z.Flags = .{ .collapse_whitespace = false, ... };
/// var parser: md4z.Parser(Visitor) = .init(&visitor, flags);
///
/// // May return an error from a callback,
/// // which stops the parsing completely
/// try parser.parse("# *Hello*");
/// ```
pub fn Parser(comptime Visitor: type) type {
    return struct {
        inner: md4c.MD_PARSER,
        visitor: *Visitor,

        /// `DIALECT_COMMONMARK` and `DIALECT_GITHUB` can be used as `flags`.
        pub fn init(visitor: *Visitor, flags: Flags) @This() {
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
                .visitor = visitor,
            };
        }

        /// All possible errors from callbacks that can abort parsing.
        pub const CallbackError = block: {
            const visitor_info = switch (@typeInfo(Visitor)) {
                inline .@"struct", .@"enum", .@"union", .@"opaque" => |info| info,
                else => @compileError("Visitor must be a namespace"),
            };

            var Error: type = error{};

            // Do || (merge) with all errors from callbacks
            for (visitor_info.decl_names) |decl_name|
                if (mem.eql(u8, decl_name, "enterBlock") or mem.eql(u8, decl_name, "leaveBlock") or
                    mem.eql(u8, decl_name, "enterSpan") or mem.eql(u8, decl_name, "leaveSpan") or
                    mem.eql(u8, decl_name, "text"))
                {
                    const callback_info = @typeInfo(@TypeOf(@field(Visitor, decl_name))).@"fn";

                    const CallbackReturnType = callback_info.return_type orelse
                        @compileError(decl_name ++ " callback cannot have a generic return type");

                    switch (@typeInfo(CallbackReturnType)) {
                        .error_union => |info| Error = Error || info.error_set,
                        else => {},
                    }
                };

            break :block Error;
        };

        /// Parses Markdown of `input` and calls the visitor callbacks.
        ///
        /// If a visitor callback returns an error (`CallbackError`),
        /// returns that error and stops parsing completely.
        ///
        /// If the `md4c` parser fails, `ParseError.ParseFailed` is returned.
        pub inline fn parse(self: *const @This(), input: []const u8) (ParseError || CallbackError)!void {
            const errno = md4c.md_parse(input.ptr, input.len, &self.inner, self.visitor);

            switch (errno) {
                0 => {},
                -1 => return ParseError.ParseFailed,
                else => {
                    const AnyErrorInt = @Int(.unsigned, @bitSizeOf(anyerror));
                    const err = @errorFromInt(@as(AnyErrorInt, @intCast(errno)));
                    return @errorCast(err);
                },
            }
        }

        fn enterBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            const block = blockFromDetail(block_type, detail);

            return callVisitor("enterBlock", .{ visitor, block });
        }
        fn leaveBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            const block = blockFromDetail(block_type, detail);

            return callVisitor("leaveBlock", .{ visitor, block });
        }

        fn enterSpan(span_type: md4c.MD_SPANTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            const span = spanFromDetail(span_type, detail);

            return callVisitor("enterSpan", .{ visitor, span });
        }
        fn leaveSpan(span_type: md4c.MD_SPANTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            const span = spanFromDetail(span_type, detail);

            return callVisitor("leaveSpan", .{ visitor, span });
        }

        fn text(text_type: md4c.MD_TEXTTYPE, data: [*c]const md4c.MD_CHAR, size: md4c.MD_SIZE, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata));

            return callVisitor("text", .{
                visitor,
                @as(TextType, @fromBackingInt(text_type)),
                data[0..size],
            });
        }

        /// Returns an errno that can be returned from a raw `md4c` callback.
        inline fn callVisitor(comptime callback_name: []const u8, args: anytype) c_int {
            const result = @call(.auto, @field(Visitor, callback_name), args);

            return switch (@typeInfo(result)) {
                .error_union => result catch |err| @intFromError(err),
                else => 0,
            };
        }
    };
}

/// `parse` function returns this in
/// case of a critical error in `md4c` parser.
pub const ParseError = error{ParseFailed};

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
};

pub const DIALECT_COMMONMARK: Flags = @fromBackingInt(md4c.MD_DIALECT_COMMONMARK);
pub const DIALECT_GITHUB: Flags = @fromBackingInt(md4c.MD_DIALECT_GITHUB);

/// Converts C-pointer `detail` from `md4c` to `Block`.
inline fn blockFromDetail(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque) Block {
    const block_type_info = @typeInfo(BlockType).@"enum";
    const block_info = @typeInfo(Block).@"union";

    inline for (
        block_type_info.field_values,
        block_info.field_names,
        block_info.field_types,
    ) |field_tag, field_name, FieldType|
        if (field_tag == block_type)
            return switch (FieldType) {
                void => @unionInit(Block, field_name, {}),
                else => @unionInit(Block, field_name, @ptrCast(@alignCast(detail))),
            };

    // Unknown `block_type`
    unreachable;
}

/// Converts C-pointer `detail` from `md4c` to `Block`.
inline fn spanFromDetail(span_type: md4c.MD_SPANTYPE, detail: ?*anyopaque) Span {
    const span_type_info = @typeInfo(SpanType).@"enum";
    const span_info = @typeInfo(Span).@"union";

    inline for (
        span_type_info.field_values,
        span_info.field_names,
        span_info.field_types,
    ) |field_tag, field_name, FieldType|
        if (field_tag == span_type)
            return switch (FieldType) {
                void => @unionInit(Span, field_name, {}),
                else => @unionInit(Span, field_name, @ptrCast(@alignCast(detail))),
            };

    // Unknown `span_type`
    unreachable;
}

pub const BlockType = enum(md4c.MD_BLOCKTYPE) {
    doc = md4c.MD_BLOCK_DOC,
    quote = md4c.MD_BLOCK_QUOTE,
    unordered_list = md4c.MD_BLOCK_UL,
    ordered_list = md4c.MD_BLOCK_OL,
    list_item = md4c.MD_BLOCK_LI,
    horizontal_rule = md4c.MD_BLOCK_HR,
    heading = md4c.MD_BLOCK_H,
    fenced_code = md4c.MD_BLOCK_CODE,
    html = md4c.MD_BLOCK_HTML,
    paragraph = md4c.MD_BLOCK_P,
    table = md4c.MD_BLOCK_TABLE,
    table_head = md4c.MD_BLOCK_THEAD,
    table_body = md4c.MD_BLOCK_TBODY,
    table_row = md4c.MD_BLOCK_TR,
    table_head_row = md4c.MD_BLOCK_TH,
    table_data = md4c.MD_BLOCK_TD,
    footnote_def_section = md4c.MD_BLOCK_FOOTNOTE_DEF_SECTION,
    footnote = md4c.MD_BLOCK_FOOTNOTE_DEF,
    admonition = md4c.MD_BLOCK_ADMONITION,
    blank_line = md4c.MD_BLOCK_BLANK,
};
pub const Block = union(BlockType) {
    doc: void,
    quote: void,
    unordered_list: *const md4c.MD_BLOCK_UL_DETAIL,
    ordered_list: *const md4c.MD_BLOCK_OL_DETAIL,
    list_item: *const md4c.MD_BLOCK_LI_DETAIL,
    horizontal_rule: void,
    heading: *const md4c.MD_BLOCK_H_DETAIL,
    fenced_code: *const md4c.MD_BLOCK_CODE_DETAIL,
    html: void,
    paragraph: void,
    table: *const md4c.MD_BLOCK_TABLE_DETAIL,
    table_head: void,
    table_body: void,
    table_row: void,
    table_head_row: void,
    table_data: *const md4c.MD_BLOCK_TD_DETAIL,
    footnote_def_section: void,
    footnote: *const md4c.MD_BLOCK_FOOTNOTE_DEF_DETAIL,
    admonition: *const md4c.MD_BLOCK_ADMONITION_DETAIL,
    blank_line: *const md4c.MD_BLOCK_BLANK_DETAIL,
};

pub const SpanType = enum(md4c.MD_SPANTYPE) {
    emphasis = md4c.MD_SPAN_EM,
    strong = md4c.MD_SPAN_STRONG,
    link = md4c.MD_SPAN_A,
    img = md4c.MD_SPAN_IMG,
    code = md4c.MD_SPAN_CODE,
    insert = md4c.MD_SPAN_INS,
    delete = md4c.MD_SPAN_DEL,
    latex_math = md4c.MD_SPAN_LATEXMATH,
    latex_math_display = md4c.MD_SPAN_LATEXMATH_DISPLAY,
    wiki_link = md4c.MD_SPAN_WIKILINK,
    underline = md4c.MD_SPAN_U,
    spoiler = md4c.MD_SPAN_SPOILER,
    superscript = md4c.MD_SPAN_SUPERSCRIPT,
    subscript = md4c.MD_SPAN_SUBSCRIPT,
    footnote_ref = md4c.MD_SPAN_FOOTNOTE_REF,
    mark = md4c.MD_SPAN_MARK,
};
pub const Span = union(SpanType) {
    emphasis: void,
    strong: void,
    link: *const md4c.MD_SPAN_A_DETAIL,
    img: *const md4c.MD_SPAN_IMG_DETAIL,
    code: void,
    insert: void,
    delete: void,
    latex_math: void,
    latex_math_display: void,
    wiki_link: *const md4c.MD_SPAN_WIKILINK_DETAIL,
    underline: void,
    spoiler: void,
    superscript: void,
    subscript: void,
    footnote_ref: *const md4c.MD_SPAN_FOOTNOTE_REF_DETAIL,
    mark: void,
};

pub const TextType = enum(md4c.MD_TEXTTYPE) {
    normal = md4c.MD_TEXT_NORMAL,
    null_char = md4c.MD_TEXT_NULLCHAR,
    hard_line_break = md4c.MD_TEXT_BR,
    line_break = md4c.MD_TEXT_SOFTBR,
    entity = md4c.MD_TEXT_ENTITY,
    code = md4c.MD_TEXT_CODE,
    html = md4c.MD_TEXT_HTML,
    latex_math = md4c.MD_TEXT_LATEXMATH,
};

test "`parse` returns errors from callbacks and stops immediately" {
    const BlockError = error{SomeBlockFail};
    const SpanError = error{SomeSpanFail};
    const TextError = error{SomeTextFail};

    const Visitor = struct {
        enter_block_return_value: BlockError!void,
        leave_block_return_value: BlockError!void,
        enter_span_return_value: SpanError!void,
        leave_span_return_value: SpanError!void,
        text_return_value: TextError!void,

        pub fn enterBlock(self: *@This(), _: Block) BlockError!void {
            return self.enter_block_return_value;
        }
        pub fn leaveBlock(self: *@This(), _: Block) BlockError!void {
            return self.leave_block_return_value;
        }

        pub fn enterSpan(self: *@This(), _: Span) SpanError!void {
            return self.enter_span_return_value;
        }
        pub fn leaveSpan(self: *@This(), _: Span) SpanError!void {
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

    var visitor: Visitor = undefined;
    var parser: ParserType = .init(&visitor, .{});

    const cases = .{
        .{ .field_name = "enter_block_return_value", .err = BlockError.SomeBlockFail },
        .{ .field_name = "leave_block_return_value", .err = BlockError.SomeBlockFail },
        .{ .field_name = "enter_span_return_value", .err = SpanError.SomeSpanFail },
        .{ .field_name = "leave_span_return_value", .err = SpanError.SomeSpanFail },
        .{ .field_name = "text_return_value", .err = TextError.SomeTextFail },
    };

    inline for (cases) |case| {
        visitor = .{
            .enter_block_return_value = {},
            .leave_block_return_value = {},
            .enter_span_return_value = {},
            .leave_span_return_value = {},
            .text_return_value = {},
        };
        @field(visitor, case.field_name) = case.err;

        const result = parser.parse(
            \\# **Hello**
            \\> Quote
        );

        try testing.expectError(case.err, result);
    }
}

test "`parse` result is identical to the original `md4c.md_parse` result" {}
