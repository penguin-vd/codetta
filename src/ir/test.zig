const std = @import("std");
const testing = std.testing;

const Parser = @import("../parser/parser.zig");
const Lower = @import("lower.zig");
const score = @import("score.zig");

fn lower(allocator: std.mem.Allocator, input: []const u8) !score.Score {
    var parser = Parser.init(allocator, input);
    const program = try parser.parseProgram();

    var lowerer = Lower.init(allocator, program);
    return lowerer.lower();
}

test "single note phrase placed at the start of the song" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\tempo 120
        \\time_signature 4/4
        \\
        \\phrase melody =
        \\  C4.quarter
        \\
        \\section verse =
        \\  track lead: melody
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(u32, 480), result.ticks_per_quarter);
    try testing.expectEqual(@as(u32, 120), result.tempo_bpm);
    try testing.expectEqual(@as(usize, 1), result.tracks.len);
    try testing.expectEqualStrings("lead", result.tracks[0].name);

    try testing.expectEqual(@as(usize, 1), result.notes.len);
    const note = result.notes[0];
    try testing.expectEqual(@as(u32, 0), note.start);
    try testing.expectEqual(@as(u32, 480), note.duration); // quarter = 1/4 bar = ticks_per_quarter in 4/4
    try testing.expectEqual(@as(u8, 60), note.pitch); // C4 -> MIDI 60
    try testing.expectEqual(@as(u16, 0), note.track);
}

test "chord reference expands into simultaneous notes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track chords: Cmaj.whole
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 3), result.notes.len);
    for (result.notes) |n| {
        try testing.expectEqual(@as(u32, 0), n.start);
        try testing.expectEqual(@as(u32, 1920), n.duration); // whole = 1 bar = 4 * 480
    }
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch);
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch);
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch);
}

test "transpose and reverse transform pitch and timing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase melody =
        \\  C4.quarter E4.quarter
        \\
        \\section verse =
        \\  track lead: melody transpose +2 reverse
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 2), result.notes.len);

    // source order C4(0) E4(480); transpose +2 -> D4(0) F#4(480);
    // reverse mirrors start within [0, length=960]: 0<->480
    try testing.expectEqual(@as(u32, 0), result.notes[0].start);
    try testing.expectEqual(@as(u8, 66), result.notes[0].pitch); // F#4

    try testing.expectEqual(@as(u32, 480), result.notes[1].start);
    try testing.expectEqual(@as(u8, 62), result.notes[1].pitch); // D4
}

test "repeat tiles a pattern and advances the cursor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase one = C4.whole
        \\
        \\section verse =
        \\  track lead: one * 2
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 2), result.notes.len);
    try testing.expectEqual(@as(u32, 0), result.notes[0].start);
    try testing.expectEqual(@as(u32, 1920), result.notes[1].start);
}

test "sections place sequentially and share track identity by name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase a = C4.whole
        \\phrase b = D4.whole
        \\
        \\section intro =
        \\  track lead: a
        \\
        \\section verse =
        \\  track lead: b
        \\
        \\song =
        \\  intro
        \\  verse
    );

    // both sections use a "lead" track - same name maps to the same index
    try testing.expectEqual(@as(usize, 1), result.tracks.len);
    try testing.expectEqualStrings("lead", result.tracks[0].name);

    try testing.expectEqual(@as(usize, 2), result.notes.len);
    try testing.expectEqual(@as(u32, 0), result.notes[0].start);
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch); // C4, intro
    try testing.expectEqual(@as(u32, 1920), result.notes[1].start); // verse starts after intro's whole bar
    try testing.expectEqual(@as(u8, 62), result.notes[1].pitch); // D4, verse
}

test "song repetition replays a section" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase a = C4.whole
        \\
        \\section verse =
        \\  track lead: a
        \\
        \\song =
        \\  verse * 2
    );

    try testing.expectEqual(@as(usize, 2), result.notes.len);
    try testing.expectEqual(@as(u32, 0), result.notes[0].start);
    try testing.expectEqual(@as(u32, 1920), result.notes[1].start);
}

