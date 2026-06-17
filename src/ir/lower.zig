const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("../parser/ast.zig");
const Node = ast.Node;
const NodeIndex = ast.NodeIndex;
const Program = ast.Program;

const score = @import("score.zig");
const Score = score.Score;
const NoteEvent = score.NoteEvent;
const TrackInfo = score.TrackInfo;

pub const LowerError = error{ UndefinedReference, MissingSong, OutOfMemory };

const default_velocity: u8 = 80; // mf, used wherever no `dynamic` is in effect yet

const RelativeNote = struct {
    start: u32,
    duration: u32,
    pitch: u8,
    velocity: u8,
};

const Pattern = struct {
    notes: []const RelativeNote,
    length: u32, // total ticks spanned, needed for sequencing/repeat/reverse
};

const DynamicPoint = struct {
    tick: u32,
    velocity: u8,
    ramp_to: ?struct { velocity: u8, end_tick: u32 } = null,
};

allocator: Allocator,
program: Program,

ticks_per_quarter: u32 = 480,
tempo_bpm: u32 = 120,
numerator: u32 = 4,
denominator: u32 = 4,
song_index: ?NodeIndex = null,

chord_defs: std.StringHashMapUnmanaged([]const ast.Pitched) = .empty,
phrase_defs: std.StringHashMapUnmanaged(NodeIndex) = .empty,
section_defs: std.StringHashMapUnmanaged(NodeIndex) = .empty,
phrase_patterns: std.StringHashMapUnmanaged(Pattern) = .empty,

pub fn init(allocator: Allocator, program: Program) Self {
    return .{ .allocator = allocator, .program = program };
}

pub fn lower(self: *Self) LowerError!Score {
    try self.collectDefinitions();

    const song_index = self.song_index orelse return error.MissingSong;
    const song = self.program.nodes[song_index].song_def;

    var tracks: std.ArrayList(TrackInfo) = .empty;
    var track_indices: std.StringHashMapUnmanaged(u16) = .empty;
    var notes: std.ArrayList(NoteEvent) = .empty;

    var cursor: u32 = 0;
    for (song.items) |item_index| {
        cursor = try self.placeSongItem(item_index, cursor, &tracks, &track_indices, &notes);
    }

    const items = try notes.toOwnedSlice(self.allocator);
    std.mem.sort(NoteEvent, items, {}, lessByStart);

    return .{
        .ticks_per_quarter = self.ticks_per_quarter,
        .tempo_bpm = self.tempo_bpm,
        .time_signature = .{ .numerator = self.numerator, .denominator = self.denominator },
        .tracks = try tracks.toOwnedSlice(self.allocator),
        .notes = items,
    };
}

fn collectDefinitions(self: *Self) !void {
    for (self.program.top_level) |index| {
        switch (self.program.nodes[index]) {
            .tempo => |t| self.tempo_bpm = t.bpm,
            .time_signature => |ts| {
                self.numerator = ts.numerator;
                self.denominator = ts.denominator;
            },
            .chord_def => |c| try self.chord_defs.put(self.allocator, c.name, c.notes),
            .phrase_def => |p| try self.phrase_defs.put(self.allocator, p.name, index),
            .section_def => |s| try self.section_defs.put(self.allocator, s.name, index),
            .song_def => self.song_index = index,
            else => unreachable,
        }
    }
}

fn placeSongItem(
    self: *Self,
    index: NodeIndex,
    start: u32,
    tracks: *std.ArrayList(TrackInfo),
    track_indices: *std.StringHashMapUnmanaged(u16),
    notes: *std.ArrayList(NoteEvent),
) LowerError!u32 {
    return switch (self.program.nodes[index]) {
        .identifier => |n| self.placeSection(n.name, start, tracks, track_indices, notes),
        .repeat => |r| blk: {
            var cursor = start;
            var i: u32 = 0;
            while (i < r.count) : (i += 1) {
                cursor = try self.placeSongItem(r.target, cursor, tracks, track_indices, notes);
            }
            break :blk cursor;
        },
        else => unreachable,
    };
}

