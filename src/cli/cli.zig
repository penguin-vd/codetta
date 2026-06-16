const std = @import("std");
const Allocator = std.mem.Allocator;

// Each subcommand owns its own flags, so adding a backend is just a new
// case here plus a function in `commands.zig`.

pub const InputOptions = struct {
    input_path: []const u8,
};

pub const MidiOptions = struct {
    input_path: []const u8,
    output_path: []const u8,
};

pub const WebOptions = struct {
    input_path: []const u8,
    output_path: []const u8,
};

pub const Command = union(enum) {
    help,
    midi: MidiOptions,
    web: WebOptions,
    inspect_ast: InputOptions,
    inspect_score: InputOptions,
    check: InputOptions,
};

pub const ParseError = error{
    MissingCommand,
    UnknownCommand,
    MissingInput,
    MissingValue,
    UnknownArgument,
    OutOfMemory,
};

pub const usage =
    \\Usage: codetta <command> <input.coda> [options]
    \\
    \\Commands:
    \\  midi <input> [-o <output>]   Compile to a Standard MIDI File
    \\  web <input> [-o <output>]    Compile to @tonejs/midi-style JSON
    \\  inspect-ast <input>          Print the parsed syntax tree
    \\  inspect-score <input>        Print the lowered Score IR
    \\  check <input>                Parse and lower without producing output
    \\
    \\Options:
    \\  -h, --help                   Show this help message
    \\
;

pub fn parse(allocator: Allocator, args: []const [:0]const u8) ParseError!Command {
    if (args.len == 0) return error.MissingCommand;

    const name = args[0];
    if (eql(name, "-h") or eql(name, "--help")) return .help;

    const rest = args[1..];
    if (eql(name, "midi")) return parseMidi(allocator, rest);
    if (eql(name, "web")) return parseWeb(allocator, rest);
    if (eql(name, "inspect-ast")) return .{ .inspect_ast = try parseInputOnly(rest) };
    if (eql(name, "inspect-score")) return .{ .inspect_score = try parseInputOnly(rest) };
    if (eql(name, "check")) return .{ .check = try parseInputOnly(rest) };

    return error.UnknownCommand;
}

const InputOutput = struct {
    input_path: []const u8,
    output_path: []const u8,
};

// Shared "<input> [-o <output>]" parsing for file-producing backends. When
// `-o` is omitted, the output path is the input with its extension swapped
// for `ext`.
fn parseInputOutput(allocator: Allocator, args: []const [:0]const u8, ext: []const u8) ParseError!InputOutput {
    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (eql(arg, "-o") or eql(arg, "--output")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            output_path = args[i];
            continue;
        }

        if (arg.len > 0 and arg[0] == '-') return error.UnknownArgument;
        if (input_path != null) return error.UnknownArgument;
        input_path = arg;
    }

    const input = input_path orelse return error.MissingInput;
    const output = output_path orelse try deriveOutputPath(allocator, input, ext);

    return .{ .input_path = input, .output_path = output };
}

fn parseMidi(allocator: Allocator, args: []const [:0]const u8) ParseError!Command {
    const io = try parseInputOutput(allocator, args, ".mid");
    return .{ .midi = .{ .input_path = io.input_path, .output_path = io.output_path } };
}

fn parseWeb(allocator: Allocator, args: []const [:0]const u8) ParseError!Command {
    const io = try parseInputOutput(allocator, args, ".json");
    return .{ .web = .{ .input_path = io.input_path, .output_path = io.output_path } };
}

fn parseInputOnly(args: []const [:0]const u8) ParseError!InputOptions {
    var input_path: ?[]const u8 = null;

    for (args) |arg| {
        if (arg.len > 0 and arg[0] == '-') return error.UnknownArgument;
        if (input_path != null) return error.UnknownArgument;
        input_path = arg;
    }

    return .{ .input_path = input_path orelse return error.MissingInput };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

// "song.coda" -> "song" + ext; inputs without the ".coda" extension just get
// ext appended.
fn deriveOutputPath(allocator: Allocator, input_path: []const u8, ext: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, input_path, ".coda"))
        input_path[0 .. input_path.len - ".coda".len]
    else
        input_path;

    return std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, ext });
}
