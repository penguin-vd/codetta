const std = @import("std");
const Allocator = std.mem.Allocator;

const ir = @import("../ir/score.zig");
const Score = ir.Score;
const TrackInfo = ir.TrackInfo;

pub fn write(allocator: Allocator, s: Score) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;

    try bytes.appendSlice(allocator, "MThd");
    try appendU32(&bytes, allocator, 6);
    try appendU16(&bytes, allocator, 1); // format 1: multiple simultaneous tracks
    try appendU16(&bytes, allocator, @intCast(1 + s.tracks.len));
    try appendU16(&bytes, allocator, @intCast(s.ticks_per_quarter));

    try appendChunk(&bytes, allocator, try buildMetaTrack(allocator, s));
    for (s.tracks, 0..) |track, i| {
        try appendChunk(&bytes, allocator, try buildInstrumentTrack(allocator, s, track, @intCast(i)));
    }

    return bytes.toOwnedSlice(allocator);
}

fn appendChunk(bytes: *std.ArrayList(u8), allocator: Allocator, data: []const u8) !void {
    try bytes.appendSlice(allocator, "MTrk");
    try appendU32(bytes, allocator, @intCast(data.len));
    try bytes.appendSlice(allocator, data);
}

fn buildMetaTrack(allocator: Allocator, s: Score) ![]u8 {
    var data: std.ArrayList(u8) = .empty;

    const micros_per_quarter: u32 = 60_000_000 / s.tempo_bpm;
    try appendVarLen(&data, allocator, 0);
    try data.appendSlice(allocator, &.{
        0xFF, 0x51, 0x03,
        @intCast((micros_per_quarter >> 16) & 0xFF),
        @intCast((micros_per_quarter >> 8) & 0xFF),
        @intCast(micros_per_quarter & 0xFF),
    });

    try appendVarLen(&data, allocator, 0);
    try data.appendSlice(allocator, &.{
        0xFF, 0x58, 0x04,
        @intCast(s.time_signature.numerator),
        log2OfPowerOfTwo(s.time_signature.denominator),
        24,
        8,
    });

    try appendEndOfTrack(&data, allocator);
    return data.toOwnedSlice(allocator);
}

const NoteEdge = struct {
    tick: u32,
    status: u8,
    pitch: u8,
    velocity: u8,
};

fn buildInstrumentTrack(allocator: Allocator, s: Score, track: TrackInfo, track_id: u16) ![]u8 {
    const channel: u8 = @intCast(track_id % 16);

    var edges: std.ArrayList(NoteEdge) = .empty;
    for (s.notes) |n| {
        if (n.track != track_id) continue;
        try edges.append(allocator, .{ .tick = n.start, .status = 0x90 | channel, .pitch = n.pitch, .velocity = n.velocity });
        try edges.append(allocator, .{ .tick = n.start + n.duration, .status = 0x80 | channel, .pitch = n.pitch, .velocity = 0 });
    }
    std.mem.sort(NoteEdge, edges.items, {}, lessByTickThenOff);

    var data: std.ArrayList(u8) = .empty;

    try appendVarLen(&data, allocator, 0);
    try data.appendSlice(allocator, &.{ 0xFF, 0x03, @intCast(track.name.len) });
    try data.appendSlice(allocator, track.name);

    var prev_tick: u32 = 0;
    for (edges.items) |edge| {
        try appendVarLen(&data, allocator, edge.tick - prev_tick);
        try data.appendSlice(allocator, &.{ edge.status, edge.pitch, edge.velocity });
        prev_tick = edge.tick;
    }

    try appendEndOfTrack(&data, allocator);
    return data.toOwnedSlice(allocator);
}

fn lessByTickThenOff(_: void, a: NoteEdge, b: NoteEdge) bool {
    if (a.tick != b.tick) return a.tick < b.tick;
    return (a.status & 0xF0) < (b.status & 0xF0);
}

fn appendEndOfTrack(data: *std.ArrayList(u8), allocator: Allocator) !void {
    try appendVarLen(data, allocator, 0);
    try data.appendSlice(allocator, &.{ 0xFF, 0x2F, 0x00 });
}

fn appendU16(bytes: *std.ArrayList(u8), allocator: Allocator, value: u16) !void {
    try bytes.appendSlice(allocator, &.{ @intCast(value >> 8), @intCast(value & 0xFF) });
}

fn appendU32(bytes: *std.ArrayList(u8), allocator: Allocator, value: u32) !void {
    try bytes.appendSlice(allocator, &.{
        @intCast((value >> 24) & 0xFF),
        @intCast((value >> 16) & 0xFF),
        @intCast((value >> 8) & 0xFF),
        @intCast(value & 0xFF),
    });
}

fn appendVarLen(bytes: *std.ArrayList(u8), allocator: Allocator, value: u32) !void {
    var groups: [5]u8 = undefined;
    var count: usize = 1;
    var v = value;

    groups[0] = @intCast(v & 0x7F);
    v >>= 7;
    while (v > 0) : (v >>= 7) {
        groups[count] = @intCast(v & 0x7F);
        count += 1;
    }

    var i = count;
    while (i > 0) {
        i -= 1;
        const continuation: u8 = if (i > 0) 0x80 else 0;
        try bytes.append(allocator, groups[i] | continuation);
    }
}

fn log2OfPowerOfTwo(value: u32) u8 {
    var n = value;
    var exponent: u8 = 0;
    while (n > 1) : (n >>= 1) exponent += 1;
    return exponent;
}
