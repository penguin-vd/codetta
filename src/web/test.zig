const std = @import("std");
const testing = std.testing;

const Web = @import("web.zig");
const ir = @import("../ir/score.zig");
const Score = ir.Score;

fn sampleScore() Score {
    return .{
        .ticks_per_quarter = 480,
        .tempo_bpm = 120,
        .time_signature = .{ .numerator = 3, .denominator = 4 },
        .tracks = &.{ .{ .name = "lead" }, .{ .name = "bass" } },
        .notes = &.{
            .{ .start = 0, .duration = 480, .pitch = 60, .velocity = 127, .track = 0 },
            .{ .start = 480, .duration = 240, .pitch = 64, .velocity = 64, .track = 0 },
            .{ .start = 0, .duration = 960, .pitch = 36, .velocity = 100, .track = 1 },
        },
    };
}

test "header carries tempo, ppq and time signature" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const json = try Web.write(arena.allocator(), sampleScore());

    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), json, .{});
    const header = parsed.value.object.get("header").?.object;
    try testing.expectEqual(@as(i64, 120), header.get("tempo").?.integer);
    try testing.expectEqual(@as(i64, 480), header.get("ppq").?.integer);

    const sig = header.get("timeSignature").?.array;
    try testing.expectEqual(@as(i64, 3), sig.items[0].integer);
    try testing.expectEqual(@as(i64, 4), sig.items[1].integer);
}

test "notes are grouped by track with normalized velocity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const json = try Web.write(arena.allocator(), sampleScore());

    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), json, .{});
    const tracks = parsed.value.object.get("tracks").?.array;
    try testing.expectEqual(@as(usize, 2), tracks.items.len);

    const lead = tracks.items[0].object;
    try testing.expectEqualStrings("lead", lead.get("name").?.string);
    const lead_notes = lead.get("notes").?.array;
    try testing.expectEqual(@as(usize, 2), lead_notes.items.len);

    const first = lead_notes.items[0].object;
    try testing.expectEqual(@as(i64, 60), first.get("midi").?.integer);
    try testing.expectEqual(@as(i64, 0), first.get("ticks").?.integer);
    try testing.expectEqual(@as(i64, 480), first.get("durationTicks").?.integer);
    try testing.expectApproxEqAbs(@as(f64, 1.0), first.get("velocity").?.float, 0.001);

    const bass_notes = tracks.items[1].object.get("notes").?.array;
    try testing.expectEqual(@as(usize, 1), bass_notes.items.len);
}
