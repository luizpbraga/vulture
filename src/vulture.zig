/// This File introduce some abstraction on zig http module
/// for facilitate the use.
const std = @import("std");
const net = std.net;
const http = std.http;
const sw = std.mem.startsWith;
const eql = std.mem.eql;

const Zure = struct {
    const RouteFunc = *const fn (*Context) anyerror!void;

    const Route = struct {
        method: http.Method,
        handleFunc: RouteFunc,
    };

    const Context = struct {
        req: *http.Server.Request,
        res: *http.Server.Response,
        params: ?std.StringHashMap([]const u8) = null,
        arena: std.heap.ArenaAllocator,

        // TODO parse params
        fn init(child_alloc: std.mem.Allocator, req: *http.Server.Request, res: *http.Server.Response) Context {
            return .{
                .res = res,
                .req = req,
                .arena = std.heap.ArenaAllocator.init(child_alloc),
            };
        }

        fn deinit(ctx: *Context) void {
            ctx.arena.deinit();
        }

        fn send(c: *Context, string: []const u8) !void {
            c.res.transfer_encoding = .{ .content_length = string.len };
            try c.res.headers.append("content-type", "text/plain");
            try c.res.headers.append("connection", "close");
            try c.res.send();
            try c.res.writeAll(string);
        }

        fn sendJson(c: *Context, json_struct: anytype) !void {
            const allocator = c.arena.allocator();

            const json_string = try std.json.stringifyAlloc(allocator, json_struct, .{});
            errdefer allocator.free(json_string);
            c.res.transfer_encoding = .{ .content_length = json_string.len };
            try c.res.headers.append("content-type", "application/json");
            try c.res.headers.append("connection", "close");
            try c.res.send();
            try c.res.writeAll(json_string);
        }

        fn sendStatus(c: *Context, status: http.Status) !void {
            c.res.status = status;
            try c.res.headers.append("connection", "close");
            try c.res.send();
        }

        fn setStatus(c: *Context, status: http.Status) *Context {
            c.res.status = status;
            return c;
        }

        fn parseParams(c: *Context) !?std.StringHashMap([]const u8) {
            // /route?
            const target = c.req.target;

            var n = std.mem.count(u8, target, "?");

            if (n > 1) return error.ParseError1;
            if (n == 0 or n > 1) return null;

            const allocator = c.arena.allocator();

            var params = std.StringHashMap([]const u8).init(allocator);
            n = std.mem.indexOf(u8, c.target, "?").? + 1;

            var iter = std.mem.tokenizeScalar(u8, target[n..], "&");
            while (iter.next()) |param| {
                n = std.mem.indexOf(u8, param, "=");
                const name = param[0..n];
                const value = param[n + 1 ..];
                try params.put(name, value);
            }

            return params;
        }
    };

    server: http.Server,
    ally: std.mem.Allocator,
    routes: std.StringHashMap(Route),

    fn init(ally: std.mem.Allocator) Zure {
        return .{
            .ally = ally,
            .server = http.Server.init(ally, .{ .reuse_port = true, .reuse_address = true }),
            .routes = std.StringHashMap(Route).init(ally),
        };
    }

    fn deinit(self: *Zure) void {
        self.server.deinit();
        self.routes.deinit();
    }

    fn newRoute(self: *Zure, method: http.Method, target: []const u8, handleFunc: RouteFunc) !void {
        try self.routes.put(target, .{ .method = method, .handleFunc = handleFunc });
    }

    fn get(self: *Zure, target: []const u8, handleFunc: RouteFunc) !void {
        try self.routes.put(target, .{ .method = .GET, .handleFunc = handleFunc });
    }

    fn post(self: *Zure, target: []const u8, handleFunc: RouteFunc) !void {
        try self.routes.put(target, .{ .method = .POST, .handleFunc = handleFunc });
    }

    fn listen(self: *@This(), address: []const u8, port: u16) !void {
        const addr = try net.Address.parseIp4(address, port);

        try self.server.listen(addr);

        outer: while (true) {
            var response = try self.server.accept(.{ .allocator = self.ally });
            defer response.deinit();

            while (response.reset() != .closing) {
                try response.wait();

                const route = self.routes.get(response.request.target) orelse {
                    response.status = .bad_request;
                    try response.headers.append("connection", "close");
                    try response.send();
                    try response.finish();
                    break :outer;
                };

                var c = Zure.Context.init(self.ally, &response.request, &response);
                defer c.deinit();

                try route.handleFunc(&c);
                try response.finish();
            }
        }
    }
};

fn testRoutGetSend(c: *Zure.Context) anyerror!void {
    if (c.req.headers.contains("Authorization")) {
        std.debug.print("ok", .{});
    }
    try c.send("Hello Word");
}

fn testRoutGetSendJson(c: *Zure.Context) anyerror!void {
    if (c.req.headers.contains("Authorization")) {
        std.debug.print("ok", .{});
    }
    try c.sendJson(.{ .msg = "Hello Word" });
}

fn testRoutGetBadRequestSendJson(c: *Zure.Context) anyerror!void {
    if (c.req.headers.contains("Authorization")) {
        std.debug.print("ok", .{});
    }
    try c.setStatus(.bad_request).sendJson(.{ .msg = "Bad Request" });
}

test "main" {
    const ally = std.testing.allocator;

    var app = Zure.init(ally);
    defer app.deinit();

    try app.newRoute(.GET, "/test1", testRoutGetSend);
    try app.newRoute(.GET, "/test2", testRoutGetSendJson);
    try app.newRoute(.GET, "/test3", testRoutGetBadRequestSendJson);

    try app.listen("0.0.0.0", 8080);
}

// pub fn main() !void {
//     // code
//
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const ally = gpa.allocator();
//     defer if (.leak == gpa.deinit()) @panic("LEAK");
//
//     var server = http.Server.init(ally, .{ .reuse_port = true, .reuse_address = true });
//     defer server.deinit();
//
//     const address = try net.Address.parseIp4("0.0.0.0", 8080);
//
//     try server.listen(address);
//
//     while (true) {
//         var response = try server.accept(.{ .allocator = ally });
//         defer response.deinit();
//
//         while (response.reset() != .closing) {
//             try response.wait();
//
//             std.debug.print("!{}\n", .{response.request.method});
//
//             if (response.request.headers.getFirstValue("Content-Type")) |content_type| {
//                 std.debug.print("?{s}\n", .{content_type});
//                 if (eql(u8, content_type, "application/json")) {
//                     try response.headers.append("connection", "close");
//                     try response.send();
//                     continue;
//                 }
//             }
//
//             if (!sw(u8, response.request.target, "/test")) {
//                 try response.headers.append("connection", "close");
//                 try response.send();
//                 continue;
//             }
//
//             const buff = try response.reader().readAllAlloc(ally, 100);
//             defer ally.free(buff);
//             std.debug.print("{s}", .{buff});
//
//             const server_body = "é nois";
//             response.transfer_encoding = .{ .content_length = server_body.len };
//             try response.headers.append("content-type", "text/plain");
//             try response.headers.append("connection", "close");
//             try response.send();
//             _ = try response.writeAll(server_body);
//             try response.finish();
//         }
//     }
// }
