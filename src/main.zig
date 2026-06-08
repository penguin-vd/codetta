const std = @import("std");

const Cli = @import("cli/cli.zig");
const commands = @import("commands.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    const command = Cli.parse(allocator, args[1..]) catch |err| {
        std.debug.print("error: {s}\n\n{s}", .{ @errorName(err), Cli.usage });
        return;
    };

    switch (command) {
        .help => std.debug.print("{s}", .{Cli.usage}),
        .midi => |options| try commands.midi(allocator, init.io, options),
        .inspect_ast => |options| try commands.inspectAst(allocator, init.io, options),
        .inspect_score => |options| try commands.inspectScore(allocator, init.io, options),
        .check => |options| try commands.check(allocator, init.io, options),
    }
}
