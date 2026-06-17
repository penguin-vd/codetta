const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("../parser/parser.zig");
const ast = @import("../parser/ast.zig");

const Candidate = struct { label: []const u8, detail: []const u8, type: []const u8 };

const keywords = [_]Candidate{
    .{ .label = "tempo", .detail = "set the beats per minute", .type = "keyword" },
    .{ .label = "time_signature", .detail = "set the meter, e.g. 4/4", .type = "keyword" },
    .{ .label = "chord", .detail = "define a named chord", .type = "keyword" },
    .{ .label = "phrase", .detail = "define a reusable phrase", .type = "keyword" },
    .{ .label = "section", .detail = "group tracks into a section", .type = "keyword" },
    .{ .label = "track", .detail = "a named voice within a section", .type = "keyword" },
    .{ .label = "song", .detail = "arrange sections into a song", .type = "keyword" },
    .{ .label = "rest", .detail = "a silence of the given duration", .type = "keyword" },
    .{ .label = "dynamic", .detail = "set or shape the volume", .type = "keyword" },
    .{ .label = "transpose", .detail = "shift pitch by N semitones", .type = "keyword" },
    .{ .label = "reverse", .detail = "play the target backwards", .type = "keyword" },
    .{ .label = "augment", .detail = "stretch durations by xN", .type = "keyword" },
    .{ .label = "diminish", .detail = "compress durations by xN", .type = "keyword" },
    .{ .label = "arp", .detail = "arpeggiate (default: up)", .type = "keyword" },
    .{ .label = "crescendo", .detail = "grow louder toward a level", .type = "keyword" },
    .{ .label = "diminuendo", .detail = "fade quieter toward a level", .type = "keyword" },
    .{ .label = "to", .detail = "target level of a dynamic shape", .type = "keyword" },
    .{ .label = "over", .detail = "span of a dynamic shape, in bars", .type = "keyword" },
};

const arp_modes = [_]Candidate{
    .{ .label = "up", .detail = "arpeggiate low to high", .type = "property" },
    .{ .label = "down", .detail = "arpeggiate high to low", .type = "property" },
    .{ .label = "up_down", .detail = "up then down (no repeated endpoints)", .type = "property" },
    .{ .label = "bounce", .detail = "up then down (repeated endpoints)", .type = "property" },
};

const durations = [_]Candidate{
    .{ .label = "whole", .detail = "duration", .type = "property" },
    .{ .label = "half", .detail = "duration", .type = "property" },
    .{ .label = "quarter", .detail = "duration", .type = "property" },
    .{ .label = "eighth", .detail = "duration", .type = "property" },
    .{ .label = "sixteenth", .detail = "duration", .type = "property" },
    .{ .label = "dot", .detail = "extend the preceding duration by half", .type = "property" },
};

const dynamics = [_]Candidate{
    .{ .label = "ppp", .detail = "dynamic: softest", .type = "constant" },
    .{ .label = "pp", .detail = "dynamic: very soft", .type = "constant" },
    .{ .label = "p", .detail = "dynamic: soft", .type = "constant" },
    .{ .label = "mp", .detail = "dynamic: medium soft", .type = "constant" },
    .{ .label = "mf", .detail = "dynamic: medium loud", .type = "constant" },
    .{ .label = "f", .detail = "dynamic: loud", .type = "constant" },
    .{ .label = "ff", .detail = "dynamic: very loud", .type = "constant" },
    .{ .label = "fff", .detail = "dynamic: loudest", .type = "constant" },
};

pub fn completionsJson(allocator: Allocator, source: []const u8) ![]const u8 {
    var items: std.ArrayList(Candidate) = .empty;
    try items.appendSlice(allocator, &keywords);
    try items.appendSlice(allocator, &durations);
    try items.appendSlice(allocator, &arp_modes);
    try items.appendSlice(allocator, &dynamics);

    var parser = Parser.init(allocator, source);
    const lenient = try parser.parseLenient();
    for (lenient.program.top_level) |index| switch (lenient.program.nodes[index]) {
        .chord_def => |c| try items.append(allocator, .{ .label = c.name, .detail = try formatNotes(allocator, c.notes), .type = "class" }),
        .phrase_def => |p| try items.append(allocator, .{ .label = p.name, .detail = "phrase", .type = "variable" }),
        .section_def => |s| try items.append(allocator, .{ .label = s.name, .detail = "section", .type = "namespace" }),
        else => {},
    };

    return std.json.Stringify.valueAlloc(allocator, items.items, .{});
}

pub fn hoverJson(allocator: Allocator, source: []const u8, line: u32, column: u32) ![]const u8 {
    const word = wordAt(source, line, column) orelse return "";

    var parser = Parser.init(allocator, source);
    const lenient = try parser.parseLenient();
    for (lenient.program.top_level) |index| switch (lenient.program.nodes[index]) {
        .chord_def => |c| if (std.mem.eql(u8, c.name, word))
            return hover(allocator, try heading(allocator, "chord", c.name), try formatNotes(allocator, c.notes)),
        .phrase_def => |p| if (std.mem.eql(u8, p.name, word))
            return hover(allocator, try heading(allocator, "phrase", p.name), try countDetail(allocator, p.body.len, "element")),
        .section_def => |s| if (std.mem.eql(u8, s.name, word))
            return hover(allocator, try heading(allocator, "section", s.name), try trackNames(allocator, lenient.program, s.tracks)),
        else => {},
    };

    if (builtin(word)) |c| return hover(allocator, c.label, c.detail);
    if (noteMidi(word)) |midi|
        return hover(allocator, word, try std.fmt.allocPrint(allocator, "note · MIDI {d}", .{midi}));

    return "";
}

