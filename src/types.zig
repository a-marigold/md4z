//! Types of markdown document structure.

const std = @import("std");
const testing = std.testing;
const md4c = @import("md4c");

pub fn blockFromType(comptime block_type: BlockType, detail: ?*anyopaque) @field(block, @tagName(block_type)) {
    const Block = @field(block, @tagName(block_type));
    const block_info = @typeInfo(Block).@"struct";
    const block_fields_len = block_info.field_names.len;

    return switch (block_fields_len) {
        0 => .{},
        1 => switch (Block) {
            block.TableHead => .{ .data = .{ .detail = @ptrCast(@alignCast(detail)) } },
            else => .{ .detail = @ptrCast(@alignCast(detail)) },
        },
        else => unreachable,
    };
}
/// Internal helper for `blockFromType`
pub const BlockType = enum(md4c.MD_BLOCKTYPE) {
    // Names are in PascalCase to easily access
    // `block` type declarations (like `OrderedList`)
    // without enum's snake_case conversion

    Doc = md4c.MD_BLOCK_DOC,
    Quote = md4c.MD_BLOCK_QUOTE,
    UnorderedList = md4c.MD_BLOCK_UL,
    OrderedList = md4c.MD_BLOCK_OL,
    ListItem = md4c.MD_BLOCK_LI,
    HorizontalRule = md4c.MD_BLOCK_HR,
    Heading = md4c.MD_BLOCK_H,
    CodeBlock = md4c.MD_BLOCK_CODE,
    Html = md4c.MD_BLOCK_HTML,
    Paragraph = md4c.MD_BLOCK_P,
    Table = md4c.MD_BLOCK_TABLE,
    TableHead = md4c.MD_BLOCK_THEAD,
    TableBody = md4c.MD_BLOCK_TBODY,
    TableRow = md4c.MD_BLOCK_TR,
    TableHeadRow = md4c.MD_BLOCK_TH,
    TableData = md4c.MD_BLOCK_TD,
    FootnoteDeclSection = md4c.MD_BLOCK_FOOTNOTE_DEF_SECTION,
    FootnoteDecl = md4c.MD_BLOCK_FOOTNOTE_DEF,
    Admonition = md4c.MD_BLOCK_ADMONITION,
    BlankLine = md4c.MD_BLOCK_BLANK,
};

