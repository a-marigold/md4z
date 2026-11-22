const std = @import("std");
const mem = std.mem;
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
/// // Can be any namespace (struct, enum, union, opaque)
/// const Visitor = struct {
///     user_field: SomeType,
///     user_field1: SomeType1,
///
///     // Callbacks can or can not return errors
///
///     // It's guaranteed that `leaveBlock` is called
///     // for every span that appears in `enterBlock`
///     // (if there is no error)
///     pub fn enterBlock(self: *@This(), block_type: BlockType, block: *const Block) SomeError!void {}
///     pub fn leaveBlock(self: *@This(), block_type: BlockType, block: *const Block) !void {}
///
///     // It's guaranteed that `leaveSpan` is called
///     // for every span that appears in `enterSpan`
///     // (if there is no error)
///     pub fn enterSpan(self: *@This(), span_type: SpanType, block: *const Span) void {}
///     pub fn leaveSpan(self: *@This(), span_type: SpanType, block: *const Span) void {}
///
///     // Isn't called for the whole content of a block or a span at once.
///     // Instead, textual contents of blocks and spans can be
///     // sliced into parts so `text` is called multiple times for it
///     pub fn text(self: *@This(), text_type: TextType, data: []const u8) void {}
/// };
///
/// const parser: Parser(Visitor) = .init(.{ .user_field = ... }, flags);
///
/// // May return an error from a callback,
/// // which stops the parsing completely
/// try parser.parse("# *Hello*");
/// ```
pub fn Parser(comptime Visitor: type) type {
    return struct {
        inner: md4c.MD_PARSER,
        visitor: *Visitor,

        /// Not only `FLAG_*` can be used as `flags`,
        /// but also `DIALECT_COMMONMARK` and `DIALECT_GITHUB`.
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
                .@"struct", .@"enum", .@"union", .@"opaque" => |info| info,
                else => @compileError("Visitor must be a namespace"),
            };

            var Error: type = error{};

            // Do || (merge) with all errors from callbacks
            for (visitor_info.decl_names) |decl_name|
                if (mem.eql(u8, decl_name, "enterBlock") or mem.eql(u8, decl_name, "leaveBlock") or
                    mem.eql(u8, decl_name, "enterSpan") or mem.eql(u8, decl_name, "leaveSpan") or
                    mem.eql(u8, decl_name, "text"))
                {
                    const callback_info = @typeInfo(@FieldType(Visitor, decl_name)).@"fn";

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
        pub inline fn parse(self: *@This(), input: []const u8) (ParseError || CallbackError)!void {
            const result = md4c.md_parse(input.ptr, input.len, &self.inner, self.visitor);

            return switch (result) {
                0 => {},
                -1 => ParseError.ParseFailed,
                else => @errorFromInt(result),
            };
        }

        fn enterBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(@alignCast(userdata.?));

            const block: *const Block = @ptrCast(@alignCast(detail));

            visitor.enterBlock(@fromBackingInt(block_type), block) catch |err| return @intFromError(err);
        }
        fn leaveBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            const block: *const Block = @ptrCast(@alignCast(detail));

            visitor.leaveBlock(@fromBackingInt(block_type), block) catch |err| return @intFromError(err);
        }

        fn enterSpan(span_type: md4c.MD_SPANTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            const span: *const Span = @ptrCast(@alignCast(detail));

            visitor.enterSpan(@fromBackingInt(span_type), span) catch |err| return @intFromError(err);
        }
        fn leaveSpan(span_type: md4c.MD_SPANTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            const span: *const Span = @ptrCast(@alignCast(detail));

            visitor.leaveSpan(@fromBackingInt(span_type), span) catch |err| return @intFromError(err);
        }

        fn text(text_type: md4c.MD_TEXTTYPE, data: [*c]const md4c.MD_CHAR, size: md4c.MD_SIZE, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            visitor.text(@fromBackingInt(text_type), data.?[0..size]) catch |err| return @intFromError(err);
        }
    };
}

pub const Flags = packed struct(u32) {
    collapse_whitespace: bool = false,
    permissive_atx_headers: bool = false,
    permissive_url_autolinks: bool = false,
    permissive_email_autolinks: bool = false,
    no_indented_code_blocks: bool = false,
    no_html_blocks: bool = false,
    no_html_spans: bool = false,
    tables: bool = false,
    strike_through: bool = false,
    permissive_www_autolinks: bool = false,
    tasklists: bool = false,
    latex_math_spans: bool = false,
    wikilinks: bool = false,
    underline: bool = false,
    hard_soft_breaks: bool = false,
    spoilers: bool = false,
    superscripts: bool = false,
    subscripts: bool = false,
    admonitions: bool = false,
    footnotes: bool = false,
    highlight: bool = false,
    preserve_blank_lines: bool = false,
    insert: bool = false,

    _: u23 = 0,
};

