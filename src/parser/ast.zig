const std = @import("std");

pub const NodeIndex = u32;

pub const Pitch = enum { c, d, e, f, g, a, b };
pub const Accidental = enum { natural, sharp, flat };
pub const DurationKind = enum { whole, half, quarter, eighth, sixteenth };
pub const Duration = struct { kind: DurationKind, dotted: bool };
pub const DynamicLevel = enum { ppp, pp, p, mp, mf, f, ff, fff };
pub const DynamicShapeKind = enum { crescendo, diminuendo };
pub const Position = struct { bar: u32, beat: u32 };
pub const Pitched = struct { pitch: Pitch, accidental: Accidental, octave: u8 };

pub const TransformKind = union(enum) {
    transpose: i32, // +5 / -5
    reverse,
    augment: u32, // xN
    diminish: u32, // xN
    humanize: f32, // 0.0-1.0
};

pub const Node = union(enum) {
    // global settings
    tempo: struct { bpm: u32 },
    time_signature: struct { numerator: u32, denominator: u32 },

    // top-level definitions
    chord_def: struct { name: []const u8, notes: []const Pitched },
    phrase_def: struct { name: []const u8, body: []const NodeIndex }, // body -> phrase elements
    section_def: struct { name: []const u8, tracks: []const NodeIndex }, // tracks -> .track
    song_def: struct { items: []const NodeIndex }, // items -> identifier/repeat

    // phrase elements
    note: struct { pitched: Pitched, duration: Duration },
    rest: struct { duration: Duration },
    chord_ref: struct { name: []const u8, duration: Duration }, // Cmaj.half
    positioned: struct { position: Position, target: NodeIndex }, // @1.1 C3.whole
    dynamic_level: struct { position: Position, level: DynamicLevel }, // dynamic @0 p
    dynamic_shape: struct { // dynamic @0.3 crescendo to f over 1 bar
        position: Position,
        shape: DynamicShapeKind,
        target: DynamicLevel,
        bars: u32,
    },

    // references & combinators (phrases, tracks, song all reuse these)
    identifier: struct { name: []const u8 },
    sequence: struct { items: []const NodeIndex }, // A B C, juxtaposed in time
    repeat: struct { target: NodeIndex, count: u32 }, // <node> * N
    transform: struct { target: NodeIndex, op: TransformKind }, // <node> transpose +5

    // section structure
    track: struct { name: []const u8, content: NodeIndex },
};

pub const Program = struct {
    nodes: []const Node,
    top_level: []const NodeIndex,
};