// TODO: list item next line indentation rules:
/// Type declarations of blocks that `enterBlock` and `leaveBlock` receive.
///
/// - Use `promote` function of blocks to translate their
/// low-level `detail` pointer into a high-level struct.
/// - Raw `detail` pointer can be used instead of `promote`.\
///   Note that dereferencing it after the callback finishes is UB.
///
/// Blocks that don't have additional info are just `struct {}`:\
/// `struct {}` instead of `void` to create identity,
/// so callbacks can use the block type in `switch` as unique prong.
pub const block = struct {
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
                .delimiter = @fromBackingInt(detail.mark_delimiter),
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
                0 => .{ .item = {} },
                else => .{
                    .task = .{
                        .marker = @fromBackingInt(detail.task_mark),
                        .marker_offset = detail.task_mark_offset,
                    },
                },
            };
        }
        pub const Promoted = union(enum) {
            item,
            task: struct { marker: TaskMarker, marker_offset: u32 },
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

    /// Fenced or indented code block.
    pub const CodeBlock = struct {
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
            /// Indented code block has no fence.
            none = 0,

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

    /// Section with one or more `FootnoteDecl` inside.
    pub const FootnoteDeclSection = struct {};

    /// Footnote declaration.
    pub const FootnoteDecl = struct {
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

pub fn spanFromType(comptime span_type: SpanType, detail: ?*anyopaque) @field(span, @tagName(span_type)) {
    const Span = @field(span, @tagName(span_type));
    const span_info = @typeInfo(Span).@"struct";
    const span_fields_len = span_info.field_names.len;

    return switch (span_fields_len) {
        0 => .{},
        1 => .{ .detail = @ptrCast(@alignCast(detail)) },
        else => unreachable,
    };
}
/// Internal helper for `fromType`.
pub const SpanType = enum(md4c.MD_SPANTYPE) {
    // Names are in PascalCase to easily access
    // `span` type declarations (like `WikiLink`)
    // without enum's snake_case conversion

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

/// Type declarations of spans that `enterSpan` and `leaveSpan` receive.
///
/// - Use `promote` function of spans to translate their
///   low-level `detail` pointer into a high-level struct.
/// - Raw `detail` pointer can be used instead of `promote`.\
///   Note that dereferencing it after the callback finishes is UB.
///
/// Spans that don't have additional info are just `struct {}`:\
/// `struct {}` instead of `void` to create identity,
/// so callbacks can use the span type in `switch` as unique prong.
pub const span = struct {
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

    /// Reference to a footnote declaration.
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
/// 1. Fenced code blocks info strings
/// 2. Image and Link titles
/// 3. Footnote labels
/// 4. Admonition type strings
pub const Attribute = struct {
    detail: md4c.MD_ATTRIBUTE,

    /// May return `null` because Attribute
    /// in `md4c` may contain `null` in
    /// its `text` to represent emptiness.
    pub fn promote(self: @This()) ?Promoted {
        const detail = self.detail;
        return switch (detail.text) {
            null => null,
            else => .{
                .data = detail.text[0..detail.size],
                .substr_types = @ptrCast(detail.substr_types),
                .substr_offsets = @ptrCast(detail.substr_offsets),
            },
        };
    }

    pub const Promoted = struct {
        data: []const u8,
        substr_types: [*]const SubstrType,
        substr_offsets: [*]const u32,

        pub fn iterate(self: @This()) SubstrIterator {
            return .{ .promoted = self, .substr_index = 0 };
        }
    };

    /// Iterator over the attribute textual data.
    ///
    /// Raw `substr_types` and `substr_offsets` of `Promoted`
    /// can be used instead of this abstraction.
    ///
    /// Invariants:
    /// - `substr_offsets[0] == 0`
    /// - `substr_offsets[last_index + 1] == data.len`
    pub const SubstrIterator = struct {
        promoted: Promoted,
        substr_index: usize,

        /// Returns substrings of `Text.data`:
        ///
        /// `normal`, `entity` or `null_char`.
        pub fn next(self: *@This()) ?Substr {
            const data = self.promoted.data;
            const types = self.promoted.substr_types;
            const offsets = self.promoted.substr_offsets;
            const substr_index = self.substr_index;

            const substr_start = offsets[substr_index];
            if (substr_start == data.len) return null;

            const substr_type = types[substr_index];

            self.substr_index += 1;
            const substr_end = offsets[self.substr_index];

            return .{
                .type = substr_type,
                .data = data[substr_start..substr_end],
            };
        }
    };

    pub const Substr = struct { type: SubstrType, data: []const u8 };
    const SubstrType = enum(md4c.MD_TEXTTYPE) {
        normal = @backingInt(TextType.normal),
        entity = @backingInt(TextType.entity),
        null_char = @backingInt(TextType.null_char),
    };
};

pub const TextType = enum(md4c.MD_TEXTTYPE) {
    normal = md4c.MD_TEXT_NORMAL,
    null_char = md4c.MD_TEXT_NULLCHAR,
    hard_line_break = md4c.MD_TEXT_BR,
    soft_line_break = md4c.MD_TEXT_SOFTBR,
    entity = md4c.MD_TEXT_ENTITY,
    code = md4c.MD_TEXT_CODE,
    html = md4c.MD_TEXT_HTML,
    latex_math = md4c.MD_TEXT_LATEXMATH,
};

test "`ListItem.promote` returns `Promoted.item` if `detail` isn't a task" {
    const item_detail: md4c.MD_BLOCK_LI_DETAIL = .{
        .is_task = 0,
        .task_mark = undefined,
        .task_mark_offset = undefined,
    };

    const list_item: block.ListItem = .{ .detail = &item_detail };

    const promoted = list_item.promote();
    try testing.expectEqual(.item, promoted);
}
test "`ListItem.promote` returns `Promoted.task` if `detail` is a task" {
    const marker = 'x';
    const marker_offset = 1;

    const task_detail: md4c.MD_BLOCK_LI_DETAIL = .{
        .is_task = 1,
        .task_mark = marker,
        .task_mark_offset = marker_offset,
    };

    const list_item: block.ListItem = .{ .detail = &task_detail };

    const promoted = list_item.promote();

    try testing.expectEqual(.task, promoted);

    try testing.expectEqual(marker, promoted.task.marker);
    try testing.expectEqual(marker_offset, promoted.task.marker_offset);
}

test "`Attribute.promote` returns `null` if `detail` is empty" {
    const empty_detail: md4c.MD_ATTRIBUTE = .{
        .text = null,
        .size = 0,
        .substr_types = null,
        .substr_offsets = null,
    };

    const attr: Attribute = .{ .detail = empty_detail };

    const promoted = attr.promote();
    try testing.expectEqual(null, promoted);
}
test "`Attribute.promote` returns `Promoted` if `detail` isn't empty" {
    const text = "abc";
    const substr_type: Attribute.SubstrType = .normal;

    const detail: md4c.MD_ATTRIBUTE = .{
        .text = text,
        .size = text.len,
        .substr_types = &[_]md4c.MD_TEXTTYPE{@backingInt(substr_type)},
        .substr_offsets = &[_]c_uint{ 0, text.len },
    };

    const attr: Attribute = .{ .detail = detail };

    const promoted = attr.promote();

    try testing.expect(promoted != null);

    try testing.expectEqual(text, promoted.?.data);

    try testing.expectEqual(substr_type, promoted.?.substr_types[0]);

    try testing.expectEqual(0, promoted.?.substr_offsets[0]);
    try testing.expectEqual(text.len, promoted.?.substr_offsets[1]);
}