// The symbol's definition as a JSON `{line, column}`, or empty when it has no
// in-source definition (a keyword, note, or duration).
pub fn definitionJson(allocator: Allocator, source: []const u8, line: u32, column: u32) ![]const u8 {
    const word = wordAt(source, line, column) orelse return "";

    var parser = Parser.init(allocator, source);
    const lenient = try parser.parseLenient();
    for (lenient.program.top_level) |index| switch (lenient.program.nodes[index]) {
        .chord_def => |c| if (std.mem.eql(u8, c.name, word)) return location(allocator, c.line, c.column),
        .phrase_def => |p| if (std.mem.eql(u8, p.name, word)) return location(allocator, p.line, p.column),
        .section_def => |s| if (std.mem.eql(u8, s.name, word)) return location(allocator, s.line, s.column),
        else => {},
    };

    return "";
}

fn hover(allocator: Allocator, title: []const u8, detail: []const u8) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .title = title, .detail = detail }, .{});
}

fn location(allocator: Allocator, line: u32, column: u32) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .line = line, .column = column }, .{});
}

// The fixed-vocabulary entry for `word`, if any (keyword, duration, or dynamic).
fn builtin(word: []const u8) ?Candidate {
    for (keywords) |c| if (std.mem.eql(u8, c.label, word)) return c;
    for (durations) |c| if (std.mem.eql(u8, c.label, word)) return c;
    for (arp_modes) |c| if (std.mem.eql(u8, c.label, word)) return c;
    for (dynamics) |c| if (std.mem.eql(u8, c.label, word)) return c;

    // Match duration with numeric prefix, e.g. "2whole", "3half"
    var i: usize = 0;
    while (i < word.len and word[i] >= '0' and word[i] <= '9') i += 1;
    if (i > 0 and i < word.len) {
        for (durations) |c| if (std.mem.eql(u8, c.label, word[i..])) return c;
    }

    return null;
}

// The MIDI number of a note literal like C4, F#3, or Bb2 (C4 = 60), or null
// when `word` isn't a note. Mirrors the lexer's note grammar.
fn noteMidi(word: []const u8) ?i32 {
    if (word.len < 2) return null;
    const semitone: i32 = switch (word[0]) {
        'C' => 0, 'D' => 2, 'E' => 4, 'F' => 5, 'G' => 7, 'A' => 9, 'B' => 11,
        else => return null,
    };

    var i: usize = 1;
    var accidental: i32 = 0;
    if (word[i] == '#') {
        accidental = 1;
        i += 1;
    } else if (word[i] == 'b') {
        accidental = -1;
        i += 1;
    }
    if (i >= word.len) return null;

    var octave: i32 = 0;
    while (i < word.len) : (i += 1) {
        if (word[i] < '0' or word[i] > '9') return null;
        octave = octave * 10 + (word[i] - '0');
    }
    return (octave + 1) * 12 + semitone + accidental;
}

fn heading(allocator: Allocator, kind: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ kind, name });
}

fn countDetail(allocator: Allocator, count: usize, noun: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d} {s}{s}", .{ count, noun, if (count == 1) "" else "s" });
}

fn formatNotes(allocator: Allocator, notes: []const ast.Pitched) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (notes, 0..) |p, i| {
        if (i != 0) try out.append(allocator, ' ');
        const letter: u8 = switch (p.pitch) {
            .c => 'C', .d => 'D', .e => 'E', .f => 'F', .g => 'G', .a => 'A', .b => 'B',
        };
        const accidental: []const u8 = switch (p.accidental) {
            .natural => "", .sharp => "#", .flat => "b",
        };
        const chunk = try std.fmt.allocPrint(allocator, "{c}{s}{d}", .{ letter, accidental, p.octave });
        try out.appendSlice(allocator, chunk);
    }
    return out.toOwnedSlice(allocator);
}

fn trackNames(allocator: Allocator, program: ast.Program, tracks: []const ast.NodeIndex) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (tracks, 0..) |index, i| {
        if (i != 0) try out.appendSlice(allocator, ", ");
        try out.appendSlice(allocator, program.nodes[index].track.name);
    }
    return out.toOwnedSlice(allocator);
}

fn wordAt(source: []const u8, line: u32, column: u32) ?[]const u8 {
    if (line == 0 or column == 0) return null;

    var idx: usize = 0;
    var cur_line: u32 = 1;
    while (cur_line < line) {
        if (idx >= source.len) return null;
        if (source[idx] == '\n') cur_line += 1;
        idx += 1;
    }

    var line_end = idx;
    while (line_end < source.len and source[line_end] != '\n') line_end += 1;
    const text = source[idx..line_end];

    var at: usize = column - 1;
    if (at > text.len) return null;
    if (at == text.len or !isWord(text[at])) {
        if (at == 0) return null;
        at -= 1;
        if (!isWord(text[at])) return null;
    }

    var start = at;
    while (start > 0 and isWord(text[start - 1])) start -= 1;
    var end = at + 1;
    while (end < text.len and isWord(text[end])) end += 1;
    return text[start..end];
}

// `#` so a sharp note like F#3 reads as one word; the lexer treats it the same.
fn isWord(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '#';
}
