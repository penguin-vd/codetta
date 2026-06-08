const std = @import("std");
const testing = std.testing;

const Lexer = @import("lexer.zig");
const Token = @import("token.zig");
const TokenType = Token.TokenType;

const Expected = struct {
    type: TokenType,
    literal: []const u8,
};

fn expectTokens(input: []const u8, expected: []const Expected) !void {
    var lexer = Lexer.init(input);

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try testing.expectEqual(exp.type, tok.tokenType);
        try testing.expectEqualStrings(exp.literal, tok.literal);
    }
}

test "settings" {
    try expectTokens("tempo 120\ntime_signature 4/4", &.{
        .{ .type = .tempo, .literal = "tempo" },
        .{ .type = .int, .literal = "120" },
        .{ .type = .time_signature, .literal = "time_signature" },
        .{ .type = .int, .literal = "4" },
        .{ .type = .slash, .literal = "/" },
        .{ .type = .int, .literal = "4" },
        .{ .type = .eof, .literal = "" },
    });
}

test "notes and durations" {
    try expectTokens("C4.quarter Bb3.quarter F#5.eighth rest.half", &.{
        .{ .type = .note, .literal = "C4" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .duration, .literal = "quarter" },
        .{ .type = .note, .literal = "Bb3" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .duration, .literal = "quarter" },
        .{ .type = .note, .literal = "F#5" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .duration, .literal = "eighth" },
        .{ .type = .rest, .literal = "rest" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .duration, .literal = "half" },
        .{ .type = .eof, .literal = "" },
    });
}

test "dotted duration" {
    try expectTokens("C4.quarter.dot", &.{
        .{ .type = .note, .literal = "C4" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .duration, .literal = "quarter" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .dot, .literal = "dot" },
        .{ .type = .eof, .literal = "" },
    });
}

test "chord definition" {
    try expectTokens("chord Cmaj = [C4 E4 G4]", &.{
        .{ .type = .chord, .literal = "chord" },
        .{ .type = .identifier, .literal = "Cmaj" },
        .{ .type = .equals, .literal = "=" },
        .{ .type = .lbracket, .literal = "[" },
        .{ .type = .note, .literal = "C4" },
        .{ .type = .note, .literal = "E4" },
        .{ .type = .note, .literal = "G4" },
        .{ .type = .rbracket, .literal = "]" },
        .{ .type = .eof, .literal = "" },
    });
}

test "phrase, polyphony and transformations" {
    try expectTokens("phrase melody = C4.quarter\n@1.1 C3.whole\nmelody transpose +5 reverse", &.{
        .{ .type = .phrase, .literal = "phrase" },
        .{ .type = .identifier, .literal = "melody" },
        .{ .type = .equals, .literal = "=" },
        .{ .type = .note, .literal = "C4" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .duration, .literal = "quarter" },
        .{ .type = .at, .literal = "@" },
        .{ .type = .int, .literal = "1" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .int, .literal = "1" },
        .{ .type = .note, .literal = "C3" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .duration, .literal = "whole" },
        .{ .type = .identifier, .literal = "melody" },
        .{ .type = .identifier, .literal = "transpose" },
        .{ .type = .plus, .literal = "+" },
        .{ .type = .int, .literal = "5" },
        .{ .type = .identifier, .literal = "reverse" },
        .{ .type = .eof, .literal = "" },
    });
}

test "dynamics" {
    try expectTokens("dynamic @0 p\ndynamic @0.3 crescendo to f over 1 bar", &.{
        .{ .type = .dynamic, .literal = "dynamic" },
        .{ .type = .at, .literal = "@" },
        .{ .type = .int, .literal = "0" },
        .{ .type = .identifier, .literal = "p" },
        .{ .type = .dynamic, .literal = "dynamic" },
        .{ .type = .at, .literal = "@" },
        .{ .type = .int, .literal = "0" },
        .{ .type = .dot, .literal = "." },
        .{ .type = .int, .literal = "3" },
        .{ .type = .crescendo, .literal = "crescendo" },
        .{ .type = .to, .literal = "to" },
        .{ .type = .identifier, .literal = "f" },
        .{ .type = .over, .literal = "over" },
        .{ .type = .int, .literal = "1" },
        .{ .type = .identifier, .literal = "bar" },
        .{ .type = .eof, .literal = "" },
    });
}

test "comments" {
    try expectTokens("tempo 120 -- BPM\nsong", &.{
        .{ .type = .tempo, .literal = "tempo" },
        .{ .type = .int, .literal = "120" },
        .{ .type = .comment, .literal = " BPM" },
        .{ .type = .song, .literal = "song" },
        .{ .type = .eof, .literal = "" },
    });
}

test "section and repetition" {
    try expectTokens("section verse =\n  track melody: melody * 2", &.{
        .{ .type = .section, .literal = "section" },
        .{ .type = .identifier, .literal = "verse" },
        .{ .type = .equals, .literal = "=" },
        .{ .type = .track, .literal = "track" },
        .{ .type = .identifier, .literal = "melody" },
        .{ .type = .colon, .literal = ":" },
        .{ .type = .identifier, .literal = "melody" },
        .{ .type = .asterisk, .literal = "*" },
        .{ .type = .int, .literal = "2" },
        .{ .type = .eof, .literal = "" },
    });
}

test "illegal characters" {
    try expectTokens("$", &.{
        .{ .type = .illegal, .literal = "$" },
        .{ .type = .eof, .literal = "" },
    });
}

test "illegal characters across multiple lines" {
    try expectTokens("tempo $\n@ ?", &.{
        .{ .type = .tempo, .literal = "tempo" },
        .{ .type = .illegal, .literal = "$" },
        .{ .type = .at, .literal = "@" },
        .{ .type = .illegal, .literal = "?" },
        .{ .type = .eof, .literal = "" },
    });
}

const ExpectedLoc = struct {
    type: TokenType,
    literal: []const u8,
    line: u32,
    column: u32,
};

fn expectTokenLocations(input: []const u8, expected: []const ExpectedLoc) !void {
    var lexer = Lexer.init(input);

    for (expected) |exp| {
        const tok = lexer.nextToken();
        try testing.expectEqual(exp.type, tok.tokenType);
        try testing.expectEqualStrings(exp.literal, tok.literal);
        try testing.expectEqual(exp.line, tok.line);
        try testing.expectEqual(exp.column, tok.column);
    }
}

test "tracks line and column numbers" {
    try expectTokenLocations("tempo 120\ntime_signature 4/4", &.{
        .{ .type = .tempo, .literal = "tempo", .line = 1, .column = 1 },
        .{ .type = .int, .literal = "120", .line = 1, .column = 7 },
        .{ .type = .time_signature, .literal = "time_signature", .line = 2, .column = 1 },
        .{ .type = .int, .literal = "4", .line = 2, .column = 16 },
        .{ .type = .slash, .literal = "/", .line = 2, .column = 17 },
        .{ .type = .int, .literal = "4", .line = 2, .column = 18 },
        .{ .type = .eof, .literal = "", .line = 2, .column = 19 },
    });
}

test "tracks line and column numbers for illegal tokens" {
    try expectTokenLocations("tempo $\n@ ?", &.{
        .{ .type = .tempo, .literal = "tempo", .line = 1, .column = 1 },
        .{ .type = .illegal, .literal = "$", .line = 1, .column = 7 },
        .{ .type = .at, .literal = "@", .line = 2, .column = 1 },
        .{ .type = .illegal, .literal = "?", .line = 2, .column = 3 },
    });
}
