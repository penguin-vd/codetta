const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("../parser/parser.zig");
const ast = @import("../parser/ast.zig");

pub const Severity = enum { err, warning };

pub const Diagnostic = struct {
    severity: Severity,
    line: u32,
    column: u32,
    message: []const u8,
};

const NameSet = std.StringHashMapUnmanaged(void);

// Runs the full set of checks over `source`, returning every diagnostic at
// once rather than stopping at the first. Syntax errors are recovered from so
// later declarations still get linted; semantic rules only run once the file
// parses cleanly, when the tree can be trusted.
pub fn collect(allocator: Allocator, source: []const u8) ![]const Diagnostic {
    var parser = Parser.init(allocator, source);
    const lenient = try parser.parseLenient();

    var list: std.ArrayList(Diagnostic) = .empty;
    for (lenient.diagnostics) |d| {
        try list.append(allocator, .{ .severity = .err, .line = d.line, .column = d.column, .message = d.message });
    }

    try runRules(allocator, lenient.program, lenient.diagnostics.len > 0, &list);

    std.mem.sort(Diagnostic, list.items, {}, lessByPosition);
    return list.toOwnedSlice(allocator);
}

pub fn toJson(allocator: Allocator, source: []const u8) ![]const u8 {
    return writeJson(allocator, try collect(allocator, source));
}

fn runRules(allocator: Allocator, program: ast.Program, had_syntax_errors: bool, list: *std.ArrayList(Diagnostic)) !void {
    var chords: NameSet = .empty;
    var phrases: NameSet = .empty;
    var sections: NameSet = .empty;
    var song_index: ?ast.NodeIndex = null;
    var has_tempo = false;
    var has_time_signature = false;

    for (program.top_level) |index| {
        switch (program.nodes[index]) {
            .tempo => has_tempo = true,
            .time_signature => has_time_signature = true,
            .chord_def => |c| try chords.put(allocator, c.name, {}),
            .phrase_def => |p| try phrases.put(allocator, p.name, {}),
            .section_def => |s| try sections.put(allocator, s.name, {}),
            .song_def => song_index = index,
            else => {},
        }
    }

    if (!has_tempo) try warn(allocator, list, 1, 1, "no `tempo` set; defaults to 120 bpm", .{});
    if (!has_time_signature) try warn(allocator, list, 1, 1, "no `time_signature` set; defaults to 4/4", .{});

    // A partial tree from a syntax error makes reference checks unreliable.
    if (had_syntax_errors) return;

    if (song_index == null) {
        try err(allocator, list, 1, 1, "no `song` block; there is nothing to play", .{});
        return;
    }

    var used_chords: NameSet = .empty;
    var used_phrases: NameSet = .empty;
    var used_sections: NameSet = .empty;

    const ctx = Checker{
        .program = program,
        .chords = chords,
        .phrases = phrases,
        .sections = sections,
        .used_chords = &used_chords,
        .used_phrases = &used_phrases,
        .used_sections = &used_sections,
        .list = list,
        .allocator = allocator,
    };
    for (program.nodes[song_index.?].song_def.items) |item| try ctx.songItem(item);
    for (program.top_level) |index| switch (program.nodes[index]) {
        .section_def => |s| for (s.tracks) |track_index| try ctx.trackContent(program.nodes[track_index].track.content),
        .phrase_def => |p| for (p.body) |elem| try ctx.phraseElement(elem),
        else => {},
    };

    // Anything defined but never referenced is dead weight.
    for (program.top_level) |index| switch (program.nodes[index]) {
        .chord_def => |c| if (!used_chords.contains(c.name))
            try warn(allocator, list, c.line, c.column, "chord `{s}` is never used", .{c.name}),
        .phrase_def => |p| if (!used_phrases.contains(p.name))
            try warn(allocator, list, p.line, p.column, "phrase `{s}` is never used", .{p.name}),
        .section_def => |s| if (!used_sections.contains(s.name))
            try warn(allocator, list, s.line, s.column, "section `{s}` is never used", .{s.name}),
        else => {},
    };
}

