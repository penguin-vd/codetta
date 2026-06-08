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

test "missing song declaration is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.MissingSong, lower(arena.allocator(), "tempo 120"));
}
