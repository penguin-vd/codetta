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

test "phrase with voice cursor reset and dynamics" {
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
    try testing.expectEqual(@as(usize, 5), phrase.body.len);

    const voice = program.nodes[phrase.body[1]].voice;
    try testing.expectEqual(@as(u32, 1), voice.position.bar);
    try testing.expectEqual(@as(u32, 1), voice.position.beat);
    try testing.expectEqual(ast.DurationKind.whole, program.nodes[phrase.body[2]].note.duration.kind);

    const level = program.nodes[phrase.body[3]].dynamic_level;
    try testing.expectEqual(@as(u32, 0), level.position.bar);
    try testing.expectEqual(ast.DynamicLevel.p, level.level);

    const shape = program.nodes[phrase.body[4]].dynamic_shape;
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
        \\  track melody:  melody arp transpose +5 reverse augment x2
        \\  track bass:    bassline * 2
    );

    const section = program.nodes[program.top_level[0]].section_def;
    try testing.expectEqualStrings("verse", section.name);
    try testing.expectEqual(@as(usize, 2), section.tracks.len);

    const melody_track = program.nodes[section.tracks[0]].track;
    try testing.expectEqualStrings("melody", melody_track.name);

    // melody transpose +5 reverse augment x2
    // -> transform(augment x2, transform(reverse, transform(transpose +5, transform(arp, identifier(melody)))))
    const augment = program.nodes[melody_track.content].transform;
    try testing.expectEqual(@as(u32, 2), augment.op.augment);

    const reverse = program.nodes[augment.target].transform;
    try testing.expectEqual(ast.TransformKind.reverse, reverse.op);

    const transpose = program.nodes[reverse.target].transform;
    try testing.expectEqual(@as(i32, 5), transpose.op.transpose);

    const arp = program.nodes[transpose.target].transform;
    try testing.expectEqual(ast.TransformKind{ .arp = .{ .mode = .up } }, arp.op);

    try testing.expectEqualStrings("melody", program.nodes[arp.target].identifier.name);

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

test "staccato and legato transforms on phrase elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\phrase funky =
        \\  C3.quarter staccato
        \\  D3.eighth legato
    );

    const phrase = program.nodes[program.top_level[0]].phrase_def;
    try testing.expectEqual(@as(usize, 2), phrase.body.len);

    const staccato = program.nodes[phrase.body[0]].transform;
    try testing.expectEqual(ast.TransformKind{ .articulation = .staccato }, staccato.op);
    _ = program.nodes[staccato.target].note;

    const legato = program.nodes[phrase.body[1]].transform;
    try testing.expectEqual(ast.TransformKind{ .articulation = .legato }, legato.op);
    _ = program.nodes[legato.target].note;
}

test "staccato and legato on track content" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\section verse =
        \\  track synth: melody staccato
        \\  track strings: melody legato
    );

    const section = program.nodes[program.top_level[0]].section_def;

    const synth = program.nodes[section.tracks[0]].track;
    const s = program.nodes[synth.content].transform;
    try testing.expectEqual(ast.TransformKind{ .articulation = .staccato }, s.op);

    const strings = program.nodes[section.tracks[1]].track;
    const l = program.nodes[strings.content].transform;
    try testing.expectEqual(ast.TransformKind{ .articulation = .legato }, l.op);
}

test "staccato chains with arp" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\section verse =
        \\  track keys: Cmaj.whole arp.up staccato
    );

    const section = program.nodes[program.top_level[0]].section_def;
    const track = program.nodes[section.tracks[0]].track;

    const staccato = program.nodes[track.content].transform;
    try testing.expectEqual(ast.TransformKind{ .articulation = .staccato }, staccato.op);

    const arp = program.nodes[staccato.target].transform;
    try testing.expectEqual(ast.ArpMode.up, arp.op.arp.mode);
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

