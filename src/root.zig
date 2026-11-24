const parser = @import("parser.zig");

pub const Parser = parser.Parser;
pub const ParseError = parser.ParseError;
pub const BlockType = parser.BlockType;
pub const Block = parser.Block;
pub const SpanType = parser.SpanType;
pub const Span = parser.Span;
pub const TextType = parser.TextType;

pub const Flags = parser.Flags;

pub const DIALECT_COMMONMARK = parser.DIALECT_COMMONMARK;
pub const DIALECT_GITHUB = parser.DIALECT_GITHUB;

test {
    _ = &parser;
}