fn placeSection(
    self: *Self,
    name: []const u8,
    start: u32,
    tracks: *std.ArrayList(TrackInfo),
    track_indices: *std.StringHashMapUnmanaged(u16),
    notes: *std.ArrayList(NoteEvent),
) LowerError!u32 {
    const def_index = self.section_defs.get(name) orelse return error.UndefinedReference;
    const section = self.program.nodes[def_index].section_def;

    var section_length: u32 = 0;
    for (section.tracks) |track_index| {
        const track = self.program.nodes[track_index].track;
        const track_id = try self.trackIndexFor(track.name, tracks, track_indices);
        const pattern = try self.resolvePattern(track.content);

        for (pattern.notes) |n| {
            try notes.append(self.allocator, .{
                .start = start + n.start,
                .duration = n.duration,
                .pitch = n.pitch,
                .velocity = n.velocity,
                .track = track_id,
            });
        }
        section_length = @max(section_length, pattern.length);
    }

    return start + section_length;
}

fn trackIndexFor(
    self: *Self,
    name: []const u8,
    tracks: *std.ArrayList(TrackInfo),
    track_indices: *std.StringHashMapUnmanaged(u16),
) !u16 {
    if (track_indices.get(name)) |id| return id;

    const id: u16 = @intCast(tracks.items.len);
    try tracks.append(self.allocator, .{ .name = name });
    try track_indices.put(self.allocator, name, id);
    return id;
}

fn resolvePattern(self: *Self, index: NodeIndex) LowerError!Pattern {
    return switch (self.program.nodes[index]) {
        .note => |n| self.singleNote(n.pitched, n.duration),
        .rest => |n| .{ .notes = &.{}, .length = self.ticksFor(n.duration) },
        .chord_ref => |n| self.resolveChordRef(n.name, n.duration),
        .inline_chord => |n| self.resolveInlineChord(n.notes, n.duration),
        .identifier => |n| self.resolvePhrasePattern(n.name),
        .sequence => |n| self.resolveSequence(n.items),
        .repeat => |n| self.resolveRepeat(n.target, n.count),
        .transform => |n| self.resolveTransform(n.target, n.op),
        else => unreachable,
    };
}

fn singleNote(self: *Self, pitched: ast.Pitched, duration: ast.Duration) !Pattern {
    const ticks = self.ticksFor(duration);
    const notes = try self.allocator.alloc(RelativeNote, 1);
    notes[0] = .{ .start = 0, .duration = ticks, .pitch = midiPitch(pitched), .velocity = default_velocity };
    return .{ .notes = notes, .length = ticks };
}

fn resolveChordRef(self: *Self, name: []const u8, duration: ast.Duration) !Pattern {
    const pitches = self.chord_defs.get(name) orelse return error.UndefinedReference;
    const ticks = self.ticksFor(duration);

    const notes = try self.allocator.alloc(RelativeNote, pitches.len);
    for (pitches, notes) |p, *n| {
        n.* = .{ .start = 0, .duration = ticks, .pitch = midiPitch(p), .velocity = default_velocity };
    }
    return .{ .notes = notes, .length = ticks };
}

fn resolveInlineChord(self: *Self, pitches: []const ast.Pitched, duration: ast.Duration) !Pattern {
    const ticks = self.ticksFor(duration);
    const notes = try self.allocator.alloc(RelativeNote, pitches.len);
    for (pitches, notes) |p, *n| {
        n.* = .{ .start = 0, .duration = ticks, .pitch = midiPitch(p), .velocity = default_velocity };
    }
    return .{ .notes = notes, .length = ticks };
}

fn resolveSequence(self: *Self, items: []const NodeIndex) !Pattern {
    var notes: std.ArrayList(RelativeNote) = .empty;
    var cursor: u32 = 0;

    for (items) |item_index| {
        const sub = try self.resolvePattern(item_index);
        try appendShifted(self.allocator, &notes, sub, cursor);
        cursor += sub.length;
    }

    return .{ .notes = try notes.toOwnedSlice(self.allocator), .length = cursor };
}

fn resolveRepeat(self: *Self, target: NodeIndex, count: u32) !Pattern {
    const sub = try self.resolvePattern(target);

    var notes: std.ArrayList(RelativeNote) = .empty;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        try appendShifted(self.allocator, &notes, sub, i * sub.length);
    }

    return .{ .notes = try notes.toOwnedSlice(self.allocator), .length = sub.length * count };
}