test "dynamics resolve into per-note velocity, including crescendo ramps" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase melody =
        \\  C4.quarter D4.quarter E4.quarter F4.quarter
        \\
        \\  dynamic @0 p
        \\  dynamic @0.2 crescendo to f over 1 bar
        \\
        \\section verse =
        \\  track lead: melody
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 4), result.notes.len);

    // before the ramp starts (tick 0 < ramp start tick 960): flat "p"
    try testing.expectEqual(@as(u8, 48), result.notes[0].velocity);

    // at the ramp's start (tick 960): still at the "from" level (p = 48)
    try testing.expectEqual(@as(u8, 48), result.notes[2].velocity);

    // partway through the ramp: strictly between p (48) and f (96)
    try testing.expect(result.notes[3].velocity > 48 and result.notes[3].velocity < 96);
}

test "undefined chord reference is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.UndefinedReference, lower(arena.allocator(),
        \\section verse =
        \\  track chords: Cmaj.whole
        \\
        \\song =
        \\  verse
    ));
}

test "arp.up spreads chord notes low to high" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track keys: Cmaj.whole arp
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 3), result.notes.len);
    // sorted low to high: C4(60), E4(64), G4(67)
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch);
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch);
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch);
    // whole = 1920 ticks, 3 notes -> each 640 ticks
    try testing.expectEqual(@as(u32, 0), result.notes[0].start);
    try testing.expectEqual(@as(u32, 640), result.notes[1].start);
    try testing.expectEqual(@as(u32, 1280), result.notes[2].start);
    for (result.notes) |n| try testing.expectEqual(@as(u32, 640), n.duration);
}

test "arp.down spreads chord notes high to low" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track keys: Cmaj.whole arp.down
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 3), result.notes.len);
    try testing.expectEqual(@as(u8, 67), result.notes[0].pitch); // G4
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch); // E4
    try testing.expectEqual(@as(u8, 60), result.notes[2].pitch); // C4
}

test "arp.up_down goes up then down without repeating endpoints" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track keys: Cmaj.whole arp.up_down
        \\
        \\song =
        \\  verse
    );

    // 3 notes -> up_down = C E G E = 4 steps
    try testing.expectEqual(@as(usize, 4), result.notes.len);
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch); // C4
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch); // E4
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch); // G4
    try testing.expectEqual(@as(u8, 64), result.notes[3].pitch); // E4
    // 1920 / 4 = 480 ticks each
    for (result.notes) |n| try testing.expectEqual(@as(u32, 480), n.duration);
}

test "arp.bounce goes up then down with repeated endpoints" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track keys: Cmaj.whole arp.bounce
        \\
        \\song =
        \\  verse
    );

    // 3 notes -> bounce = C E G G E C = 6 steps
    try testing.expectEqual(@as(usize, 6), result.notes.len);
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch); // C4
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch); // E4
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch); // G4
    try testing.expectEqual(@as(u8, 67), result.notes[3].pitch); // G4
    try testing.expectEqual(@as(u8, 64), result.notes[4].pitch); // E4
    try testing.expectEqual(@as(u8, 60), result.notes[5].pitch); // C4
    // 1920 / 6 = 320 ticks each
    for (result.notes) |n| try testing.expectEqual(@as(u32, 320), n.duration);
}

test "arp with x2 cycles through the pattern twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track keys: Cmaj.whole arp x2
        \\
        \\song =
        \\  verse
    );

    // 3 notes * 2 cycles = 6 steps, each 1920/6 = 320 ticks
    try testing.expectEqual(@as(usize, 6), result.notes.len);
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch); // C4
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch); // E4
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch); // G4
    try testing.expectEqual(@as(u8, 60), result.notes[3].pitch); // C4 (cycle 2)
    try testing.expectEqual(@as(u8, 64), result.notes[4].pitch); // E4
    try testing.expectEqual(@as(u8, 67), result.notes[5].pitch); // G4
    for (result.notes) |n| try testing.expectEqual(@as(u32, 320), n.duration);
}

test "duration multiplier scales note length" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase melody = C4.2whole
        \\
        \\section verse =
        \\  track lead: melody
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 1), result.notes.len);
    // 2whole = 2 * 1920 = 3840 ticks
    try testing.expectEqual(@as(u32, 3840), result.notes[0].duration);
}

