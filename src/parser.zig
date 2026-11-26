const std = @import("std");
const testing = std.testing;
const md4c = @import("md4c");

/// `Visitor` is a namespace (`struct`, `enum`, `union`, `opaque`) with `pub fn` callbacks.
///
/// Callbacks are `enterBlock`, `leaveBlock`, `enterSpan`, `leaveSpan` and `text`.
///
/// 1. Block and span generic callbacks receive:
///    - A mutable pointer to the visitor.
///    - Block or span, which is `anytype`.
///      Possible types of it can be found in
///      `block` and `span` namespaces.
/// 2. `text` receives:
///    - A mutable poitner to the visitor.
///    - `TextType` (e.g `normal` or `code`).
///    - `data`, which is a **non**-null-terminated slice of text.
///
/// Callbacks can or can not return errors.
/// If a callback returns an error, `parse` stops and returns that error.
///
/// See the example in [README](https://github.com/a-marigold/md4z/blob/main/README.md).
pub fn Parser(comptime Visitor: type) type {
    return struct {
        inner: md4c.MD_PARSER,
        visitor: *Visitor,

        /// `Flags.dialect_commonmark` and `Flags.dialect_github` can be used as `flags`.
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
            var Error: type = error{};

            // Do || (merge) with all errors from callbacks
            for (.{ "enterBlock", "leaveBlock", "enterSpan", "leaveSpan", "text" }) |decl_name| {
                const callback = @field(Visitor, decl_name);
                const callback_info = @typeInfo(@TypeOf(callback)).@"fn";

                const CallbackReturnType = callback_info.return_type orelse
                    @compileError(decl_name ++ " callback cannot have a generic return type");

                switch (@typeInfo(CallbackReturnType)) {
                    .error_union => |info| Error = Error || info.error_set,
                    else => {},
                }
            }

            break :block Error;
        };

        /// Parses Markdown of `input` and calls the visitor callbacks.
        ///
        /// If a visitor callback returns an error (`CallbackError`),
        /// returns that error and stops parsing completely.
        ///
        /// If the `md4c` parser fails, `ParseError.ParseFailed` is returned.
        pub fn parse(self: *const @This(), input: []const u8) (ParseError || CallbackError)!void {
            const errno = md4c.md_parse(input.ptr, @intCast(input.len), &self.inner, self.visitor);

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
            const block_tag: block.Type = @fromBackingInt(block_type);

            switch (block_tag) {
                inline else => |tag| {
                    const tag_name = comptime @tagName(tag);

                    const BlockType = @field(block, tag_name);
                    const block_info = @typeInfo(BlockType).@"struct";
                    const block_fields_len = block_info.field_names.len;

                    const detail_block: BlockType = switch (block_fields_len) {
                        0 => .{},
                        1 => switch (BlockType) {
                            block.TableHead => .{ .data = .{ .detail = @ptrCast(@alignCast(detail)) } },
                            else => .{ .detail = @ptrCast(@alignCast(detail)) },
                        },
                        else => unreachable,
                    };

                    const visitor: *Visitor = @ptrCast(@alignCast(userdata));
                    return callVisitor(callback_name, .{ visitor, detail_block });
                },
            }
        }

        fn callSpan(
            comptime callback_name: []const u8,
            span_type: md4c.MD_SPANTYPE,
            detail: ?*anyopaque,
            userdata: ?*anyopaque,
        ) c_int {
            const span_tag: span.Type = @fromBackingInt(span_type);

            switch (span_tag) {
                inline else => |tag| {
                    const tag_name = comptime @tagName(tag);

                    const SpanType = @field(span, tag_name);
                    const span_info = @typeInfo(SpanType).@"struct";
                    const span_fields_len = span_info.field_names.len;

                    const detail_span: SpanType = switch (span_fields_len) {
                        0 => .{},
                        1 => .{ .detail = @ptrCast(@alignCast(detail)) },
                        else => unreachable,
                    };

                    const visitor: *Visitor = @ptrCast(@alignCast(userdata));
                    return callVisitor(callback_name, .{ visitor, detail_span });
                },
            }
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

    pub const dialect_commonmark: @This() = @fromBackingInt(md4c.MD_DIALECT_COMMONMARK);
    pub const dialect_github: @This() = @fromBackingInt(md4c.MD_DIALECT_GITHUB);
};

/// Type declarations of blocks that `enterBlock` and `leaveBlock` receive.
///
/// Use `promote` function of blocks to translate their
/// low-level `detail` pointer into a high-level struct.
///
/// If raw `detail` pointer is used instead of `promote`,
/// dereferencing it after the callback finishes is UB.
///
/// Blocks that don't have additional info are just `struct {}`:\
/// `struct {}` instead of `void` to create identity,
/// so callbacks can use the block type in `switch` as unique prong.
const block = struct {
    /// Internal helper for raw `md4c` callbacks in `Parser`.
    const Type = enum(md4c.MD_BLOCKTYPE) {
        // Names are in PascalCase to easily access
        // `block` type declarations (like `FencedCode`)
        // without enum's snake_case convertion

        Doc = md4c.MD_BLOCK_DOC,
        Quote = md4c.MD_BLOCK_QUOTE,
        UnorderedList = md4c.MD_BLOCK_UL,
        OrderedList = md4c.MD_BLOCK_OL,
        ListItem = md4c.MD_BLOCK_LI,
        HorizontalRule = md4c.MD_BLOCK_HR,
        Heading = md4c.MD_BLOCK_H,
        FencedCodeBlock = md4c.MD_BLOCK_CODE,
        Html = md4c.MD_BLOCK_HTML,
        Paragraph = md4c.MD_BLOCK_P,
        Table = md4c.MD_BLOCK_TABLE,
        TableHead = md4c.MD_BLOCK_THEAD,
        TableBody = md4c.MD_BLOCK_TBODY,
        TableRow = md4c.MD_BLOCK_TR,
        TableHeadRow = md4c.MD_BLOCK_TH,
        TableData = md4c.MD_BLOCK_TD,
        FootnoteDefSection = md4c.MD_BLOCK_FOOTNOTE_DEF_SECTION,
        Footnote = md4c.MD_BLOCK_FOOTNOTE_DEF,
        Admonition = md4c.MD_BLOCK_ADMONITION,
        BlankLine = md4c.MD_BLOCK_BLANK,
    };

    pub const Doc = struct {};
    pub const Quote = struct {};

    pub const UnorderedList = struct {
        detail: *const md4c.MD_BLOCK_UL_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .is_tight = detail.is_tight != 0,
                .marker = @fromBackingInt(detail.mark),
            };
        }
        pub const Promoted = struct { is_tight: bool, marker: Marker };

        pub const Marker = enum(md4c.MD_CHAR) {
            @"-" = '-',
            @"+" = '+',
            @"*" = '*',
        };
    };

    pub const OrderedList = struct {
        detail: *const md4c.MD_BLOCK_OL_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .start = detail.start,
                .is_tight = detail.is_tight != 0,
                .marker = @fromBackingInt(detail.mark_delimiter),
            };
        }
        pub const Promoted = struct { start: u32, is_tight: bool, delimiter: Delimiter };

        pub const Delimiter = enum(md4c.MD_CHAR) {
            @"." = '.',
            @")" = ')',
        };
    };

    pub const ListItem = struct {
        detail: *const md4c.MD_BLOCK_LI_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return switch (detail.is_task) {
                false => .{ .item = {} },
                true => .{
                    .task = .{
                        .marker = @fromBackingInt(detail.task_mark),
                        .offset = detail.task_mark_offset,
                    },
                },
            };
        }
        pub const Promoted = union(enum) {
            item,
            task: struct { marker: TaskMarker, offset: u32 },
        };

        pub const TaskMarker = enum(md4c.MD_CHAR) {
            x = 'x',
            X = 'X',
            @" " = ' ',
        };
    };

    pub const HorizontalRule = struct {};

    pub const Heading = struct {
        detail: *const md4c.MD_BLOCK_H_DETAIL,

        pub fn promote(self: @This()) Promoted {
            return .{ .level = self.detail.level };
        }
        pub const Promoted = struct { level: u32 };
    };

    pub const FencedCodeBlock = struct {
        detail: *const md4c.MD_BLOCK_CODE_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .info = .{ .detail = detail.info },
                .lang = .{ .detail = detail.lang },
                .fence = @fromBackingInt(detail.fence_char),
            };
        }
        pub const Promoted = struct {
            info: Attribute,

            /// The first substring of `info` attribute.
            lang: Attribute,

            fence: Fence,
        };

        pub const Fence = enum(md4c.MD_CHAR) {
            @"`" = '`',
            @"~" = '~',
        };
    };

    pub const Html = struct {};
    pub const Paragraph = struct {};

    pub const Table = struct {
        detail: *const md4c.MD_BLOCK_TABLE_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .column_count = detail.col_count,
                .head_row_count = detail.head_row_count,
                .body_row_count = detail.body_row_count,
            };
        }
        pub const Promoted = struct { column_count: u32, head_row_count: u32, body_row_count: u32 };
    };

    pub const TableHead = struct { data: TableData };
    pub const TableBody = struct {};
    pub const TableRow = struct {};
    pub const TableHeadRow = struct {};

    pub const TableData = struct {
        detail: *const md4c.MD_BLOCK_TD_DETAIL,

        pub fn promote(self: @This()) Promoted {
            return .{ .alignment = @fromBackingInt(self.detail.@"align") };
        }
        pub const Promoted = struct { alignment: Alignment };

        pub const Alignment = enum(md4c.MD_ALIGN) {
            default = md4c.MD_ALIGN_DEFAULT,
            left = md4c.MD_ALIGN_LEFT,
            center = md4c.MD_ALIGN_CENTER,
            right = md4c.MD_ALIGN_RIGHT,
        };
    };

    pub const FootnoteDefSection = struct {};

    pub const Footnote = struct {
        detail: *const md4c.MD_BLOCK_FOOTNOTE_DEF_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .id = detail.id,
                .ref_count = detail.ref_count,
                .label = .{ .detail = detail.label },
            };
        }
        pub const Promoted = struct { id: u32, ref_count: u32, label: Attribute };
    };
    pub const Admonition = struct {
        detail: *const md4c.MD_BLOCK_ADMONITION_DETAIL,

        pub fn promote(self: @This()) Promoted {
            return .{ .type = .{ .detail = self.detail.type } };
        }
        pub const Promoted = struct { type: Attribute };
    };
    pub const BlankLine = struct {
        detail: *const md4c.MD_BLOCK_BLANK_DETAIL,

        pub fn promote(self: @This()) Promoted {
            return .{ .line_count = self.detail.line_count };
        }
        pub const Promoted = struct { line_count: u32 };
    };
};