// Mirrors the lowerer's traversal: records every name that's referenced and
// flags the ones that resolve to nothing.
const Checker = struct {
    program: ast.Program,
    chords: NameSet,
    phrases: NameSet,
    sections: NameSet,
    used_chords: *NameSet,
    used_phrases: *NameSet,
    used_sections: *NameSet,
    list: *std.ArrayList(Diagnostic),
    allocator: Allocator,

    fn songItem(self: Checker, index: ast.NodeIndex) !void {
        switch (self.program.nodes[index]) {
            .identifier => |n| {
                try self.used_sections.put(self.allocator, n.name, {});
                if (!self.sections.contains(n.name))
                    try err(self.allocator, self.list, n.line, n.column, "undefined section `{s}`", .{n.name});
            },
            .repeat => |r| try self.songItem(r.target),
            else => {},
        }
    }

    fn trackContent(self: Checker, index: ast.NodeIndex) !void {
        switch (self.program.nodes[index]) {
            .identifier => |n| {
                try self.used_phrases.put(self.allocator, n.name, {});
                if (!self.phrases.contains(n.name))
                    try err(self.allocator, self.list, n.line, n.column, "undefined phrase `{s}`", .{n.name});
            },
            .chord_ref => |n| try self.useChord(n.name, n.line, n.column),
            .sequence => |n| for (n.items) |item| try self.trackContent(item),
            .repeat => |n| try self.trackContent(n.target),
            .transform => |n| try self.trackContent(n.target),
            else => {},
        }
    }

    // Phrase bodies only reference chords (bare names lex as chord refs); a
    // `positioned` element wraps another phrase element.
    fn phraseElement(self: Checker, index: ast.NodeIndex) !void {
        switch (self.program.nodes[index]) {
            .chord_ref => |n| try self.useChord(n.name, n.line, n.column),
            .positioned => |n| try self.phraseElement(n.target),
            .transform => |n| try self.phraseElement(n.target),
            .repeat => |n| try self.phraseElement(n.target),
            .sequence => |n| for (n.items) |item| try self.phraseElement(item),
            else => {},
        }
    }

    fn useChord(self: Checker, name: []const u8, line: u32, column: u32) !void {
        try self.used_chords.put(self.allocator, name, {});
        if (!self.chords.contains(name))
            try err(self.allocator, self.list, line, column, "undefined chord `{s}`", .{name});
    }
};

fn warn(allocator: Allocator, list: *std.ArrayList(Diagnostic), line: u32, column: u32, comptime fmt: []const u8, args: anytype) !void {
    try list.append(allocator, .{ .severity = .warning, .line = line, .column = column, .message = try std.fmt.allocPrint(allocator, fmt, args) });
}

fn err(allocator: Allocator, list: *std.ArrayList(Diagnostic), line: u32, column: u32, comptime fmt: []const u8, args: anytype) !void {
    try list.append(allocator, .{ .severity = .err, .line = line, .column = column, .message = try std.fmt.allocPrint(allocator, fmt, args) });
}

fn lessByPosition(_: void, a: Diagnostic, b: Diagnostic) bool {
    if (a.line != b.line) return a.line < b.line;
    return a.column < b.column;
}

// The wire shape: the `severity` enum becomes a tidy "error"/"warning" string.
const DiagnosticJson = struct {
    severity: []const u8,
    line: u32,
    column: u32,
    message: []const u8,
};

pub fn writeJson(allocator: Allocator, diagnostics: []const Diagnostic) ![]u8 {
    const items = try allocator.alloc(DiagnosticJson, diagnostics.len);
    for (diagnostics, items) |d, *out| out.* = .{
        .severity = if (d.severity == .err) "error" else "warning",
        .line = d.line,
        .column = d.column,
        .message = d.message,
    };
    return std.json.Stringify.valueAlloc(allocator, items, .{});
}
