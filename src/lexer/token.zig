pub const TokenType = enum {
    // general
    identifier,
    int,
    illegal,
    eof,
    comment,

    // literals
    note,
    duration,

    // keywords
    tempo,
    time_signature,
    phrase,
    chord,
    section,
    track,
    song,
    rest,
    dynamic,
    crescendo,
    diminuendo,
    to,
    over,

    // symbols
    dot,
    equals,
    at,
    asterisk,
    plus,
    minus,
    slash,
    lbracket,
    rbracket,
    colon,
};

tokenType: TokenType,
literal: []const u8,
line: u32,
column: u32,

pub fn init(tokenType: TokenType, literal: []const u8, line: u32, column: u32) @This() {
    return .{
        .tokenType = tokenType,
        .literal = literal,
        .line = line,
        .column = column,
    };
}
