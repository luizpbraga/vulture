/// This File introduce some abstraction on zig http module
/// for facilitate the use.
const std = @import("std");
const net = std.net;
const http = std.http;
const sw = std.mem.startsWith;
const eql = std.mem.eql;

pub const Vulture = @This();

pub const RouteFunc = *const fn (*Context) anyerror!void;

pub const Route = struct {
    method: ?http.Method,
    handleFunc: RouteFunc,
};

pub const Context = struct {
    cookies: ?std.StringHashMap(Cookie) = null,
    params: ?std.StringHashMap([]const u8) = null,
    arena: std.heap.ArenaAllocator,
    res: *http.Server.Response,
    req: *http.Server.Request,

    // TODO parse params
    pub fn init(child_alloc: std.mem.Allocator, req: *http.Server.Request, res: *http.Server.Response) Context {
        return .{
            .res = res,
            .req = req,
            .arena = std.heap.ArenaAllocator.init(child_alloc),
        };
    }

    pub fn deinit(ctx: *Context) void {
        ctx.arena.deinit();
    }

    const Cookie = struct {
        http_only: bool,
        name: []const u8,
        value: []const u8,
        domain: []const u8,
        expires: usize,
    };

    const Accept = enum {
        @"text/html",
        @"application/json",
        @"application/xml",
        @"text/xml",
        @"image/jpeg",
        @"image/png",
        @"image/gif",
        @"*/*",
        @"text/*",
        @"application/*",
    };

    pub fn setCookie(c: *Context, cookie: *const Cookie) void {
        if (c.cookies) |cookies| {
            try cookies.put(cookie.name, cookie);

            if (!c.res.headers.contains("cookie")) {
                try c.res.headers.append("cookie", cookie.value);
            }

            @panic("Not Implemented");
        }

        c.cookies = std.AutoHashMap([]const u8, Cookie).init(c.arena.allocator());
    }

    pub fn bodyParse(c: *Context, comptime T: type) !T {
        const allocator = c.arena.allocator();

        const body = try c.res.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        errdefer allocator.free(body);

        return try std.json.parseFromSliceLeaky(T, allocator, body, .{});
    }

    /// caller owns the memory
    pub fn bodyToParsed(allocator: std.mem.Allocator, c: *Context, comptime T: type, buff: []u8) !std.json.Parsed(T) {
        try c.res.readAll(buff);
        return try std.json.parseFromSlice(T, allocator, buff, .{});
    }

    // matchs the accept header
    pub fn accept(c: *Context, offers: []const u8) Accept {
        _ = offers;
        _ = c;
        @panic("Not Implemented");
    }

    pub fn send(c: *Context, string: []const u8) !void {
        try c.res.headers.append("content-type", "application/txt");
        try c.write(string);
    }

    pub fn sendJson(c: *Context, json_struct: anytype) !void {
        const allocator = c.arena.allocator();
        const json_string = try std.json.stringifyAlloc(allocator, json_struct, .{});
        errdefer allocator.free(json_string);
        try c.res.headers.append("content-type", "application/json");
        try c.write(json_string);
    }

    /// Send the bytes and eval the header
    fn write(c: *Context, bytes: []const u8) !void {
        c.res.transfer_encoding = .{ .content_length = bytes.len };
        try c.res.headers.append("connection", "close");
        try c.res.send();
        try c.res.writeAll(bytes);
    }

    pub fn sendStatus(c: *Context, status: http.Status) !void {
        c.res.status = status;
        try c.res.headers.append("connection", "close");
        try c.res.send();
    }

    pub fn setStatus(c: *Context, status: http.Status) *Context {
        c.res.status = status;
        return c;
    }

    pub fn parseParams(c: *Context) !?std.StringHashMap([]const u8) {
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

pub fn init(ally: std.mem.Allocator) Vulture {
    return .{
        .ally = ally,
        .server = http.Server.init(ally, .{ .reuse_port = true, .reuse_address = true }),
        .routes = std.StringHashMap(Route).init(ally),
    };
}

pub fn deinit(self: *Vulture) void {
    self.server.deinit();
    self.routes.deinit();
}

pub const StaticConfig = struct {};

pub fn newStaticRoute(self: *Vulture, target: []const u8, path: []const u8, config: StaticConfig) !void {
    _ = config;
    _ = path;
    _ = target;
    _ = self;
    @panic("Not Implemented");
}

/// create a new route
pub fn new(self: *Vulture, method: http.Method, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = method, .handleFunc = handleFunc });
}

/// match a giver route. Can use any http method
pub fn match(self: *Vulture, route: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(route, .{ .method = null, .handleFunc = handleFunc });
}

pub fn get(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .GET, .handleFunc = handleFunc });
}

pub fn post(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .POST, .handleFunc = handleFunc });
}

pub fn head(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .HEAD, .handleFunc = handleFunc });
}

pub fn delete(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .DELETE, .handleFunc = handleFunc });
}

pub fn connect(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .CONNECT, .handleFunc = handleFunc });
}

pub fn options(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .OPTIONS, .handleFunc = handleFunc });
}

pub fn patch(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .PATCH, .handleFunc = handleFunc });
}

pub fn trace(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .TRACE, .handleFunc = handleFunc });
}

pub fn put(self: *Vulture, target: []const u8, handleFunc: RouteFunc) !void {
    try self.routes.put(target, .{ .method = .PUT, .handleFunc = handleFunc });
}

pub fn listen(self: *Vulture, address: []const u8, port: u16) !void {
    const addr = try net.Address.parseIp4(address, port);

    try self.server.listen(addr);

    std.log.info("Server listen to {s} at {};", .{ address, port });

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

            var c = Vulture.Context.init(self.ally, &response.request, &response);
            defer c.deinit();

            try route.handleFunc(&c);
            try response.finish();
        }
    }
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
