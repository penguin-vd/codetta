const std = @import("std");
const testing = std.testing;

const Midi = @import("midi.zig");
const ir = @import("../ir/score.zig");
const Score = ir.Score;

fn singleTrackScore() Score {
    return .{
        .ticks_per_quarter = 480,
        .tempo_bpm = 120,
        .time_signature = .{ .numerator = 4, .denominator = 4 },
        .tracks = &.{.{ .name = "lead" }},
        .notes = &.{
            .{ .start = 0, .duration = 480, .pitch = 60, .velocity = 100, .track = 0 },
            .{ .start = 480, .duration = 480, .pitch = 64, .velocity = 100, .track = 0 },
        },
    };
}

fn readU16(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) | (@as(u32, bytes[2]) << 8) | bytes[3];
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, pos, needle)) |found| {
        count += 1;
        pos = found + 1;
    }
    return count;
}

test "MThd header reflects format, track count and resolution" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const bytes = try Midi.write(arena.allocator(), singleTrackScore());

    try testing.expectEqualStrings("MThd", bytes[0..4]);
    try testing.expectEqual(@as(u32, 6), readU32(bytes[4..8]));
    try testing.expectEqual(@as(u16, 1), readU16(bytes[8..10])); // format 1
    try testing.expectEqual(@as(u16, 2), readU16(bytes[10..12])); // meta track + 1 instrument
    try testing.expectEqual(@as(u16, 480), readU16(bytes[12..14]));
}

test "emits one MTrk chunk per instrument plus a meta track" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const bytes = try Midi.write(arena.allocator(), singleTrackScore());
    try testing.expectEqual(@as(usize, 2), countOccurrences(bytes, "MTrk"));
}

test "encodes tempo and time signature as meta events" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const bytes = try Midi.write(arena.allocator(), singleTrackScore());

    // 120 BPM -> 60_000_000 / 120 = 500_000 us/quarter = 0x07A120
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20 }) != null);
    // 4/4 -> numerator 4, denominator 2^2
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0xFF, 0x58, 0x04, 4, 2 }) != null);
}

test "writes track names as meta events" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const bytes = try Midi.write(arena.allocator(), singleTrackScore());
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0xFF, 0x03, 4, 'l', 'e', 'a', 'd' }) != null);
}

test "encodes notes as note-on/note-off pairs and chains adjacent notes with zero delta" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const bytes = try Midi.write(arena.allocator(), singleTrackScore());

    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x90, 60, 100 }) != null); // C4 note-on, channel 0
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x80, 60, 0 }) != null); // C4 note-off

    // E4 starts exactly where C4 ends - the off/on pair is adjacent with delta 0
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x80, 60, 0, 0x00, 0x90, 64, 100 }) != null);
}

test "encodes large delta times as multi-byte variable-length quantities" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const s = Score{
        .ticks_per_quarter = 480,
        .tempo_bpm = 120,
        .time_signature = .{ .numerator = 4, .denominator = 4 },
        .tracks = &.{.{ .name = "lead" }},
        .notes = &.{
            .{ .start = 16384, .duration = 480, .pitch = 60, .velocity = 100, .track = 0 },
        },
    };

    const bytes = try Midi.write(arena.allocator(), s);

    // delta 16384 -> VLQ 0x81 0x80 0x00, immediately followed by the note-on
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x81, 0x80, 0x00, 0x90, 60, 100 }) != null);
}

test "notes are routed to their track's own channel" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const s = Score{
        .ticks_per_quarter = 480,
        .tempo_bpm = 120,
        .time_signature = .{ .numerator = 4, .denominator = 4 },
        .tracks = &.{ .{ .name = "lead" }, .{ .name = "bass" } },
        .notes = &.{
            .{ .start = 0, .duration = 480, .pitch = 72, .velocity = 100, .track = 0 },
            .{ .start = 0, .duration = 480, .pitch = 36, .velocity = 90, .track = 1 },
        },
    };

    const bytes = try Midi.write(arena.allocator(), s);

    try testing.expectEqual(@as(usize, 3), countOccurrences(bytes, "MTrk"));
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x90, 72, 100 }) != null); // channel 0
    try testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x91, 36, 90 }) != null); // channel 1
}
