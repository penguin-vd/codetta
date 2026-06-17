//! Freestanding WASM reactor exposing Codetta's compile pipeline to the
//! browser. The parse and lower stages are already IO-free, so this module
//! just wires `source bytes -> Score -> backend bytes` and hands the result
//! back across the JS boundary.
//!
//! ABI (all lengths in bytes):
//!   alloc(len) -> ptr        reserve `len` bytes for the source string
//!   compileJson(ptr, len)    compile to @tonejs/midi-style JSON; -> ok?
//!   compileMidi(ptr, len)    compile to a Standard MIDI File; -> ok?
//!   diagnose(ptr, len)       collect diagnostics as JSON; -> always true
//!   completions(ptr, len)    list completion items as JSON; -> always true
//!   hover(ptr, len, ln, col) document the symbol at line/col; -> always true
//!   definition(p, l, ln, col) locate the symbol's definition; -> always true
//!   resultPtr() -> ptr       start of the last result (JSON, MIDI, or error)
//!   resultLen() -> len       length of the last result
//!
//! On failure compile* returns false and the result holds a UTF-8 error
//! message. The result lives until the next compile* call, so JS must copy
//! it out before calling again.

const std = @import("std");

const Parser = @import("parser/parser.zig");
const Lower = @import("ir/lower.zig");
const Midi = @import("midi/midi.zig");
const Web = @import("web/web.zig");
const Diag = @import("diag/diag.zig");
const Lsp = @import("lsp/lsp.zig");

const page_allocator = std.heap.wasm_allocator;

// Source buffers handed out by `alloc` persist until the matching compile*
// frees them. Everything a compile produces (Score, output, error text)
// lives in this arena, reset at the start of each call.
var arena_state: ?std.heap.ArenaAllocator = null;

fn arena() *std.heap.ArenaAllocator {
    if (arena_state == null) arena_state = std.heap.ArenaAllocator.init(page_allocator);
    return &arena_state.?;
}

// One borrowed source string plus a fresh arena for the work it drives. Every
// export opens one of these and defers `close()`, so the marshalling - reset
// the arena, view the input bytes, free them when done - lives in one place.
const Source = struct {
    a: std.mem.Allocator,
    bytes: []u8,

    fn open(ptr: [*]u8, len: usize) Source {
        _ = arena().reset(.retain_capacity);
        return .{ .a = arena().allocator(), .bytes = ptr[0..len] };
    }

    fn close(self: Source) void {
        page_allocator.free(self.bytes);
    }
};

var result: []const u8 = "";

export fn alloc(len: usize) ?[*]u8 {
    const buf = page_allocator.alloc(u8, len) catch return null;
    return buf.ptr;
}

export fn resultPtr() [*]const u8 {
    return result.ptr;
}

export fn resultLen() usize {
    return result.len;
}

export fn compileJson(ptr: [*]u8, len: usize) bool {
    return compile(ptr, len, Web.write);
}

export fn compileMidi(ptr: [*]u8, len: usize) bool {
    return compile(ptr, len, Midi.write);
}

// Collects every diagnostic for the source (errors and lint warnings) as a
// JSON array. The result is always valid JSON, even on internal failure.
export fn diagnose(ptr: [*]u8, len: usize) bool {
    const src = Source.open(ptr, len);
    defer src.close();

    result = Diag.toJson(src.a, src.bytes) catch "[]";
    return true;
}

// Lists every completion the document can offer as a JSON array; CodeMirror
// filters it against the prefix being typed, so no position is needed.
export fn completions(ptr: [*]u8, len: usize) bool {
    const src = Source.open(ptr, len);
    defer src.close();

    result = Lsp.completionsJson(src.a, src.bytes) catch "[]";
    return true;
}

// Documents the symbol at the 1-based line/column as a JSON object, or an
// empty result when the cursor isn't over a known name or keyword.
export fn hover(ptr: [*]u8, len: usize, line: u32, column: u32) bool {
    const src = Source.open(ptr, len);
    defer src.close();

    result = Lsp.hoverJson(src.a, src.bytes, line, column) catch "";
    return true;
}

// Locates the definition of the symbol at the 1-based line/column as a JSON
// `{line, column}`, or an empty result when it has no in-source definition.
export fn definition(ptr: [*]u8, len: usize, line: u32, column: u32) bool {
    const src = Source.open(ptr, len);
    defer src.close();

    result = Lsp.definitionJson(src.a, src.bytes, line, column) catch "";
    return true;
}

const Backend = fn (std.mem.Allocator, @import("ir/score.zig").Score) anyerror![]u8;

fn compile(ptr: [*]u8, len: usize, backend: *const Backend) bool {
    // The source outlives parsing/lowering (Score borrows track names from
    // it) but the backend copies what it needs, so we can free afterwards.
    const src = Source.open(ptr, len);
    defer src.close();
    const a = src.a;

    var parser = Parser.init(a, src.bytes);
    const program = parser.parseProgram() catch |err| {
        if (err == error.SyntaxError) {
            const diag = parser.diagnostic.?;
            return fail(a, "{d}:{d}: {s}", .{ diag.line, diag.column, diag.message });
        }
        return fail(a, "{s}", .{@errorName(err)});
    };

    var lowerer = Lower.init(a, program);
    const score = lowerer.lower() catch |err| return fail(a, "{s}", .{@errorName(err)});

    result = backend(a, score) catch |err| return fail(a, "{s}", .{@errorName(err)});
    return true;
}

fn fail(a: std.mem.Allocator, comptime fmt: []const u8, args: anytype) bool {
    result = std.fmt.allocPrint(a, fmt, args) catch "out of memory";
    return false;
}