test "arp.bounce x2 with multi-bar duration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track keys: Cmaj.2whole arp.bounce x2
        \\
        \\song =
        \\  verse
    );

    // bounce cycle = 6 steps, x2 = 12 steps over 3840 ticks -> 320 each
    try testing.expectEqual(@as(usize, 12), result.notes.len);
    for (result.notes) |n| try testing.expectEqual(@as(u32, 320), n.duration);
    // first cycle: C E G G E C
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch);
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch);
    try testing.expectEqual(@as(u8, 67), result.notes[3].pitch);
    try testing.expectEqual(@as(u8, 60), result.notes[5].pitch);
    // second cycle repeats
    try testing.expectEqual(@as(u8, 60), result.notes[6].pitch);
    try testing.expectEqual(@as(u8, 60), result.notes[11].pitch);
}

test "inline chord in a track expands into simultaneous notes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\section verse =
        \\  track keys: [C4 E4 G4].whole
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 3), result.notes.len);
    for (result.notes) |n| {
        try testing.expectEqual(@as(u32, 0), n.start);
        try testing.expectEqual(@as(u32, 1920), n.duration);
    }
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch);
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch);
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch);
}

test "inline chord in a track followed by a note forms a sequence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\section verse =
        \\  track test: [B3 C4 E4 G4].whole G4.quarter
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 5), result.notes.len);
    // chord at tick 0
    for (result.notes[0..4]) |n| try testing.expectEqual(@as(u32, 0), n.start);
    // G4.quarter after the whole bar
    try testing.expectEqual(@as(u32, 1920), result.notes[4].start);
    try testing.expectEqual(@as(u8, 67), result.notes[4].pitch);
}

test "inline chord in a phrase with arp transform" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase cool =
        \\  [C4 E4 G4].2whole arp.up_down x2
        \\
        \\section verse =
        \\  track keys: cool
        \\
        \\song =
        \\  verse
    );

    // up_down on 3 notes = 4 steps per cycle, x2 = 8 steps over 3840 ticks
    try testing.expectEqual(@as(usize, 8), result.notes.len);
    try testing.expectEqual(@as(u8, 60), result.notes[0].pitch); // C4
    try testing.expectEqual(@as(u8, 64), result.notes[1].pitch); // E4
    try testing.expectEqual(@as(u8, 67), result.notes[2].pitch); // G4
    try testing.expectEqual(@as(u8, 64), result.notes[3].pitch); // E4 (down)
    // cycle 2
    try testing.expectEqual(@as(u8, 60), result.notes[4].pitch);
    for (result.notes) |n| try testing.expectEqual(@as(u32, 480), n.duration); // 3840/8
}

test "full example with inline chords, arp in phrase, and mixed tracks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\tempo 100
        \\time_signature 4/4
        \\
        \\chord Cmaj = [B3 C4 E4 G3]
        \\chord Dmin = [F4 A3 C4 D4]
        \\
        \\phrase bassC =
        \\  C2.quarter C3.quarter C2.quarter C3.quarter
        \\phrase bassD =
        \\  D2.quarter D3.quarter D2.quarter D3.quarter
        \\
        \\phrase cool =
        \\    Cmaj.2whole arp.up_down x2
        \\
        \\section loop =
        \\  track chords: cool
        \\  track bass:   bassC bassC bassD bassD
        \\  track test: [B3 C4 E4 G4].whole G4.quarter
        \\
        \\song =
        \\  loop * 4
    );

    try testing.expectEqual(@as(u32, 100), result.tempo_bpm);
    try testing.expectEqual(@as(usize, 3), result.tracks.len);
    // should have notes from all three tracks across 4 repeats
    try testing.expect(result.notes.len > 0);
}

