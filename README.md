# Usage

The only APIs of this library:
1. `Parser(comptime Visitor: type)`.
2. `Parser.init(visitor, flags)`.
3. `Parser.parse(input: []const u8)`.

`Visitor` is a namespace (struct, enum, etc).
Visitor can have any fields, any public variable or fn declarations,
but it must have at least the 5 callbacks as `pub fn`.

Callbacks receive a mutable pointer to their visitor.

Callbacks can return errors. 
If a callback returns an error, `parse` stops and returns that error.

There are 5 callbacks in `md4c` library:
```zig
// Can be any namespace (struct, enum, union, opaque)
const Visitor = struct {
    user_field: SomeType,
    user_field1: SomeType1,

    // Callbacks can or can not return errors

	// 
    pub fn enterBlock(self: *@This(), block_type: BlockType, block: *const Block) SomeError!void {}
    pub fn leaveBlock(self: *@This(), block_type: BlockType, block: *const Block) !void {}

    //
    pub fn enterSpan(self: *@This(), span_type: SpanType, block: *const Span) void {}
    pub fn leaveSpan(self: *@This(), span_type: SpanType, block: *const Span) void {}
    
	//
	pub fn text(self: *@This(), data: []const u8) void {}
};

const parser: Parser(Visitor) = .init(.{ .user_field = ... }, flags);

// This may return an error from a callback,
// which stops the parsing completely
try parser.parse("# *Hello*");
```
