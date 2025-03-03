const jack = @import("jack.zig");
const std = @import("std");

const Client = jack.client.JackClient;
const Hardware = jack.Hardware;

const log = std.log.scoped(.jack);

pub fn testJack() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const allocator = gpa.allocator();

    const client = jack.client.JackClient.init(allocator, .{
        .client_name = "delia",
        .server_name = null,
    }) catch |err| {
        log.err("Failed to init jack client: {!}", .{err});
        return;
    };

    defer client.deinit();

    for (client.hardware.playbacks) |playback| {
        log.info("Playback: {s}", .{playback.name});
    }

    client.registerPort("test", .playback);
}
