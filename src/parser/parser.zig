const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Lexer = @import("../lexer/lexer.zig");
const Token = @import("../lexer/token.zig");
const TokenType = Token.TokenType;

const ast = @import("ast.zig");
const Node = ast.Node;
const NodeIndex = ast.NodeIndex;
const Program = ast.Program;

const ParseError = error{ SyntaxError, OutOfMemory };

pub const Diagnostic = struct {
    message: []const u8,
    line: u32,
    column: u32,
};

allocator: Allocator,
lexer: Lexer,
cur_token: Token,
peek_token: Token,
nodes: std.ArrayList(Node),
top_level: std.ArrayList(NodeIndex),
diagnostic: ?Diagnostic = null,

pub fn init(allocator: Allocator, input: []const u8) Self {
    var lexer = Lexer.init(input);
    const cur = nextSignificant(&lexer);
    const peek = nextSignificant(&lexer);

    return .{
        .allocator = allocator,
        .lexer = lexer,
        .cur_token = cur,
        .peek_token = peek,
        .nodes = .empty,
        .top_level = .empty,
        .diagnostic = null,
    };
}

fn nextSignificant(lexer: *Lexer) Token {
    while (true) {
        const tok = lexer.nextToken();
        if (tok.tokenType != .comment) return tok;
    }
}

fn advance(self: *Self) void {
    self.cur_token = self.peek_token;
    self.peek_token = nextSignificant(&self.lexer);
}

fn fail(self: *Self, comptime fmt: []const u8, args: anytype) ParseError {
    return self.failAt(self.cur_token, fmt, args);
}

fn failAt(self: *Self, tok: Token, comptime fmt: []const u8, args: anytype) ParseError {
    self.diagnostic = .{
        .message = std.fmt.allocPrint(self.allocator, fmt, args) catch "out of memory",
        .line = tok.line,
        .column = tok.column,
    };
    return error.SyntaxError;
}

fn expect(self: *Self, tokenType: TokenType) ParseError!Token {
    if (self.cur_token.tokenType != tokenType) {
        return self.fail("expected {s}, found {s} '{s}'", .{
            @tagName(tokenType),
            @tagName(self.cur_token.tokenType),
            self.cur_token.literal,
        });
    }

    const tok = self.cur_token;
    self.advance();
    return tok;
}

fn addNode(self: *Self, node: Node) !NodeIndex {
    const index: NodeIndex = @intCast(self.nodes.items.len);
    try self.nodes.append(self.allocator, node);
    return index;
}

pub fn parseProgram(self: *Self) !Program {
    while (self.cur_token.tokenType != .eof) {
        const index = try self.parseTopLevel();
        try self.top_level.append(self.allocator, index);
    }

    return .{
        .nodes = try self.nodes.toOwnedSlice(self.allocator),
        .top_level = try self.top_level.toOwnedSlice(self.allocator),
    };
}

pub const Lenient = struct {
    program: Program,
    diagnostics: []const Diagnostic,
};

const max_diagnostics = 64;

// Like parseProgram, but recovers from syntax errors so a whole file can be
// checked at once: on failure it records the diagnostic, skips to the next
// top-level declaration, and keeps going.
pub fn parseLenient(self: *Self) error{OutOfMemory}!Lenient {
    var diagnostics: std.ArrayList(Diagnostic) = .empty;

    while (self.cur_token.tokenType != .eof) {
        const index = self.parseTopLevel() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SyntaxError => {
                if (self.diagnostic) |d| {
                    if (diagnostics.items.len < max_diagnostics) try diagnostics.append(self.allocator, d);
                }
                self.synchronize();
                continue;
            },
        };
        try self.top_level.append(self.allocator, index);
    }

    return .{
        .program = .{
            .nodes = try self.nodes.toOwnedSlice(self.allocator),
            .top_level = try self.top_level.toOwnedSlice(self.allocator),
        },
        .diagnostics = try diagnostics.toOwnedSlice(self.allocator),
    };
}

fn synchronize(self: *Self) void {
    self.advance();
    while (!isTopLevelStart(self.cur_token.tokenType) and self.cur_token.tokenType != .eof) {
        self.advance();
    }
}

