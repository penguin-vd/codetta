// Backend-agnostic output of the lowering pass

pub const NoteEvent = struct {
    start: u32, // absolute position, in ticks from the start of the piece
    duration: u32, // length, in ticks
    pitch: u8, // MIDI note number 0-127 (C4 = 60)
    velocity: u8, // 0-127, resolved from dynamics
    track: u16, // index into Score.tracks
};

pub const TrackInfo = struct {
    name: []const u8,
};

pub const TimeSignature = struct {
    numerator: u32,
    denominator: u32,
};

pub const Score = struct {
    ticks_per_quarter: u32,
    tempo_bpm: u32,
    time_signature: TimeSignature,
    tracks: []const TrackInfo,
    notes: []const NoteEvent,
};
