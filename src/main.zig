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

fn testBodyParse(c: *Vulture.Context) anyerror!void {
    const T = struct {
        name: []const u8,
        pass: []const u8,
    };

    var obj = try c.bodyParse(T);

    std.debug.print("{}\n", .{obj});

    obj.name = "Vulture";

    try c.sendJson(obj);
}

pub fn main() !void {
    const ally = std.heap.page_allocator;

    var app = Vulture.init(ally);
    defer app.deinit();

    try app.new(.GET, "/test1", testRoutGetSend);
    try app.new(.GET, "/test2", testRoutGetSendJson);
    try app.get("/test3", testRoutGetBadRequestSendJson);
    try app.post("/test4", testBodyParse);

    try app.listen("0.0.0.0", 8080);
}

test "simple test" {}
