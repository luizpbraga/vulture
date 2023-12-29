const std = @import("std");
const Vulture = @import("Vulture");

fn testRoutGetSend(c: *Vulture.Context) anyerror!void {
    if (c.req.headers.contains("Authorization")) {
        std.debug.print("ok", .{});
    }
    try c.send("Hello Word");
}

fn testRoutGetSendJson(c: *Vulture.Context) anyerror!void {
    if (c.req.headers.contains("Authorization")) {
        std.debug.print("ok", .{});
    }
    try c.sendJson(.{ .msg = "Hello Word" });
}

fn testRoutGetBadRequestSendJson(c: *Vulture.Context) anyerror!void {
    if (c.req.headers.contains("Authorization")) {
        std.debug.print("ok", .{});
    }
    try c.setStatus(.bad_request).sendJson(.{ .msg = "Bad Request" });
}

pub fn main() !void {
    const ally = std.heap.page_allocator;

    var app = Vulture.init(ally);
    defer app.deinit();

    try app.newRoute(.GET, "/test1", testRoutGetSend);
    try app.newRoute(.GET, "/test2", testRoutGetSendJson);
    try app.newRoute(.GET, "/test3", testRoutGetBadRequestSendJson);

    try app.listen("0.0.0.0", 8080);
}

test "simple test" {}
