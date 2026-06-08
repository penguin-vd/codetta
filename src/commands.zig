const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("parser/parser.zig");
const ast = @import("parser/ast.zig");
const Lower = @import("ir/lower.zig");
const ir = @import("ir/score.zig");
const Midi = @import("midi/midi.zig");
const Cli = @import("cli/cli.zig");
const inspect = @import("inspect/inspect.zig");

// One function per CLI subcommand, each wiring `parseSource`/`lowerProgram`
// to a backend or inspection utility.

pub fn midi(allocator: Allocator, io: std.Io, options: Cli.MidiOptions) !void {
    const program = try parseSource(allocator, io, options.input_path) orelse return;
    const result = try lowerProgram(allocator, program) orelse return;

    const bytes = try Midi.write(allocator, result);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = options.output_path, .data = bytes });
    std.debug.print("wrote {d} bytes to {s}\n", .{ bytes.len, options.output_path });
}

pub fn inspectAst(allocator: Allocator, io: std.Io, options: Cli.InputOptions) !void {
    const program = try parseSource(allocator, io, options.input_path) orelse return;
    inspect.printProgram(program);
}

pub fn inspectScore(allocator: Allocator, io: std.Io, options: Cli.InputOptions) !void {
    const program = try parseSource(allocator, io, options.input_path) orelse return;
    const result = try lowerProgram(allocator, program) orelse return;
    inspect.printScore(result);
}

pub fn check(allocator: Allocator, io: std.Io, options: Cli.InputOptions) !void {
    const program = try parseSource(allocator, io, options.input_path) orelse return;
    _ = try lowerProgram(allocator, program) orelse return;
    std.debug.print("{s}: ok\n", .{options.input_path});
}

// Both stages report their own diagnostics and return null on failure, so
// callers can just `orelse return` without repeating error text.

fn parseSource(allocator: Allocator, io: std.Io, input_path: []const u8) !?ast.Program {
    const code = std.Io.Dir.cwd().readFileAlloc(io, input_path, allocator, .unlimited) catch |err| {
        std.debug.print("error: could not read '{s}': {s}\n", .{ input_path, @errorName(err) });
        return null;
    };

    var parser = Parser.init(allocator, code);
    return parser.parseProgram() catch |err| {
        if (err == error.SyntaxError) {
            const diag = parser.diagnostic.?;
            std.debug.print("error: {s}:{d}:{d}: {s}\n", .{ input_path, diag.line, diag.column, diag.message });
            return null;
        }
        return err;
    };
}

fn lowerProgram(allocator: Allocator, program: ast.Program) !?ir.Score {
    var lowerer = Lower.init(allocator, program);
    return lowerer.lower() catch |err| {
        std.debug.print("error: {s}\n", .{@errorName(err)});
        return null;
    };
}
