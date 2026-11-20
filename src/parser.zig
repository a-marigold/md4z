const md4c = @import("md4c");

// TODO: add docs
pub fn Parser(comptime Visitor: type) type {
    return struct {
        inner: md4c.MD_PARSER,
        visitor: Visitor,

        pub fn init(visitor: Visitor) @This() {
            return .{
                .inner = .{
                    .enter_block = enterBlock,
                    .leave_block = leaveBlock,
                    .enter_span = enterSpan,
                    .leave_span = leaveSpan,
                    .text = text,

                    .flags = 0,

                    // Reserved and must be set to zero
                    .abi_version = 0,

                    .debug_log = null,
                    .syntax = null,
                },
                .visitor = visitor,
            };
        }

        /// Parses Markdown of `input` and calls the visitor callbacks.
        ///
        /// If the `md4c` parser fails, `ParseError.ParseFailed` is returned.
        ///
        /// If a visitor callback returns an error, immediately returns that error.
        pub inline fn parse(self: *@This(), input: []const u8) (ParseError || anyerror)!void {
            const result = md4c.md_parse(input.ptr, input.len, &self.inner, &self.visitor);

            return switch (result) {
                0 => {},
                -1 => ParseError.ParseFailed,
                else => @errorFromInt(result),
            };
        }

        fn enterBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            const block: *const Block = @ptrCast(@alignCast(detail));

            visitor.enterBlock(@fromBackingInt(block_type), block) catch |err| return @intFromError(err);
        }
        fn leaveBlock(block_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            const block: *const Block = @ptrCast(@alignCast(detail));

            visitor.leaveBlock(@fromBackingInt(block_type), block) catch |err| return @intFromError(err);
        }

        fn enterSpan(span_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            const span: *const Span = @ptrCast(@alignCast(detail));

            visitor.enterSpan(@fromBackingInt(span_type), span) catch |err| return @intFromError(err);
        }
        fn leaveSpan(span_type: md4c.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            const span: *const Span = @ptrCast(@alignCast(detail));

            visitor.leaveSpan(@fromBackingInt(span_type), span) catch |err| return @intFromError(err);
        }

        fn text(text_type: md4c.MD_BLOCKTYPE, data: [*c]const md4c.MD_CHAR, size: md4c.MD_SIZE, userdata: ?*anyopaque) callconv(.c) c_int {
            const visitor: *Visitor = @ptrCast(userdata);

            visitor.text(@fromBackingInt(text_type), data.?[0..size]) catch |err| return @intFromError(err);
        }
    };
}

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
