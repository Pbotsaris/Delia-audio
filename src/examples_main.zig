//! Entry point for `zig build example -- <name> [args...]`. Each entry adapts the
//! command-line arguments to one example function; no name or an unknown one lists them.

const std = @import("std");
const graph = @import("core/graph");
const common = @import("core/common");
const build_options = @import("build_options");

// a backend module only exists when build.zig built it for this target
const alsa = if (build_options.alsa) @import("core/backends/alsa") else struct {};

const ExampleCommand = common.examples.Command;

pub const std_options = std.Options{
    .logFn = @import("logging.zig").logFn,
    .log_level = .debug,
};

const log = std.log.scoped(.main);

const ExampleModule = struct {
    name: []const u8,
    commands: []const ExampleCommand,
};

const groups = [_]ExampleModule{
    .{ .name = "graph", .commands = &graph.examples.commands },

    // alsa only on linux
} ++ (if (build_options.alsa) [_]ExampleModule{
    .{ .name = "alsa", .commands = &alsa.examples.commands },
} else [_]ExampleModule{});

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) return printUsage();

    for (groups) |group| {
        if (!std.mem.eql(u8, group.name, args[1])) continue;
        if (args.len < 3) return printGroup(group);

        for (group.commands) |command| {
            if (std.mem.eql(u8, command.name, args[2])) return command.run(args[3..]);
        }

        log.err("unknown example '{s} {s}'", .{ args[1], args[2] });
        printGroup(group);
        std.process.exit(1);
    }

    log.err("unknown module '{s}'", .{args[1]});
    printUsage();
    std.process.exit(1);
}

fn printUsage() void {
    std.debug.print("usage: zig build example -- <group> <name> [args...]\n", .{});
    for (groups) |group| printGroup(group);
}

fn printGroup(group: ExampleModule) void {
    std.debug.print("\n{s}:\n", .{group.name});
    for (group.commands) |command| std.debug.print("  {s} {s}\n", .{ command.name, command.usage });
}
