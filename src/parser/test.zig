const std = @import("std");
const testing = std.testing;

const Parser = @import("parser.zig");
const ast = @import("ast.zig");

fn parse(allocator: std.mem.Allocator, input: []const u8) !ast.Program {
    var parser = Parser.init(allocator, input);
    return parser.parseProgram();
}

test "tempo and time signature" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "tempo 120\ntime_signature 4/4");

    try testing.expectEqual(@as(usize, 2), program.top_level.len);
    try testing.expectEqual(@as(u32, 120), program.nodes[program.top_level[0]].tempo.bpm);

    const ts = program.nodes[program.top_level[1]].time_signature;
    try testing.expectEqual(@as(u32, 4), ts.numerator);
    try testing.expectEqual(@as(u32, 4), ts.denominator);
}

test "chord definition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "chord Cmaj = [C4 E4 G4]");

    const chord = program.nodes[program.top_level[0]].chord_def;
    try testing.expectEqualStrings("Cmaj", chord.name);
    try testing.expectEqual(@as(usize, 3), chord.notes.len);
    try testing.expectEqual(ast.Pitch.c, chord.notes[0].pitch);
    try testing.expectEqual(ast.Accidental.natural, chord.notes[0].accidental);
    try testing.expectEqual(@as(u8, 4), chord.notes[0].octave);
    try testing.expectEqual(ast.Pitch.g, chord.notes[2].pitch);
}

test "phrase with notes, rest, dotted duration and accidentals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "phrase melody =\n  C4.quarter Bb3.quarter.dot rest.half F#5.eighth");

    const phrase = program.nodes[program.top_level[0]].phrase_def;
    try testing.expectEqualStrings("melody", phrase.name);
    try testing.expectEqual(@as(usize, 4), phrase.body.len);

    const note1 = program.nodes[phrase.body[0]].note;
    try testing.expectEqual(ast.Pitch.c, note1.pitched.pitch);
    try testing.expectEqual(@as(u8, 4), note1.pitched.octave);
    try testing.expectEqual(ast.DurationKind.quarter, note1.duration.kind);
    try testing.expectEqual(false, note1.duration.dotted);

    const note2 = program.nodes[phrase.body[1]].note;
    try testing.expectEqual(ast.Accidental.flat, note2.pitched.accidental);
    try testing.expectEqual(true, note2.duration.dotted);

    const rest = program.nodes[phrase.body[2]].rest;
    try testing.expectEqual(ast.DurationKind.half, rest.duration.kind);

    const note4 = program.nodes[phrase.body[3]].note;
    try testing.expectEqual(ast.Accidental.sharp, note4.pitched.accidental);
    try testing.expectEqual(@as(u8, 5), note4.pitched.octave);
}

test "phrase with positioned note and dynamics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\phrase opening =
        \\  C4.quarter
        \\  @1.1 C3.whole
        \\  dynamic @0 p
        \\  dynamic @0.3 crescendo to f over 1 bar
    );

    const phrase = program.nodes[program.top_level[0]].phrase_def;
    try testing.expectEqual(@as(usize, 4), phrase.body.len);

    const positioned = program.nodes[phrase.body[1]].positioned;
    try testing.expectEqual(@as(u32, 1), positioned.position.bar);
    try testing.expectEqual(@as(u32, 1), positioned.position.beat);
    try testing.expectEqual(ast.DurationKind.whole, program.nodes[positioned.target].note.duration.kind);

    const level = program.nodes[phrase.body[2]].dynamic_level;
    try testing.expectEqual(@as(u32, 0), level.position.bar);
    try testing.expectEqual(ast.DynamicLevel.p, level.level);

    const shape = program.nodes[phrase.body[3]].dynamic_shape;
    try testing.expectEqual(@as(u32, 0), shape.position.bar);
    try testing.expectEqual(@as(u32, 3), shape.position.beat);
    try testing.expectEqual(ast.DynamicShapeKind.crescendo, shape.shape);
    try testing.expectEqual(ast.DynamicLevel.f, shape.target);
    try testing.expectEqual(@as(u32, 1), shape.bars);
}