test "dynamics swell with arp produces crescendo then diminuendo" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\tempo 100
        \\time_signature 4/4
        \\
        \\chord Cmaj = [B3 C4 E4 G3]
        \\chord Dmin = [F4 A3 C4 D4]
        \\
        \\phrase chords =
        \\  Cmaj.whole arp.up_down x2
        \\  Dmin.whole arp.up_down x2
        \\
        \\  dynamic @0 pp
        \\  dynamic @0 crescendo to fff over 1 bar
        \\  dynamic @1 diminuendo to ppp over 1 bar
        \\
        \\section loop =
        \\  track chords: chords
        \\
        \\song =
        \\  loop
    );

    // up_down on 4 notes = 6 steps per cycle, x2 = 12 notes per chord, 24 total
    try testing.expectEqual(@as(usize, 24), result.notes.len);

    // Sort by start tick for sequential analysis
    const sorted = try arena.allocator().dupe(score.NoteEvent, result.notes);
    std.mem.sort(score.NoteEvent, sorted, {}, struct {
        fn f(_: void, a: score.NoteEvent, b: score.NoteEvent) bool {
            return if (a.start != b.start) a.start < b.start else a.pitch < b.pitch;
        }
    }.f);

    // First note (tick 0) should be pp (32)
    try testing.expectEqual(@as(u8, 32), sorted[0].velocity);

    // Bar 1 (ticks 0–1919): notes should crescendo toward fff (127)
    // Each arp step = 1920/12 = 160 ticks
    // Verify velocity increases across bar 1
    var prev_vel: u8 = 0;
    for (sorted[0..12]) |n| {
        try testing.expect(n.start < 1920); // all in bar 1
        try testing.expect(n.velocity >= prev_vel);
        prev_vel = n.velocity;
    }

    // Bar 2 (ticks 1920–3839): notes should diminuendo toward ppp (16)
    // First note of bar 2 should be near fff
    try testing.expect(sorted[12].velocity > 100);
    // Last note of bar 2 should be much quieter
    try testing.expect(sorted[23].velocity < sorted[12].velocity);
    // Verify velocity decreases across bar 2
    prev_vel = 127;
    for (sorted[12..24]) |n| {
        try testing.expect(n.start >= 1920); // all in bar 2
        try testing.expect(n.velocity <= prev_vel);
        prev_vel = n.velocity;
    }
}

test "voice cursor reset enables counterpoint" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase melody =
        \\  E4.whole E4.quarter
        \\  @0 C4.quarter C5.whole
        \\
        \\section verse =
        \\  track lead: melody
        \\
        \\song =
        \\  verse
    );

    // Voice 1: E4.whole at 0, E4.quarter at 1920
    // Voice 2: @0 resets cursor, C4.quarter at 0, C5.whole at 480
    try testing.expectEqual(@as(usize, 4), result.notes.len);

    const sorted = try arena.allocator().dupe(score.NoteEvent, result.notes);
    std.mem.sort(score.NoteEvent, sorted, {}, struct {
        fn f(_: void, a: score.NoteEvent, b: score.NoteEvent) bool {
            return if (a.start != b.start) a.start < b.start else a.pitch < b.pitch;
        }
    }.f);

    // tick 0: C4 (quarter) and E4 (whole) overlap
    try testing.expectEqual(@as(u32, 0), sorted[0].start);
    try testing.expectEqual(@as(u8, 60), sorted[0].pitch); // C4
    try testing.expectEqual(@as(u32, 480), sorted[0].duration); // quarter

    try testing.expectEqual(@as(u32, 0), sorted[1].start);
    try testing.expectEqual(@as(u8, 64), sorted[1].pitch); // E4
    try testing.expectEqual(@as(u32, 1920), sorted[1].duration); // whole

    // tick 480: C5 (whole) from voice 2
    try testing.expectEqual(@as(u32, 480), sorted[2].start);
    try testing.expectEqual(@as(u8, 72), sorted[2].pitch); // C5

    // tick 1920: E4 (quarter) from voice 1
    try testing.expectEqual(@as(u32, 1920), sorted[3].start);
    try testing.expectEqual(@as(u8, 64), sorted[3].pitch); // E4
}

test "staccato halves note duration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase melody = C4.quarter
        \\
        \\section verse =
        \\  track lead: melody staccato
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 1), result.notes.len);
    try testing.expectEqual(@as(u32, 240), result.notes[0].duration); // 480 / 2
}

test "legato extends note duration by 10%" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\phrase melody = C4.quarter
        \\
        \\section verse =
        \\  track lead: melody legato
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 1), result.notes.len);
    // 480 + 480/10 = 480 + 48 = 528
    try testing.expectEqual(@as(u32, 528), result.notes[0].duration);
}

test "staccato with arp shortens arpeggiated notes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try lower(arena.allocator(),
        \\chord Cmaj = [C4 E4 G4]
        \\
        \\section verse =
        \\  track keys: Cmaj.whole arp.up staccato
        \\
        \\song =
        \\  verse
    );

    try testing.expectEqual(@as(usize, 3), result.notes.len);
    // arp splits whole (1920) into 3 notes of 640 ticks; staccato halves to 320
    for (result.notes) |n| try testing.expectEqual(@as(u32, 320), n.duration);
}

test "missing song declaration is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.MissingSong, lower(arena.allocator(), "tempo 120"));
}