/// Type declarations of spans that `enterSpan` and `leaveSpan` receive.
///
/// Use `promote` function of spans to translate their
/// low-level `detail` pointer into a high-level struct.
///
/// If raw `detail` pointer is used instead of `promote`,
/// dereferencing it after the callback finishes is UB.
///
/// Blocks that don't have additional info are just `struct {}`:\
/// `struct {}` instead of `void` to create identity,
/// so callbacks can use the span type in `switch` as unique prong.
const span = struct {
    /// Internal helper for raw `md4c` callbacks in `Parser`.
    const Type = enum(md4c.MD_SPANTYPE) {
        // Names are in PascalCase to easily access
        // `span` type declarations (like `WikiLink`)
        // without enum's snake_case convertion

        Emphasis = md4c.MD_SPAN_EM,
        Strong = md4c.MD_SPAN_STRONG,
        Link = md4c.MD_SPAN_A,
        Img = md4c.MD_SPAN_IMG,
        Code = md4c.MD_SPAN_CODE,
        Insert = md4c.MD_SPAN_INS,
        Delete = md4c.MD_SPAN_DEL,
        LatexMath = md4c.MD_SPAN_LATEXMATH,
        LatexMathDisplay = md4c.MD_SPAN_LATEXMATH_DISPLAY,
        WikiLink = md4c.MD_SPAN_WIKILINK,
        Underline = md4c.MD_SPAN_U,
        Spoiler = md4c.MD_SPAN_SPOILER,
        Superscript = md4c.MD_SPAN_SUPERSCRIPT,
        Subscript = md4c.MD_SPAN_SUBSCRIPT,
        FootnoteRef = md4c.MD_SPAN_FOOTNOTE_REF,
        Mark = md4c.MD_SPAN_MARK,
    };

    // Empty structs instead of `void`
    // to create identity, so the types can be
    // used in `switch` as unique prongs

    pub const Emphasis = struct {};
    pub const Strong = struct {};

    pub const Link = struct {
        detail: *const md4c.MD_SPAN_A_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .href = .{ .detail = detail.href },
                .title = .{ .detail = detail.title },
                .is_autolink = detail.is_autolink != 0,
            };
        }
        pub const Promoted = struct { href: Attribute, title: Attribute, is_autolink: bool };
    };

    pub const Img = struct {
        detail: *const md4c.MD_SPAN_IMG_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .src = .{ .detail = detail.src },
                .title = .{ .detail = detail.title },
            };
        }
        pub const Promoted = struct { src: Attribute, title: Attribute };
    };

    pub const Code = struct {};
    pub const Insert = struct {};
    pub const Delete = struct {};
    pub const LatexMath = struct {};
    pub const LatexMathDisplay = struct {};

    pub const WikiLink = struct {
        detail: *const md4c.MD_SPAN_WIKILINK_DETAIL,

        pub fn promote(self: @This()) Promoted {
            return .{ .target = .{ .detail = self.detail.target } };
        }
        pub const Promoted = struct { target: Attribute };
    };

    pub const Underline = struct {};
    pub const Spoiler = struct {};
    pub const Superscript = struct {};
    pub const Subscript = struct {};

    pub const FootnoteRef = struct {
        detail: *const md4c.MD_SPAN_FOOTNOTE_REF_DETAIL,

        pub fn promote(self: @This()) Promoted {
            const detail = self.detail;
            return .{
                .id = detail.id,
                .ref_id = detail.ref_id,
                .label = .{ .detail = detail.label },
            };
        }
        pub const Promoted = struct { id: u32, ref_id: u32, label: Attribute };
    };

    pub const Mark = struct {};
};

