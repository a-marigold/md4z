### About

Zig bindings of [md4c](https://github.com/mity/md4c) Markdown parser.

- Zig version - 0.17.1
- `md4c` version - 0.6.0
- `md4c-html` isn't supported

### Installation

1. `zig fetch --save https://github.com/a-marigold/md4z`
2. ```zig
   // `build.zig`
   const md4z = b.dependency("md4z", .{ .target = target, .optimize = optimize });
   const md4z_mod = md4z.module("md4z");
   ```
 
### Usage

The only API of this library:
1. `Parser(comptime Visitor: type)`.
2. `Parser(Visitor).init(visitor: *Visitor, flags: Flags)`.
3. `Parser(Visitor).parse(input: []const u8)`.

#### Flags

`Flags` is a `packed struct` with `bool` bits that specify
features and extensions of Markdown to support.

`DIALECT_COMMONMARK` and `DIALECT_GITHUB` can also be used as flags.

#### Visitor

`Visitor` is a namespace (`struct`, `enum`, `union`, `opaque`).

`Visitor` can have any fields, any public variable or fn declarations,
but it must have all the callbacks as `pub fn`.

Parameters of callbacks: 
- A mutable pointer to the visitor.
- `enterBlock`, `leaveBlock`, `enterSpan` and `leaveSpan` also receive:\
  `Block` or `Span` - a tagged union with pointers to info about the block or span.
- `text` also receives:
  1. `text_type`, which is an enum.
  2. `data`, which is a **non**-null-terminated slice of the text.

Callbacks can return errors. 
If a callback returns an error, `parse` stops and returns that error.

Example with the 5 callbacks from `md4c`:
```zig
const md4z = @import("md4z");

// Can be any namespace (struct, enum, union, opaque)
const Visitor = struct {
    foo: Foo,
    bar: *const Bar,

    // Callbacks can or can not return errors

    // It's guaranteed that `leaveBlock` is called
    // for every span that appears in `enterBlock`
    // (if there is no error)
    pub fn enterBlock(self: *@This(), block: md4z.Block) SomeError!void {}
    pub fn leaveBlock(self: *@This(), block: md4z.Block) !void {}

    // It's guaranteed that `leaveSpan` is called
    // for every span that appears in `enterSpan`
    // (if there is no error)
    pub fn enterSpan(self: *@This(), span: md4z.Span) void {}
    pub fn leaveSpan(self: *@This(), span: md4z.Span) AnotherError!void {}

    // Isn't called for the whole content of a block or a span at once.
    // Instead, textual contents of blocks and spans can be
    // sliced into parts so `text` is called multiple times for it
    pub fn text(self: *@This(), text_type: md4z.TextType, data: []const u8) void {}
};

var visitor: Visitor = .{ .foo = ... };
const flags: md4z.Flags = .{ .collapse_whitespace = false, ... };
var parser: md4z.Parser(Visitor) = .init(&visitor, flags);

// May return an error from a callback,
// which stops the parsing completely
try parser.parse("# *Hello*");
```
