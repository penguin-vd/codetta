const std = @import("std");
const testing = std.testing;

const Lsp = @import("lsp.zig");

const score =
    \\tempo 120
    \\time_signature 4/4
    \\chord Cmaj = [C4 E4 G4]
    \\phrase melody =
    \\  Cmaj.quarter Cmaj.quarter
    \\section intro =
    \\  track lead: melody
    \\  track bass: melody
    \\song =
    \\  intro
;

test "completions always offer the fixed keyword vocabulary" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Even on empty, unparseable source the keyword set is available.
    const json = try Lsp.completionsJson(arena.allocator(), "chord");
    try testing.expect(std.mem.indexOf(u8, json, "\"label\":\"tempo\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"label\":\"quarter\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"label\":\"mf\"") != null);
}

test "completions include names defined in the document" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const json = try Lsp.completionsJson(arena.allocator(), score);
    try testing.expect(std.mem.indexOf(u8, json, "\"label\":\"Cmaj\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"label\":\"melody\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"label\":\"intro\"") != null);
    // A chord carries its notes as the detail.
    try testing.expect(std.mem.indexOf(u8, json, "C4 E4 G4") != null);
}

test "hover on a chord reports its notes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `chord Cmaj` -> the name starts at column 7 on line 3.
    const json = try Lsp.hoverJson(arena.allocator(), score, 3, 7);
    try testing.expect(std.mem.indexOf(u8, json, "chord Cmaj") != null);
    try testing.expect(std.mem.indexOf(u8, json, "C4 E4 G4") != null);
}

test "hover on a section lists its tracks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `section intro` on line 6, name at column 9.
    const json = try Lsp.hoverJson(arena.allocator(), score, 6, 9);
    try testing.expect(std.mem.indexOf(u8, json, "section intro") != null);
    try testing.expect(std.mem.indexOf(u8, json, "lead, bass") != null);
}

test "hover on a keyword shows its documentation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const json = try Lsp.hoverJson(arena.allocator(), score, 1, 1);
    try testing.expect(std.mem.indexOf(u8, json, "\"title\":\"tempo\"") != null);
}

test "hover on whitespace or unknown words yields nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Column past the end of an indented line lands on nothing.
    const blank = try Lsp.hoverJson(arena.allocator(), score, 5, 40);
    try testing.expectEqualStrings("", blank);
}

test "hover on a note reports its MIDI number" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `[C4 E4 G4]` on line 3: the C4 starts at column 15.
    const json = try Lsp.hoverJson(arena.allocator(), score, 3, 15);
    try testing.expect(std.mem.indexOf(u8, json, "\"title\":\"C4\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "MIDI 60") != null);
}

test "hover on a rest documents it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const json = try Lsp.hoverJson(arena.allocator(), "phrase m =\n  rest.quarter", 2, 3);
    try testing.expect(std.mem.indexOf(u8, json, "\"title\":\"rest\"") != null);
}

test "definition resolves a reference to its source location" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `track lead: melody` on line 7: the `melody` reference starts at column 15.
    const json = try Lsp.definitionJson(arena.allocator(), score, 7, 15);
    // `phrase melody` is defined on line 4, name at column 8.
    try testing.expect(std.mem.indexOf(u8, json, "\"line\":4") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"column\":8") != null);
}

test "definition on a keyword has no in-source target" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const blank = try Lsp.definitionJson(arena.allocator(), score, 1, 1);
    try testing.expectEqualStrings("", blank);
}