/// Appears in:
/// 1. Fenced code blocks info (lang) strings
/// 2. Image and Link titles
/// 3. Footnote labels
/// 4. Admonition type strings
pub const Attribute = struct {
    detail: md4c.MD_ATTRIBUTE,

    inline fn promote(self: *@This()) Promoted {
        const detail = self.detail;
        return switch (detail.text) {
            null => .{ .empty = {} },
            else => .{ .text = .{
                .data = detail.text[0..detail.size],
                .substr_types = @ptrCast(detail.substr_types),
                .substr_offsets = @ptrCast(detail.substr_offsets),
            } },
        };
    }

    /// In `md4c`, attribute may contain `null`
    /// in its `text` to represent emptinnes.
    ///
    /// So, a union with `empty` and `text` fields is used.
    pub const Promoted = union(enum) { empty, text: Text };

    /// Iterator over the attribute textual data.
    ///
    /// Raw `substr_types` and `substr_offsets` can
    /// be used instead of `nextSubstr` abstraction.
    ///
    /// Invariants:
    /// - `substr_offsets[0]` is 0
    /// - `substr_offsets[last_index + 1]` is `data.len` (even if it's 0)
    pub const Text = struct {
        data: []const u8,

        substr_types: [*]const TextType,
        substr_offsets: [*]const u32,
        substr_index: usize,

        /// Returns substrings of `Text.data`:
        ///
        /// `normal`, `entity` or `null_char`.
        pub fn nextSubstr(self: *@This()) ?Substr {
            const data = self.data;
            const offsets = self.substr_offsets;

            const substr_start = offsets[self.substr_index];
            if (substr_start == data.len) return null;

            self.substr_index += 1;
            const substr_end = offsets[self.substr_index];

            return .{
                .type = self.substr_types[self.substr_index],
                .data = data[substr_start..substr_end],
            };
        }

        pub const Substr = struct { type: SubstrType, data: []const u8 };

        const SubstrType = enum(md4c.MD_TEXTTYPE) {
            normal = TextType.normal,
            entity = TextType.entity,
            null_char = TextType.null_char,
        };
    };
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