fn isTopLevelStart(t: TokenType) bool {
    return switch (t) {
        .tempo, .time_signature, .seed, .chord, .phrase, .section, .song => true,
        else => false,
    };
}

fn parseTopLevel(self: *Self) !NodeIndex {
    return switch (self.cur_token.tokenType) {
        .tempo => self.parseTempo(),
        .time_signature => self.parseTimeSignature(),
        .seed => self.parseSeed(),
        .chord => self.parseChordDef(),
        .phrase => self.parsePhraseDef(),
        .section => self.parseSectionDef(),
        .song => self.parseSongDef(),
        else => self.fail("expected a top-level declaration, found {s} '{s}'", .{
            @tagName(self.cur_token.tokenType), self.cur_token.literal,
        }),
    };
}

fn parseTempo(self: *Self) !NodeIndex {
    _ = try self.expect(.tempo);
    const bpm_tok = try self.expect(.int);

    return self.addNode(.{ .tempo = .{ .bpm = try self.parseIntTok(u32, bpm_tok) } });
}

fn parseTimeSignature(self: *Self) !NodeIndex {
    _ = try self.expect(.time_signature);
    const num_tok = try self.expect(.int);
    _ = try self.expect(.slash);
    const den_tok = try self.expect(.int);

    return self.addNode(.{ .time_signature = .{
        .numerator = try self.parseIntTok(u32, num_tok),
        .denominator = try self.parseIntTok(u32, den_tok),
    } });
}

fn parseSeed(self: *Self) !NodeIndex {
    _ = try self.expect(.seed);
    const val_tok = try self.expect(.int);

    return self.addNode(.{ .seed = .{ .value = try self.parseIntTok(u64, val_tok) } });
}

fn parseChordDef(self: *Self) !NodeIndex {
    _ = try self.expect(.chord);
    const name_tok = try self.expect(.identifier);
    _ = try self.expect(.equals);
    _ = try self.expect(.lbracket);

    var notes: std.ArrayList(ast.Pitched) = .empty;
    while (self.cur_token.tokenType != .rbracket) {
        const note_tok = try self.expect(.note);
        try notes.append(self.allocator, try self.parsePitched(note_tok));
    }
    _ = try self.expect(.rbracket);

    return self.addNode(.{ .chord_def = .{
        .name = name_tok.literal,
        .notes = try notes.toOwnedSlice(self.allocator),
        .line = name_tok.line,
        .column = name_tok.column,
    } });
}

fn parsePhraseDef(self: *Self) !NodeIndex {
    _ = try self.expect(.phrase);
    const name_tok = try self.expect(.identifier);
    _ = try self.expect(.equals);

    var body: std.ArrayList(NodeIndex) = .empty;
    while (try self.parsePhraseElement()) |element| {
        try body.append(self.allocator, element);
    }

    return self.addNode(.{ .phrase_def = .{
        .name = name_tok.literal,
        .body = try body.toOwnedSlice(self.allocator),
        .line = name_tok.line,
        .column = name_tok.column,
    } });
}

fn parseSectionDef(self: *Self) !NodeIndex {
    _ = try self.expect(.section);
    const name_tok = try self.expect(.identifier);
    _ = try self.expect(.equals);

    var tracks: std.ArrayList(NodeIndex) = .empty;
    while (self.cur_token.tokenType == .track) {
        try tracks.append(self.allocator, try self.parseTrack());
    }

    return self.addNode(.{ .section_def = .{
        .name = name_tok.literal,
        .tracks = try tracks.toOwnedSlice(self.allocator),
        .line = name_tok.line,
        .column = name_tok.column,
    } });
}

fn parseSongDef(self: *Self) !NodeIndex {
    _ = try self.expect(.song);
    _ = try self.expect(.equals);

    var items: std.ArrayList(NodeIndex) = .empty;
    while (try self.parseSongItem()) |item| {
        try items.append(self.allocator, item);
    }

    return self.addNode(.{ .song_def = .{ .items = try items.toOwnedSlice(self.allocator) } });
}

