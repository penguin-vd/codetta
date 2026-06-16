const std = @import("std");
const testing = std.testing;

const Diag = @import("diag.zig");

fn collect(arena: *std.heap.ArenaAllocator, source: []const u8) ![]const Diag.Diagnostic {
    return Diag.collect(arena.allocator(), source);
}

fn find(diags: []const Diag.Diagnostic, needle: []const u8) ?Diag.Diagnostic {
    for (diags) |d| {
        if (std.mem.indexOf(u8, d.message, needle) != null) return d;
    }
    return null;
}

test "a complete score produces no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const diags = try collect(&arena,
        \\tempo 120
        \\time_signature 4/4
        \\phrase m =
        \\  C4.quarter
        \\section s =
        \\  track a: m
        \\song =
        \\  s
    );
    try testing.expectEqual(@as(usize, 0), diags.len);
}

test "missing settings and song are flagged" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const diags = try collect(&arena, "phrase m =\n  C4.quarter");

    const tempo = find(diags, "tempo").?;
    try testing.expectEqual(Diag.Severity.warning, tempo.severity);
    try testing.expect(find(diags, "time_signature") != null);

    const song = find(diags, "song").?;
    try testing.expectEqual(Diag.Severity.err, song.severity);
}

test "undefined references point at the reference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const diags = try collect(&arena,
        \\tempo 120
        \\time_signature 4/4
        \\section s =
        \\  track a: ghost
        \\song =
        \\  s
    );

    const ref = find(diags, "undefined phrase").?;
    try testing.expectEqual(Diag.Severity.err, ref.severity);
    try testing.expectEqual(@as(u32, 4), ref.line);
    try testing.expectEqual(@as(u32, 12), ref.column);
}

test "definitions that are never referenced are warned about" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const diags = try collect(&arena,
        \\tempo 120
        \\time_signature 4/4
        \\chord Used = [C4 E4 G4]
        \\chord Lonely = [D4 F4 A4]
        \\phrase m =
        \\  Used.quarter
        \\section s =
        \\  track a: m
        \\song =
        \\  s
    );

    const lonely = find(diags, "Lonely").?;
    try testing.expectEqual(Diag.Severity.warning, lonely.severity);
    try testing.expectEqual(@as(u32, 4), lonely.line);
    try testing.expect(find(diags, "Used` is never used") == null);
}

test "syntax errors recover so several are reported at once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const diags = try collect(&arena, "tempo ??\nchord X = [C4 ???]\nsong =\n  s");

    var errors: usize = 0;
    var first_line: u32 = 0;
    var second_line: u32 = 0;
    for (diags) |d| {
        if (d.severity != .err) continue;
        errors += 1;
        if (errors == 1) first_line = d.line else if (errors == 2) second_line = d.line;
    }
    try testing.expect(errors >= 2);
    try testing.expectEqual(@as(u32, 1), first_line);
    try testing.expectEqual(@as(u32, 2), second_line);
}
