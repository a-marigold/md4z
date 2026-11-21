### About

Zig bindings of [md4c](https://github.com/mity/md4c) Markdown parser.

- Zig version - 0.17.1
- `md4c` version - 0.6.0
- `md4c-html` isn't supported

### Usage

The only APIs of this library:
1. `Parser(comptime Visitor: type)`.
2. `Parser(Visitor).init(visitor: Visitor, flags: u32)`.
3. `Parser(Visitor).parse(input: []const u8)`.

#### Flags (`FLAG_*`)

Flags specify features and extensions of Markdown to support.

`DIALECT_COMMONMARK` and `DIALECT_GITHUB` can also be used as flags,
because they're compounds of features of `FLAG_*` declarations.

#### Visitor

`Visitor` is a namespace (struct, enum, etc).

`Visitor` can have any fields, any public variable or fn declarations,
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
