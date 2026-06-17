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

// The wire shapes. Field names and order are the JSON contract, so std.json
// serializes these structs straight into the document above.
const Note = struct { midi: u8, ticks: u32, durationTicks: u32, velocity: f64 };
const Track = struct { name: []const u8, notes: []const Note };
const Header = struct { tempo: u32, ppq: u32, timeSignature: [2]u32 };
const Document = struct { header: Header, tracks: []const Track };

pub fn write(allocator: Allocator, s: Score) ![]u8 {
    const tracks = try allocator.alloc(Track, s.tracks.len);
    for (s.tracks, 0..) |track, track_id| {
        var notes: std.ArrayList(Note) = .empty;
        for (s.notes) |n| {
            if (n.track != track_id) continue;
            try notes.append(allocator, .{
                .midi = n.pitch,
                .ticks = n.start,
                .durationTicks = n.duration,
                .velocity = @as(f64, @floatFromInt(n.velocity)) / 127.0,
            });
        }
        tracks[track_id] = .{ .name = track.name, .notes = try notes.toOwnedSlice(allocator) };
    }

    const doc: Document = .{
        .header = .{
            .tempo = s.tempo_bpm,
            .ppq = s.ticks_per_quarter,
            .timeSignature = .{ s.time_signature.numerator, s.time_signature.denominator },
        },
        .tracks = tracks,
    };

    return std.json.Stringify.valueAlloc(allocator, doc, .{});
}