fn resolveTransform(self: *Self, target: NodeIndex, op: ast.TransformKind) !Pattern {
    const sub = try self.resolvePattern(target);
    const notes = try self.allocator.dupe(RelativeNote, sub.notes);

    switch (op) {
        .transpose => |amount| for (notes) |*n| {
            n.pitch = clampPitch(@as(i32, n.pitch) + amount);
        },
        .reverse => for (notes) |*n| {
            n.start = sub.length - (n.start + n.duration);
        },
        .augment => |factor| for (notes) |*n| {
            n.start *= factor;
            n.duration *= factor;
        },
        .diminish => |factor| {
            const safe_factor = @max(factor, 1);
            for (notes) |*n| {
                n.start /= safe_factor;
                n.duration /= safe_factor;
            }
        },
        .arp => |a| {
            if (notes.len > 0) {
                std.mem.sort(RelativeNote, notes, {}, lessByPitch);
                const one_cycle = try arpSequence(self.allocator, notes.len, a.mode);
                const total_steps = one_cycle.len * a.cycles;
                const step = sub.length / @as(u32, @intCast(total_steps));
                const out = try self.allocator.alloc(RelativeNote, total_steps);
                for (0..total_steps) |i| {
                    const src_i = one_cycle[i % one_cycle.len];
                    out[i] = .{
                        .start = @as(u32, @intCast(i)) * step,
                        .duration = step,
                        .pitch = notes[src_i].pitch,
                        .velocity = notes[src_i].velocity,
                    };
                }
                return .{ .notes = out, .length = sub.length };
            }
        },
    }

    const length = switch (op) {
        .augment => |factor| sub.length * factor,
        .diminish => |factor| sub.length / @max(factor, 1),
        else => sub.length,
    };

    return .{ .notes = notes, .length = length };
}

// ---- phrase resolution (relative time + dynamics) ----
//
// Phrases are the one place `positioned` (polyphony) and `dynamic_*` can
// appear. Dynamics aren't notes - they're velocity directives for whatever
// follows - so they're resolved as a separate pass of (tick, velocity)
// breakpoints, then looked up per note. This keeps resolvePattern's
// recursion purely about geometry (pitch/timing), not loudness.

fn resolvePhrasePattern(self: *Self, name: []const u8) LowerError!Pattern {
    if (self.phrase_patterns.get(name)) |cached| return cached;

    const def_index = self.phrase_defs.get(name) orelse return error.UndefinedReference;
    const body = self.program.nodes[def_index].phrase_def.body;

    var notes: std.ArrayList(RelativeNote) = .empty;
    var breakpoints: std.ArrayList(DynamicPoint) = .empty;
    var cursor: u32 = 0;
    var length: u32 = 0;

    for (body) |elem_index| {
        switch (self.program.nodes[elem_index]) {
            .dynamic_level => |d| try breakpoints.append(self.allocator, .{
                .tick = self.tickForPosition(d.position),
                .velocity = velocityForLevel(d.level),
            }),

            .dynamic_shape => |d| {
                const start_tick = self.tickForPosition(d.position);
                const from_velocity = velocityAt(breakpoints.items, start_tick);

                try breakpoints.append(self.allocator, .{
                    .tick = start_tick,
                    .velocity = from_velocity,
                    .ramp_to = .{
                        .velocity = velocityForLevel(d.target),
                        .end_tick = start_tick + d.bars * self.barTicks(),
                    },
                });
            },

            // A polyphonic voice: placed at an absolute phrase-relative tick,
            // independent of (and without disturbing) the running cursor.
            .positioned => |p| {
                const at = self.tickForPosition(p.position);
                const sub = try self.resolvePattern(p.target);
                try appendShifted(self.allocator, &notes, sub, at);
                length = @max(length, at + sub.length);
            },

            else => {
                const sub = try self.resolvePattern(elem_index);
                try appendShifted(self.allocator, &notes, sub, cursor);
                cursor += sub.length;
                length = @max(length, cursor);
            },
        }
    }

    std.mem.sort(DynamicPoint, breakpoints.items, {}, lessByTick);
    for (notes.items) |*n| n.velocity = velocityAt(breakpoints.items, n.start);

    const pattern = Pattern{ .notes = try notes.toOwnedSlice(self.allocator), .length = length };
    try self.phrase_patterns.put(self.allocator, name, pattern);
    return pattern;
}

