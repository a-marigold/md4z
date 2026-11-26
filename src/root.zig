const parser = @import("parser.zig");

pub const Parser = parser.Parser;
pub const ParseError = parser.ParseError;
pub const block = parser.block;
pub const span = parser.span;
pub const Attribute = parser.Attribute;
pub const TextType = parser.TextType;

pub const Flags = parser.Flags;

test {
    _ = &parser;
}
