const std = @import("std");

const Parser = @import("parser/parser.zig");
const ast = @import("parser/ast.zig");
const Lower = @import("ir/lower.zig");
const score = @import("ir/score.zig");

pub fn main(init: std.process.Init) !void {
    const code =
        \\tempo 120
        \\time_signature 4/4
        \\
        \\chord Cmaj = [C4 E4 G4]
        \\chord Fmaj = [F4 A4 C5]
        \\
        \\phrase melody =
        \\  C4.quarter E4.quarter G4.quarter rest.quarter
        \\  @1.1 C3.whole
        \\
        \\  dynamic @0 p
        \\  dynamic @0.3 crescendo to f over 1 bar
        \\
        \\section verse =
        \\  track melody: melody transpose +5 reverse
        \\  track chords: Cmaj.whole Fmaj.whole
        \\
        \\song =
        \\  verse * 2
    ;

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    var parser = Parser.init(arena.allocator(), code);
    const program = parser.parseProgram() catch |err| {
        if (err == error.SyntaxError) {
            const diag = parser.diagnostic.?;
            std.debug.print("error: {d}:{d}: {s}\n", .{ diag.line, diag.column, diag.message });
            return;
        }
        return err;
    };

    for (program.top_level) |index| {
        printNode(program, index, 0);
    }

    std.debug.print("\n--- lowered score ---\n", .{});

    var lowerer = Lower.init(arena.allocator(), program);
    const result = lowerer.lower() catch |err| {
        std.debug.print("error: {s}\n", .{@errorName(err)});
        return;
    };
    printScore(result);
}

fn printScore(s: score.Score) void {
    std.debug.print("tempo {d}, {d}/{d}, {d} ticks/quarter\n", .{
        s.tempo_bpm, s.time_signature.numerator, s.time_signature.denominator, s.ticks_per_quarter,
    });

    for (s.tracks, 0..) |track, i| {
        std.debug.print("track {d}: \"{s}\"\n", .{ i, track.name });
    }

    for (s.notes) |n| {
        std.debug.print("  [{d:>5}..{d:<5}] track {d}  pitch {d:>3}  vel {d:>3}\n", .{
            n.start, n.start + n.duration, n.track, n.pitch, n.velocity,
        });
    }
}

fn printNode(program: ast.Program, index: ast.NodeIndex, indent: usize) void {
    switch (program.nodes[index]) {
        .tempo => |n| line(indent, "tempo {d}", .{n.bpm}),
        .time_signature => |n| line(indent, "time_signature {d}/{d}", .{ n.numerator, n.denominator }),

        .chord_def => |n| {
            line(indent, "chord_def \"{s}\"", .{n.name});
            for (n.notes) |pitched| {
                printIndent(indent + 1);
                printPitched(pitched);
                std.debug.print("\n", .{});
            }
        },

        .phrase_def => |n| {
            line(indent, "phrase_def \"{s}\"", .{n.name});
            for (n.body) |child| printNode(program, child, indent + 1);
        },

        .section_def => |n| {
            line(indent, "section_def \"{s}\"", .{n.name});
            for (n.tracks) |child| printNode(program, child, indent + 1);
        },

        .song_def => |n| {
            line(indent, "song_def", .{});
            for (n.items) |child| printNode(program, child, indent + 1);
        },

        .note => |n| {
            printIndent(indent);
            std.debug.print("note ", .{});
            printPitched(n.pitched);
            std.debug.print(" ", .{});
            printDuration(n.duration);
            std.debug.print("\n", .{});
        },

        .rest => |n| {
            printIndent(indent);
            std.debug.print("rest ", .{});
            printDuration(n.duration);
            std.debug.print("\n", .{});
        },

        .chord_ref => |n| {
            printIndent(indent);
            std.debug.print("chord_ref \"{s}\" ", .{n.name});
            printDuration(n.duration);
            std.debug.print("\n", .{});
        },

        .positioned => |n| {
            line(indent, "positioned @{d}.{d}", .{ n.position.bar, n.position.beat });
            printNode(program, n.target, indent + 1);
        },

        .dynamic_level => |n| line(indent, "dynamic_level @{d}.{d} {s}", .{ n.position.bar, n.position.beat, @tagName(n.level) }),

        .dynamic_shape => |n| line(indent, "dynamic_shape @{d}.{d} {s} to {s} over {d} bar(s)", .{
            n.position.bar, n.position.beat, @tagName(n.shape), @tagName(n.target), n.bars,
        }),

        .identifier => |n| line(indent, "identifier \"{s}\"", .{n.name}),

        .sequence => |n| {
            line(indent, "sequence", .{});
            for (n.items) |child| printNode(program, child, indent + 1);
        },

        .repeat => |n| {
            line(indent, "repeat x{d}", .{n.count});
            printNode(program, n.target, indent + 1);
        },

        .transform => |n| {
            printIndent(indent);
            std.debug.print("transform ", .{});
            switch (n.op) {
                .transpose => |amount| std.debug.print("transpose {d}\n", .{amount}),
                .reverse => std.debug.print("reverse\n", .{}),
                .augment => |factor| std.debug.print("augment x{d}\n", .{factor}),
                .diminish => |factor| std.debug.print("diminish x{d}\n", .{factor}),
            }
            printNode(program, n.target, indent + 1);
        },

        .track => |n| {
            line(indent, "track \"{s}\"", .{n.name});
            printNode(program, n.content, indent + 1);
        },
    }
}

fn line(indent: usize, comptime fmt: []const u8, args: anytype) void {
    printIndent(indent);
    std.debug.print(fmt ++ "\n", args);
}

fn printIndent(indent: usize) void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

fn printPitched(p: ast.Pitched) void {
    const accidental: []const u8 = switch (p.accidental) {
        .natural => "",
        .sharp => "#",
        .flat => "b",
    };
    std.debug.print("{c}{s}{d}", .{ pitchChar(p.pitch), accidental, p.octave });
}

fn pitchChar(p: ast.Pitch) u8 {
    return switch (p) {
        .c => 'C',
        .d => 'D',
        .e => 'E',
        .f => 'F',
        .g => 'G',
        .a => 'A',
        .b => 'B',
    };
}

fn printDuration(d: ast.Duration) void {
    std.debug.print("{s}", .{@tagName(d.kind)});
    if (d.dotted) std.debug.print(".dot", .{});
}
