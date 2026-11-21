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
///     // (if there are no errors)
///     pub fn enterBlock(self: *@This(), block_type: BlockType, block: *const Block) SomeError!void {}
///     pub fn leaveBlock(self: *@This(), block_type: BlockType, block: *const Block) !void {}
///
///     // It's guaranteed that `leaveSpan` is called
///     // for every span that appears in `enterSpan`
///     // (if there are no errors)
///     pub fn enterSpan(self: *@This(), span_type: SpanType, block: *const Span) void {}
///     pub fn leaveSpan(self: *@This(), span_type: SpanType, block: *const Span) void {}
///
///     // Isn't called for the whole content of a block or span at once.
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
        visitor: Visitor,

        /// Besides `FLAG_` flags, `DIALECT_COMMONMARK` and
        /// `DIALECT_GITHUB` can be used as `flags`.
        pub fn init(visitor: Visitor, flags: u32) @This() {
            return .{
                .inner = .{
                    .enter_block = enterBlock,
                    .leave_block = leaveBlock,
                    .enter_span = enterSpan,
                    .leave_span = leaveSpan,
                    .text = text,

                    .flags = flags,

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

pub const FLAG_COLLAPSEWHITESPACE = md4c.MD_FLAG_COLLAPSEWHITESPACE;
pub const FLAG_PERMISSIVEATXHEADERS = md4c.MD_FLAG_PERMISSIVEATXHEADERS;
pub const FLAG_PERMISSIVEURLAUTOLINKS = md4c.MD_FLAG_PERMISSIVEURLAUTOLINKS;
pub const FLAG_PERMISSIVEEMAILAUTOLINKS = md4c.MD_FLAG_PERMISSIVEEMAILAUTOLINKS;
pub const FLAG_NOINDENTEDCODEBLOCKS = md4c.MD_FLAG_NOINDENTEDCODEBLOCKS;
pub const FLAG_NOHTMLBLOCKS = md4c.MD_FLAG_NOHTMLBLOCKS;
pub const FLAG_NOHTMLSPANS = md4c.MD_FLAG_NOHTMLSPANS;
pub const FLAG_TABLES = md4c.MD_FLAG_TABLES;
pub const FLAG_STRIKETHROUGH = md4c.MD_FLAG_STRIKETHROUGH;
pub const FLAG_PERMISSIVEWWWAUTOLINKS = md4c.MD_FLAG_PERMISSIVEWWWAUTOLINKS;
pub const FLAG_TASKLISTS = md4c.MD_FLAG_TASKLISTS;
pub const FLAG_LATEXMATHSPANS = md4c.MD_FLAG_LATEXMATHSPANS;
pub const FLAG_WIKILINKS = md4c.MD_FLAG_WIKILINKS;
pub const FLAG_UNDERLINE = md4c.MD_FLAG_UNDERLINE;
pub const FLAG_HARD_SOFT_BREAKS = md4c.MD_FLAG_HARD_SOFT_BREAKS;
pub const FLAG_SPOILERS = md4c.MD_FLAG_SPOILERS;
pub const FLAG_SUPERSCRIPTS = md4c.MD_FLAG_SUPERSCRIPTS;
pub const FLAG_SUBSCRIPTS = md4c.MD_FLAG_SUBSCRIPTS;
pub const FLAG_ADMONITIONS = md4c.MD_FLAG_ADMONITIONS;
pub const FLAG_FOOTNOTES = md4c.MD_FLAG_FOOTNOTES;
pub const FLAG_HIGHLIGHT = md4c.MD_FLAG_HIGHLIGHT;
pub const FLAG_PRESERVEBLANKLINES = md4c.MD_FLAG_PRESERVEBLANKLINES;
pub const FLAG_INSERT = md4c.MD_FLAG_INSERT;

pub const FLAG_PERMISSIVEAUTOLINKS = md4c.MD_FLAG_PERMISSIVEAUTOLINKS;
pub const FLAG_NOHTML = md4c.MD_FLAG_NOHTML;

pub const DIALECT_COMMONMARK = md4c.MD_DIALECT_COMMONMARK;
pub const DIALECT_GITHUB = md4c.MD_DIALECT_GITHUB;

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
    Normal = 0,
    NullChar = 1,
    HardLineBreak = 2,
    LineBreak = 3,
    Entity = 4,
    Code = 5,
    Html = 6,
    LatextMath = 7,
};