fn parsePhraseElement(self: *Self) ParseError!?NodeIndex {
    var node: NodeIndex = switch (self.cur_token.tokenType) {
        .note => try self.parseNoteElement(),
        .rest => try self.parseRestElement(),
        .identifier => try self.parseChordRefElement(),
        .lbracket => try self.parseInlineChord(),
        .at => return try self.parseVoice(),
        .dynamic => return try self.parseDynamicElement(),
        else => return null,
    };

    while (try self.tryParseTransform()) |kind| {
        node = try self.addNode(.{ .transform = .{ .target = node, .op = kind } });
    }

    return try self.maybeWrapRepeat(node);
}

fn parseNoteElement(self: *Self) !NodeIndex {
    const note_tok = try self.expect(.note);
    const pitched = try self.parsePitched(note_tok);
    const duration = try self.parseDuration();

    return self.addNode(.{ .note = .{ .pitched = pitched, .duration = duration } });
}

fn parseRestElement(self: *Self) !NodeIndex {
    _ = try self.expect(.rest);
    const duration = try self.parseDuration();

    return self.addNode(.{ .rest = .{ .duration = duration } });
}

fn parseInlineChord(self: *Self) !NodeIndex {
    _ = try self.expect(.lbracket);

    var notes: std.ArrayList(ast.Pitched) = .empty;
    while (self.cur_token.tokenType != .rbracket) {
        const note_tok = try self.expect(.note);
        try notes.append(self.allocator, try self.parsePitched(note_tok));
    }
    _ = try self.expect(.rbracket);

    const duration = try self.parseDuration();
    return self.addNode(.{ .inline_chord = .{
        .notes = try notes.toOwnedSlice(self.allocator),
        .duration = duration,
    } });
}

fn parseChordRefElement(self: *Self) !NodeIndex {
    const name_tok = try self.expect(.identifier);
    const duration = try self.parseDuration();

    return self.addNode(.{ .chord_ref = .{
        .name = name_tok.literal,
        .duration = duration,
        .line = name_tok.line,
        .column = name_tok.column,
    } });
}

fn parseVoice(self: *Self) ParseError!NodeIndex {
    _ = try self.expect(.at);
    const position = try self.parsePosition();
    return self.addNode(.{ .voice = .{ .position = position } });
}

fn parseDynamicElement(self: *Self) !NodeIndex {
    _ = try self.expect(.dynamic);
    _ = try self.expect(.at);
    const position = try self.parsePosition();

    if (self.cur_token.tokenType == .crescendo or self.cur_token.tokenType == .diminuendo) {
        return self.parseDynamicShape(position);
    }

    const level_tok = try self.expect(.identifier);

    return self.addNode(.{ .dynamic_level = .{
        .position = position,
        .level = try self.parseDynamicLevel(level_tok),
    } });
}

fn parseDynamicShape(self: *Self, position: ast.Position) !NodeIndex {
    const shape: ast.DynamicShapeKind = switch (self.cur_token.tokenType) {
        .crescendo => .crescendo,
        .diminuendo => .diminuendo,
        else => unreachable,
    };
    self.advance();

    _ = try self.expect(.to);
    const level_tok = try self.expect(.identifier);
    _ = try self.expect(.over);
    const bars_tok = try self.expect(.int);
    _ = try self.expect(.identifier); // "bar" / "bars"

    return self.addNode(.{ .dynamic_shape = .{
        .position = position,
        .shape = shape,
        .target = try self.parseDynamicLevel(level_tok),
        .bars = try self.parseIntTok(u32, bars_tok),
    } });
}

fn parseTrack(self: *Self) !NodeIndex {
    _ = try self.expect(.track);
    const name_tok = try self.expect(.identifier);
    _ = try self.expect(.colon);

    return self.addNode(.{ .track = .{
        .name = name_tok.literal,
        .content = try self.parseTrackContent(),
    } });
}

fn parseTrackContent(self: *Self) !NodeIndex {
    var items: std.ArrayList(NodeIndex) = .empty;
    while (try self.parseTrackItem()) |item| {
        try items.append(self.allocator, item);
    }

    if (items.items.len == 1) {
        return items.items[0];
    }

    return self.addNode(.{ .sequence = .{ .items = try items.toOwnedSlice(self.allocator) } });
}