pub const DIALECT_COMMONMARK: Flags = @fromBackingInt(md4c.MD_DIALECT_COMMONMARK);
pub const DIALECT_GITHUB: Flags = @fromBackingInt(md4c.MD_DIALECT_GITHUB);

/// `parse` function returns this if
/// the `md4c` parser fails for some reason.
pub const ParseError = error{ParseFailed};

pub const BlockType = enum(md4c.MD_BLOCKTYPE) {
    Doc = md4c.MD_BLOCK_DOC,
    Quote = md4c.MD_BLOCK_QUOTE,
    UnorderedList = md4c.MD_BLOCK_UL,
    OrderedList = md4c.MD_BLOCK_OL,
    ListItem = md4c.MD_BLOCK_LI,
    HorizontalRule = md4c.MD_BLOCK_HR,
    Heading = md4c.MD_BLOCK_H,
    FencedCode = md4c.MD_BLOCK_CODE,
    Html = md4c.MD_BLOCK_HTML,
    Paragraph = md4c.MD_BLOCK_P,
    Table = md4c.MD_BLOCK_TABLE,
    TableHead = md4c.MD_BLOCK_THEAD,
    TableBody = md4c.MD_BLOCK_TBODY,
    TableRow = md4c.MD_BLOCK_TR,
    TableHeadRow = md4c.MD_BLOCK_TH,
    TableData = md4c.MD_BLOCK_TD,
    FootnoteSection = md4c.MD_BLOCK_FOOTNOTE_DEF_SECTION,
    Footnote = md4c.MD_BLOCK_FOOTNOTE_DEF,
    Admonition = md4c.MD_BLOCK_ADMONITION,
    BlankLine = md4c.MD_BLOCK_BLANK,
};
pub const Block = union {
    Doc: void,
    Quote: void,
    UnorderedList: md4c.MD_BLOCK_UL_DETAIL,
    OrderedList: md4c.MD_BLOCK_OL_DETAIL,
    ListItem: md4c.MD_BLOCK_LI_DETAIL,
    HorizontalRule: void,
    Heading: md4c.MD_BLOCK_H_DETAIL,
    FencedCode: md4c.MD_BLOCK_CODE_DETAIL,
    Html: void,
    Paragraph: void,
    Table: md4c.MD_BLOCK_TABLE_DETAIL,
    TableHead: void,
    TableBody: void,
    TableRow: void,
    TableHeadRow: void,
    TableData: md4c.MD_BLOCK_TD_DETAIL,
    FootnoteSection: void,
    Footnote: md4c.MD_BLOCK_FOOTNOTE_DEF_DETAIL,
    Admonition: md4c.MD_BLOCK_ADMONITION_DETAIL,
    BlankLine: md4c.MD_BLOCK_BLANK_DETAIL,
};

pub const SpanType = enum(md4c.MD_SPANTYPE) {
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
    SuperScript = md4c.MD_SPAN_SUPERSCRIPT,
    SubScript = md4c.MD_SPAN_SUBSCRIPT,
    FootnoteRef = md4c.MD_SPAN_FOOTNOTE_REF,
    Mark = md4c.MD_SPAN_MARK,
};
pub const Span = union {
    Emphasis: void,
    Strong: void,
    Link: md4c.MD_SPAN_A_DETAIL,
    Img: md4c.MD_SPAN_IMG_DETAIL,
    Code: void,
    Insert: void,
    Delete: void,
    LatexMath: void,
    LatexMathDisplay: void,
    WikiLink: md4c.MD_SPAN_WIKILINK_DETAIL,
    Underline: void,
    Spoiler: void,
    SuperScript: void,
    SubScript: void,
    FootnoteRef: md4c.MD_SPAN_FOOTNOTE_REF_DETAIL,
    Mark: void,
};

pub const TextType = enum(md4c.MD_TEXTTYPE) {
    Normal = md4c.MD_TEXT_NORMAL,
    NullChar = md4c.MD_TEXT_NULLCHAR,
    HardLineBreak = md4c.MD_TEXT_BR,
    LineBreak = md4c.MD_TEXT_SOFTBR,
    Entity = md4c.MD_TEXT_ENTITY,
    Code = md4c.MD_TEXT_CODE,
    Html = md4c.MD_TEXT_HTML,
    LatexMath = md4c.MD_TEXT_LATEXMATH,
};

test {}
