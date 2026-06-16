const std = @import("std");
const Allocator = std.mem.Allocator;

const ir = @import("../ir/score.zig");
const Score = ir.Score;

// Serializes a lowered `Score` into JSON shaped like @tonejs/midi, the
// de-facto interchange format for browser playback. The webapp feeds each
// track straight to a Tone.js instrument:
//
//   { "header": { "tempo": 120, "ppq": 480, "timeSignature": [4, 4] },
//     "tracks": [ { "name": "melody",
//                   "notes": [ { "midi": 60, "ticks": 0,
//                                "durationTicks": 240, "velocity": 0.7 } ] } ] }
//
// Notes carry absolute `ticks`; the client converts to seconds using
// `ppq` and `tempo`, so a varying tempo stays a client-side concern.

pub fn write(allocator: Allocator, s: Score) ![]u8 {
    var out: std.ArrayList(u8) = .empty;

    try print(&out, allocator,
        \\{{"header":{{"tempo":{d},"ppq":{d},"timeSignature":[{d},{d}]}},"tracks":[
    , .{ s.tempo_bpm, s.ticks_per_quarter, s.time_signature.numerator, s.time_signature.denominator });

    for (s.tracks, 0..) |track, track_id| {
        if (track_id != 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, "{\"name\":");
        try appendJsonString(&out, allocator, track.name);
        try out.appendSlice(allocator, ",\"notes\":[");

        var first = true;
        for (s.notes) |n| {
            if (n.track != track_id) continue;
            if (!first) try out.append(allocator, ',');
            first = false;
            try print(&out, allocator,
                \\{{"midi":{d},"ticks":{d},"durationTicks":{d},"velocity":{d:.3}}}
            , .{ n.pitch, n.start, n.duration, @as(f64, @floatFromInt(n.velocity)) / 127.0 });
        }
        try out.appendSlice(allocator, "]}");
    }

    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn print(out: *std.ArrayList(u8), allocator: Allocator, comptime fmt: []const u8, args: anytype) !void {
    const chunk = try std.fmt.allocPrint(allocator, fmt, args);
    try out.appendSlice(allocator, chunk);
}

fn appendJsonString(out: *std.ArrayList(u8), allocator: Allocator, value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |c| switch (c) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        else => try out.append(allocator, c),
    };
    try out.append(allocator, '"');
}
