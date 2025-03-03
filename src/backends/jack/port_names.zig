const std = @import("std");

pub const max_n_ports: usize = 36;

pub const playback = createPorts("INPUT_TO_PLAYBACK");
pub const capture = createPorts("OUTPUT_FROM_CAPTURE");

pub fn maxReached(n: usize) bool {
    return n >= max_n_ports;
}

fn createPorts(comptime port_name: []const u8) [max_n_ports][]const u8 {
    var results: [max_n_ports][]const u8 = undefined;
    for (0..max_n_ports) |i| {
        if (i + 1 < 10) {
            const str = std.fmt.comptimePrint("{s}_0{d}", .{ port_name, i + 1 });
            results[i] = str;
            continue;
        }

        const str = std.fmt.comptimePrint("{s}_{d}", .{ port_name, i + 1 });
        results[i] = str;
    }

    return results;
}
