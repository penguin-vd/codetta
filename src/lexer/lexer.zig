const Self = @This();

const std = @import("std");
const Token = @import("token.zig");
const TokenType = Token.TokenType;

input: []const u8,
pos: usize = 0,
readPos: usize = 0,
ch: u8 = 0,
line: u32 = 1,
col: u32 = 1,

const keywords: std.StaticStringMap(TokenType) = .initComptime(.{
    .{ "tempo", .tempo },
    .{ "time_signature", .time_signature },
    .{ "phrase", .phrase },
    .{ "chord", .chord },
    .{ "section", .section },
    .{ "track", .track },
    .{ "song", .song },
    .{ "rest", .rest },
    .{ "dynamic", .dynamic },
    .{ "crescendo", .crescendo },
    .{ "diminuendo", .diminuendo },
    .{ "to", .to },
    .{ "over", .over },
    .{ "dot", .dot },
    .{ "whole", .duration },
    .{ "half", .duration },
    .{ "quarter", .duration },
    .{ "eighth", .duration },
    .{ "sixteenth", .duration },
});


pub fn init(input: []const u8) Self {
    var new: Self = .{
        .input = input,
    };

    new.readChar();
    return new;
}


fn readChar(self: *Self) void {
    if (self.ch == '\n') {
        self.line += 1;
        self.col = 1;
    } else if (self.readPos > 0) {
        self.col += 1;
    }

    if (self.readPos >= self.input.len) {
        self.ch = 0;
    } else {
        self.ch = self.input[self.readPos];
    }

    self.pos = self.readPos;
    self.readPos += 1;
}

fn peekChar(self: *Self) u8 {
    if (self.readPos >= self.input.len) {
        return 0;
    }
    return self.input[self.readPos];
}

fn skipWhitespace(self: *Self) void {
    while (self.ch == ' ' or self.ch == '\t' or self.ch == '\n' or self.ch == '\r') {
        self.readChar();
    }
}

fn readIdentifier(self: *Self) []const u8 {
    const start = self.pos;
    while (isLetter(self.ch) or isDigit(self.ch) or self.ch == '_' or self.ch == '#') {
        self.readChar();
    }
    return self.input[start..self.pos];
}

fn readNumber(self: *Self) []const u8 {
    const start = self.pos;
    while (isDigit(self.ch)) {
        self.readChar();
    }
    return self.input[start..self.pos];
}

fn readComment(self: *Self) []const u8 {
    self.readChar(); // consume second '-'
    self.readChar(); // move past "--"
    const start = self.pos;
    while (self.ch != '\n' and self.ch != 0) {
        self.readChar();
    }
    return self.input[start..self.pos];
}

fn simpleToken(self: *Self, tokenType: TokenType, line: u32, col: u32) Token {
    const literal = self.input[self.pos .. self.pos + 1];
    self.readChar();
    return Token.init(tokenType, literal, line, col);
}

pub fn nextToken(self: *Self) Token {
    self.skipWhitespace();

    const line = self.line;
    const col = self.col;

    switch (self.ch) {
        '=' => return self.simpleToken(.equals, line, col),
        '.' => return self.simpleToken(.dot, line, col),
        '@' => return self.simpleToken(.at, line, col),
        '*' => return self.simpleToken(.asterisk, line, col),
        '+' => return self.simpleToken(.plus, line, col),
        '-' => {
            if (self.peekChar() == '-') {
                return Token.init(.comment, self.readComment(), line, col);
            }
            return self.simpleToken(.minus, line, col);
        },
        '/' => return self.simpleToken(.slash, line, col),
        '[' => return self.simpleToken(.lbracket, line, col),
        ']' => return self.simpleToken(.rbracket, line, col),
        ':' => return self.simpleToken(.colon, line, col),
        0 => return Token.init(.eof, "", line, col),
        else => {},
    }

    if (isLetter(self.ch) or self.ch == '_') {
        const literal = self.readIdentifier();
        return Token.init(lookupIdent(literal), literal, line, col);
    }

    if (isDigit(self.ch)) {
        return Token.init(.int, self.readNumber(), line, col);
    }

    return self.simpleToken(.illegal, line, col);
}

fn lookupIdent(ident: []const u8) TokenType {
    if (keywords.get(ident)) |tokenType| {
        return tokenType;
    }
    if (isNote(ident)) {
        return .note;
    }
    return .identifier;
}

fn isLetter(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn isNote(ident: []const u8) bool {
    if (ident.len < 2) return false;

    var i: usize = 0;
    if (ident[i] < 'A' or ident[i] > 'G') return false;
    i += 1;

    if (ident[i] == '#' or ident[i] == 'b') {
        i += 1;
    }

    if (i >= ident.len) return false;
    while (i < ident.len) {
        if (!isDigit(ident[i])) return false;
        i += 1;
    }

    return true;
}