fn parseTrackItem(self: *Self) !?NodeIndex {
    var node: NodeIndex = switch (self.cur_token.tokenType) {
        .identifier => try self.parseIdentifierOrChordRef(),
        .note => try self.parseNoteElement(),
        .rest => try self.parseRestElement(),
        .lbracket => try self.parseInlineChord(),
        else => return null,
    };

    while (try self.tryParseTransform()) |kind| {
        node = try self.addNode(.{ .transform = .{ .target = node, .op = kind } });
    }

    return try self.maybeWrapRepeat(node);
}

fn parseSongItem(self: *Self) !?NodeIndex {
    if (self.cur_token.tokenType != .identifier) return null;

    const name_tok = self.cur_token;
    self.advance();

    const node = try self.addNode(.{ .identifier = .{
        .name = name_tok.literal,
        .line = name_tok.line,
        .column = name_tok.column,
    } });
    return try self.maybeWrapRepeat(node);
}

fn parseIdentifierOrChordRef(self: *Self) !NodeIndex {
    const name_tok = self.cur_token;

    if (self.peek_token.tokenType == .dot) {
        self.advance();
        const duration = try self.parseDuration();
        return self.addNode(.{ .chord_ref = .{
            .name = name_tok.literal,
            .duration = duration,
            .line = name_tok.line,
            .column = name_tok.column,
        } });
    }

    self.advance();
    return self.addNode(.{ .identifier = .{
        .name = name_tok.literal,
        .line = name_tok.line,
        .column = name_tok.column,
    } });
}

fn maybeWrapRepeat(self: *Self, node: NodeIndex) !NodeIndex {
    if (self.cur_token.tokenType != .asterisk) return node;

    self.advance();
    const count_tok = try self.expect(.int);

    return self.addNode(.{ .repeat = .{ .target = node, .count = try self.parseIntTok(u32, count_tok) } });
}

fn tryParseTransform(self: *Self) !?ast.TransformKind {
    if (self.cur_token.tokenType != .identifier) return null;

    const name = self.cur_token.literal;

    if (std.mem.eql(u8, name, "reverse")) {
        self.advance();
        return .reverse;
    }
    if (std.mem.eql(u8, name, "arp")) {
        self.advance();
        var mode: ast.ArpMode = .up;
        if (self.cur_token.tokenType == .dot) {
            self.advance();
            const mode_tok = try self.expect(.identifier);
            mode = std.meta.stringToEnum(ast.ArpMode, mode_tok.literal) orelse
                return self.failAt(mode_tok, "unknown arp mode '{s}'", .{mode_tok.literal});
        }
        var cycles: u32 = 1;
        if (self.cur_token.tokenType == .identifier and
            self.cur_token.literal.len >= 2 and self.cur_token.literal[0] == 'x')
        {
            cycles = try self.parseMultiplier();
        }
        return .{ .arp = .{ .mode = mode, .cycles = cycles } };
    }
    if (std.mem.eql(u8, name, "transpose")) {
        self.advance();
        return .{ .transpose = try self.parseSignedInt() };
    }
    if (std.mem.eql(u8, name, "augment")) {
        self.advance();
        return .{ .augment = try self.parseMultiplier() };
    }
    if (std.mem.eql(u8, name, "diminish")) {
        self.advance();
        return .{ .diminish = try self.parseMultiplier() };
    }
    if (std.mem.eql(u8, name, "shuffle")) {
        self.advance();
        return .shuffle;
    }
    if (std.mem.eql(u8, name, "staccato")) {
        self.advance();
        return .{ .articulation = .staccato };
    }
    if (std.mem.eql(u8, name, "legato")) {
        self.advance();
        return .{ .articulation = .legato };
    }
    return null;
}

// ---- shared value parsing ----