fn velocityAt(points: []const DynamicPoint, tick: u32) u8 {
    var active: ?DynamicPoint = null;
    for (points) |pt| {
        if (pt.tick > tick) break;
        active = pt;
    }
    const pt = active orelse return default_velocity;

    const ramp = pt.ramp_to orelse return pt.velocity;
    if (tick >= ramp.end_tick or ramp.end_tick == pt.tick) return ramp.velocity;

    const span: f32 = @floatFromInt(ramp.end_tick - pt.tick);
    const elapsed: f32 = @floatFromInt(tick - pt.tick);
    const from: f32 = @floatFromInt(pt.velocity);
    const to: f32 = @floatFromInt(ramp.velocity);

    return @intFromFloat(std.math.clamp(from + (to - from) * (elapsed / span), 0, 127));
}

// ---- shared helpers ----

fn appendShifted(allocator: Allocator, notes: *std.ArrayList(RelativeNote), pattern: Pattern, offset: u32) !void {
    for (pattern.notes) |n| {
        try notes.append(allocator, .{
            .start = offset + n.start,
            .duration = n.duration,
            .pitch = n.pitch,
            .velocity = n.velocity,
        });
    }
}

fn lessByStart(_: void, a: NoteEvent, b: NoteEvent) bool {
    return a.start < b.start;
}

fn lessByPitch(_: void, a: RelativeNote, b: RelativeNote) bool {
    return a.pitch < b.pitch;
}

fn arpSequence(allocator: Allocator, n: usize, mode: ast.ArpMode) ![]const usize {
    switch (mode) {
        .up => {
            const buf = try allocator.alloc(usize, n);
            for (buf, 0..) |*b, i| b.* = i;
            return buf;
        },
        .down => {
            const buf = try allocator.alloc(usize, n);
            for (buf, 0..) |*b, i| b.* = n - 1 - i;
            return buf;
        },
        .up_down => {
            if (n <= 1) return arpSequence(allocator, n, .up);
            const len = 2 * (n - 1);
            const buf = try allocator.alloc(usize, len);
            for (0..n) |i| buf[i] = i;
            for (1..n - 1) |i| buf[n - 1 + i] = n - 1 - i;
            return buf;
        },
        .bounce => {
            if (n <= 1) return arpSequence(allocator, n, .up);
            const len = 2 * n;
            const buf = try allocator.alloc(usize, len);
            for (0..n) |i| buf[i] = i;
            for (0..n) |i| buf[n + i] = n - 1 - i;
            return buf;
        },
    }
}

fn lessByTick(_: void, a: DynamicPoint, b: DynamicPoint) bool {
    return a.tick < b.tick;
}

// `@bar.beat` is 0-based and relative to the start of its containing
// phrase - `@0.0` is the very first beat of the phrase.
fn tickForPosition(self: *Self, position: ast.Position) u32 {
    return position.bar * self.barTicks() + position.beat * self.beatTicks();
}

fn barTicks(self: *Self) u32 {
    return self.ticks_per_quarter * self.numerator * 4 / self.denominator;
}

fn beatTicks(self: *Self) u32 {
    return self.ticks_per_quarter * 4 / self.denominator;
}

fn ticksFor(self: *Self, duration: ast.Duration) u32 {
    const divisor: u32 = switch (duration.kind) {
        .whole => 1,
        .half => 2,
        .quarter => 4,
        .eighth => 8,
        .sixteenth => 16,
    };

    var ticks = self.barTicks() * duration.multiplier / divisor;
    if (duration.dotted) ticks += ticks / 2;
    return ticks;
}

fn midiPitch(p: ast.Pitched) u8 {
    const semitone: i32 = switch (p.pitch) {
        .c => 0,
        .d => 2,
        .e => 4,
        .f => 5,
        .g => 7,
        .a => 9,
        .b => 11,
    };
    const accidental: i32 = switch (p.accidental) {
        .natural => 0,
        .sharp => 1,
        .flat => -1,
    };

    return clampPitch((@as(i32, p.octave) + 1) * 12 + semitone + accidental);
}

fn clampPitch(value: i32) u8 {
    return @intCast(std.math.clamp(value, 0, 127));
}

fn velocityForLevel(level: ast.DynamicLevel) u8 {
    return switch (level) {
        .ppp => 16,
        .pp => 32,
        .p => 48,
        .mp => 64,
        .mf => 80,
        .f => 96,
        .ff => 112,
        .fff => 127,
    };
}