test "chord reference inside phrase" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "phrase chords =\n  Cmaj.half Fmaj.whole");

    const phrase = program.nodes[program.top_level[0]].phrase_def;
    const ref = program.nodes[phrase.body[0]].chord_ref;
    try testing.expectEqualStrings("Cmaj", ref.name);
    try testing.expectEqual(ast.DurationKind.half, ref.duration.kind);
}

test "section with tracks, repetition and transformations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\section verse =
        \\  track melody:  melody transpose +5 reverse augment x2
        \\  track bass:    bassline * 2
    );

    const section = program.nodes[program.top_level[0]].section_def;
    try testing.expectEqualStrings("verse", section.name);
    try testing.expectEqual(@as(usize, 2), section.tracks.len);

    const melody_track = program.nodes[section.tracks[0]].track;
    try testing.expectEqualStrings("melody", melody_track.name);

    // melody transpose +5 reverse augment x2
    // -> transform(augment x2, transform(reverse, transform(transpose +5, identifier(melody))))
    const augment = program.nodes[melody_track.content].transform;
    try testing.expectEqual(@as(u32, 2), augment.op.augment);

    const reverse = program.nodes[augment.target].transform;
    try testing.expectEqual(ast.TransformKind.reverse, reverse.op);

    const transpose = program.nodes[reverse.target].transform;
    try testing.expectEqual(@as(i32, 5), transpose.op.transpose);
    try testing.expectEqualStrings("melody", program.nodes[transpose.target].identifier.name);

    const bass_track = program.nodes[section.tracks[1]].track;
    const repeat = program.nodes[bass_track.content].repeat;
    try testing.expectEqual(@as(u32, 2), repeat.count);
    try testing.expectEqualStrings("bassline", program.nodes[repeat.target].identifier.name);
}

test "song with repetition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "song =\n  intro\n  verse * 2\n  chorus");

    const song = program.nodes[program.top_level[0]].song_def;
    try testing.expectEqual(@as(usize, 3), song.items.len);
    try testing.expectEqualStrings("intro", program.nodes[song.items[0]].identifier.name);

    const repeat = program.nodes[song.items[1]].repeat;
    try testing.expectEqual(@as(u32, 2), repeat.count);
    try testing.expectEqualStrings("verse", program.nodes[repeat.target].identifier.name);

    try testing.expectEqualStrings("chorus", program.nodes[song.items[2]].identifier.name);
}

fn expectSyntaxError(allocator: std.mem.Allocator, input: []const u8, line: u32, column: u32, message: []const u8) !void {
    var parser = Parser.init(allocator, input);
    try testing.expectError(error.SyntaxError, parser.parseProgram());

    const diag = parser.diagnostic orelse return error.TestExpectedDiagnostic;
    try testing.expectEqual(line, diag.line);
    try testing.expectEqual(column, diag.column);
    try testing.expectEqualStrings(message, diag.message);
}

test "unexpected token at top level" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectSyntaxError(arena.allocator(), "melody transpose +5",
        1, 1, "expected a top-level declaration, found identifier 'melody'");
}

test "missing token reports expectation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectSyntaxError(arena.allocator(), "tempo",
        1, 6, "expected int, found eof ''");
}

test "unknown duration reports location" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectSyntaxError(arena.allocator(), "phrase melody =\n  C4.minim",
        2, 6, "expected duration, found identifier 'minim'");
}

test "invalid note reports location" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectSyntaxError(arena.allocator(), "chord Cmaj = [H4 E4 G4]",
        1, 15, "expected note, found identifier 'H4'");
}

test "unknown dynamic level reports location" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectSyntaxError(arena.allocator(), "phrase melody =\n  dynamic @0 superloud",
        2, 14, "unknown dynamic level 'superloud'");
}

test "invalid multiplier reports location" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectSyntaxError(arena.allocator(),
        \\section verse =
        \\  track melody: melody augment xmany
    , 2, 32, "invalid multiplier 'xmany'");
}

test "ignores comments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "tempo 120 -- BPM\nsong =\n  intro");

    try testing.expectEqual(@as(usize, 2), program.top_level.len);
    try testing.expectEqual(@as(u32, 120), program.nodes[program.top_level[0]].tempo.bpm);
}