test "inline chord in a track" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\section verse =
        \\  track keys: [C4 E4 G4].whole
    );

    const section = program.nodes[program.top_level[0]].section_def;
    const track = program.nodes[section.tracks[0]].track;
    const chord = program.nodes[track.content].inline_chord;
    try testing.expectEqual(@as(usize, 3), chord.notes.len);
    try testing.expectEqual(ast.Pitch.c, chord.notes[0].pitch);
    try testing.expectEqual(ast.Pitch.e, chord.notes[1].pitch);
    try testing.expectEqual(ast.Pitch.g, chord.notes[2].pitch);
    try testing.expectEqual(ast.DurationKind.whole, chord.duration.kind);
}

test "inline chord with transforms in a track" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\section verse =
        \\  track keys: [C4 E4 G4].whole arp.bounce x2 transpose +3
    );

    const section = program.nodes[program.top_level[0]].section_def;
    const track = program.nodes[section.tracks[0]].track;

    // transpose +3 wraps arp.bounce x2 wraps inline_chord
    const transpose = program.nodes[track.content].transform;
    try testing.expectEqual(@as(i32, 3), transpose.op.transpose);

    const arp = program.nodes[transpose.target].transform;
    try testing.expectEqual(ast.ArpMode.bounce, arp.op.arp.mode);
    try testing.expectEqual(@as(u32, 2), arp.op.arp.cycles);

    const chord = program.nodes[arp.target].inline_chord;
    try testing.expectEqual(@as(usize, 3), chord.notes.len);
}

test "inline chord in a phrase with transform and repeat" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\phrase cool =
        \\  [C4 E4 G4].2whole arp.up_down x2
    );

    const phrase = program.nodes[program.top_level[0]].phrase_def;
    try testing.expectEqual(@as(usize, 1), phrase.body.len);

    // arp.up_down x2 wraps inline_chord
    const arp = program.nodes[phrase.body[0]].transform;
    try testing.expectEqual(ast.ArpMode.up_down, arp.op.arp.mode);
    try testing.expectEqual(@as(u32, 2), arp.op.arp.cycles);

    const chord = program.nodes[arp.target].inline_chord;
    try testing.expectEqual(@as(usize, 3), chord.notes.len);
    try testing.expectEqual(@as(u32, 2), chord.duration.multiplier);
    try testing.expectEqual(ast.DurationKind.whole, chord.duration.kind);
}

test "inline chord followed by a note in a track forms a sequence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(),
        \\section verse =
        \\  track keys: [B3 C4].half G4.quarter
    );

    const section = program.nodes[program.top_level[0]].section_def;
    const track = program.nodes[section.tracks[0]].track;
    const seq = program.nodes[track.content].sequence;
    try testing.expectEqual(@as(usize, 2), seq.items.len);
    _ = program.nodes[seq.items[0]].inline_chord;
    _ = program.nodes[seq.items[1]].note;
}

test "duration with numeric multiplier" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "phrase m =\n  C4.3quarter");
    const phrase = program.nodes[program.top_level[0]].phrase_def;
    const note = program.nodes[phrase.body[0]].note;
    try testing.expectEqual(@as(u32, 3), note.duration.multiplier);
    try testing.expectEqual(ast.DurationKind.quarter, note.duration.kind);
}

test "phrase element with transform and repeat" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "phrase m =\n  C4.quarter transpose +5 * 3");
    const phrase = program.nodes[program.top_level[0]].phrase_def;
    try testing.expectEqual(@as(usize, 1), phrase.body.len);

    // * 3 wraps transpose +5 wraps note
    const repeat = program.nodes[phrase.body[0]].repeat;
    try testing.expectEqual(@as(u32, 3), repeat.count);

    const transpose = program.nodes[repeat.target].transform;
    try testing.expectEqual(@as(i32, 5), transpose.op.transpose);

    _ = program.nodes[transpose.target].note;
}

test "ignores comments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), "tempo 120 -- BPM\nsong =\n  intro");

    try testing.expectEqual(@as(usize, 2), program.top_level.len);
    try testing.expectEqual(@as(u32, 120), program.nodes[program.top_level[0]].tempo.bpm);
}
