const std = @import("std");
const testing = std.testing;

const types = @import("types.zig");
const parser = @import("parser.zig");

pub const Parser = parser.Parser;
pub const ParseError = parser.ParseError;

pub const blocks = types.blocks;
pub const spans = types.spans;
pub const Attribute = types.Attribute;
pub const TextType = types.TextType;

pub const Flags = parser.Flags;

test {
    testing.refAllDecls(@This());
}