fn parseDuration(self: *Self) !ast.Duration {
    _ = try self.expect(.dot);

    var multiplier: u32 = 1;
    if (self.cur_token.tokenType == .int) {
        multiplier = try self.parseIntTok(u32, self.cur_token);
        self.advance();
    }

    const dur_tok = try self.expect(.duration);
    const kind = std.meta.stringToEnum(ast.DurationKind, dur_tok.literal) orelse
        return self.failAt(dur_tok, "unknown duration '{s}'", .{dur_tok.literal});

    // Dotted durations are written as a trailing `.dot` - both the
    // separator and the keyword lex as `.dot`, so distinguish by literal.
    var dotted = false;
    if (self.cur_token.tokenType == .dot and std.mem.eql(u8, self.cur_token.literal, ".") and
        self.peek_token.tokenType == .dot and std.mem.eql(u8, self.peek_token.literal, "dot"))
    {
        self.advance();
        self.advance();
        dotted = true;
    }

    var triplet = false;
    if (self.cur_token.tokenType == .dot and std.mem.eql(u8, self.cur_token.literal, ".") and
        self.peek_token.tokenType == .identifier and std.mem.eql(u8, self.peek_token.literal, "t"))
    {
        self.advance();
        self.advance();
        triplet = true;
    }

    return .{ .kind = kind, .dotted = dotted, .triplet = triplet, .multiplier = multiplier };
}

// Positions are written either as `@bar.beat` (e.g. @1.1) or, for dynamics,
// as a bare offset (e.g. @0) - the beat defaults to 0 when omitted.
fn parsePosition(self: *Self) !ast.Position {
    const bar_tok = try self.expect(.int);
    const bar = try self.parseIntTok(u32, bar_tok);

    var beat: u32 = 0;
    if (self.cur_token.tokenType == .dot) {
        self.advance();
        const beat_tok = try self.expect(.int);
        beat = try self.parseIntTok(u32, beat_tok);
    }

    return .{ .bar = bar, .beat = beat };
}

fn parseSignedInt(self: *Self) !i32 {
    var sign: i32 = 1;
    switch (self.cur_token.tokenType) {
        .minus => {
            sign = -1;
            self.advance();
        },
        .plus => self.advance(),
        else => {},
    }

    const tok = try self.expect(.int);
    return sign * try self.parseIntTok(i32, tok);
}

fn parseMultiplier(self: *Self) !u32 {
    const tok = try self.expect(.identifier);
    if (tok.literal.len < 2 or tok.literal[0] != 'x') {
        return self.failAt(tok, "expected multiplier like 'x2', found '{s}'", .{tok.literal});
    }

    return std.fmt.parseInt(u32, tok.literal[1..], 10) catch
        self.failAt(tok, "invalid multiplier '{s}'", .{tok.literal});
}

fn parsePitched(self: *Self, tok: Token) !ast.Pitched {
    const literal = tok.literal;
    if (literal.len < 2) return self.failAt(tok, "invalid note '{s}'", .{literal});

    const pitch: ast.Pitch = switch (literal[0]) {
        'C' => .c,
        'D' => .d,
        'E' => .e,
        'F' => .f,
        'G' => .g,
        'A' => .a,
        'B' => .b,
        else => return self.failAt(tok, "invalid note '{s}'", .{literal}),
    };

    var i: usize = 1;
    var accidental: ast.Accidental = .natural;
    if (literal[i] == '#') {
        accidental = .sharp;
        i += 1;
    } else if (literal[i] == 'b') {
        accidental = .flat;
        i += 1;
    }

    const octave = std.fmt.parseInt(u8, literal[i..], 10) catch
        return self.failAt(tok, "invalid note octave in '{s}'", .{literal});

    return .{ .pitch = pitch, .accidental = accidental, .octave = octave };
}

fn parseDynamicLevel(self: *Self, tok: Token) !ast.DynamicLevel {
    return std.meta.stringToEnum(ast.DynamicLevel, tok.literal) orelse
        self.failAt(tok, "unknown dynamic level '{s}'", .{tok.literal});
}

fn parseIntTok(self: *Self, comptime T: type, tok: Token) ParseError!T {
    return std.fmt.parseInt(T, tok.literal, 10) catch
        self.failAt(tok, "invalid integer '{s}'", .{tok.literal});
}
