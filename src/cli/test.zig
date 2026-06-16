const std = @import("std");
const testing = std.testing;

const Cli = @import("cli.zig");

test "midi command derives the output path from the input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const command = try Cli.parse(arena.allocator(), &.{ "midi", "song.coda" });

    try testing.expect(command == .midi);
    try testing.expectEqualStrings("song.coda", command.midi.input_path);
    try testing.expectEqualStrings("song.mid", command.midi.output_path);
}

test "midi command appends .mid when the input has no .coda extension" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const command = try Cli.parse(arena.allocator(), &.{ "midi", "tunes/melody" });
    try testing.expectEqualStrings("tunes/melody.mid", command.midi.output_path);
}

test "midi command honors an explicit -o/--output" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const short = try Cli.parse(arena.allocator(), &.{ "midi", "song.coda", "-o", "out/song.mid" });
    try testing.expectEqualStrings("out/song.mid", short.midi.output_path);

    const long = try Cli.parse(arena.allocator(), &.{ "midi", "song.coda", "--output", "out/song.mid" });
    try testing.expectEqualStrings("out/song.mid", long.midi.output_path);
}

test "midi command reports a missing -o/--output value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.MissingValue, Cli.parse(arena.allocator(), &.{ "midi", "song.coda", "-o" }));
}

test "web command derives a .json output path and honors -o" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const derived = try Cli.parse(arena.allocator(), &.{ "web", "song.coda" });
    try testing.expect(derived == .web);
    try testing.expectEqualStrings("song.json", derived.web.output_path);

    const explicit = try Cli.parse(arena.allocator(), &.{ "web", "song.coda", "-o", "out/song.json" });
    try testing.expectEqualStrings("out/song.json", explicit.web.output_path);
}

test "inspect-ast, inspect-score and check take a single input path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const ast_cmd = try Cli.parse(arena.allocator(), &.{ "inspect-ast", "song.coda" });
    try testing.expect(ast_cmd == .inspect_ast);
    try testing.expectEqualStrings("song.coda", ast_cmd.inspect_ast.input_path);

    const score_cmd = try Cli.parse(arena.allocator(), &.{ "inspect-score", "song.coda" });
    try testing.expect(score_cmd == .inspect_score);
    try testing.expectEqualStrings("song.coda", score_cmd.inspect_score.input_path);

    const check_cmd = try Cli.parse(arena.allocator(), &.{ "check", "song.coda" });
    try testing.expect(check_cmd == .check);
    try testing.expectEqualStrings("song.coda", check_cmd.check.input_path);
}

test "help flags short-circuit parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expect(try Cli.parse(arena.allocator(), &.{"-h"}) == .help);
    try testing.expect(try Cli.parse(arena.allocator(), &.{"--help"}) == .help);
}

test "missing command is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.MissingCommand, Cli.parse(arena.allocator(), &.{}));
}

test "unknown command is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.UnknownCommand, Cli.parse(arena.allocator(), &.{ "wat", "song.coda" }));
}

test "missing input is reported for every subcommand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.MissingInput, Cli.parse(arena.allocator(), &.{"midi"}));
    try testing.expectError(error.MissingInput, Cli.parse(arena.allocator(), &.{"web"}));
    try testing.expectError(error.MissingInput, Cli.parse(arena.allocator(), &.{"inspect-ast"}));
    try testing.expectError(error.MissingInput, Cli.parse(arena.allocator(), &.{"inspect-score"}));
    try testing.expectError(error.MissingInput, Cli.parse(arena.allocator(), &.{"check"}));
}

test "unknown flags and extra positionals are reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.UnknownArgument, Cli.parse(arena.allocator(), &.{ "midi", "song.coda", "--bogus" }));
    try testing.expectError(error.UnknownArgument, Cli.parse(arena.allocator(), &.{ "check", "one.coda", "two.coda" }));
}
