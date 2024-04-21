//! zig [lambda runtime](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html)
//!
//! A library for building zig aws lambda functions
//!
//!
//! ```
//! const lambda = @import("lambda");
//! const std = @import("std");
//!
//! pub fn main() !void {
//!   var wrapped = lambda.wrap(handler);
//!   try lambda.run(null, wrapped.handler());
//! }
//!
//! fn handler(allocator: std.mem.Allocator, ctx: lambda.Context, event: []const u8) anyerror![]const u8 {
//!     _ = allocator;
//!     return event;
//! }
//! ```
const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.lambda);

/// Per-request context data. An instance of this is passed to every lambda invocation
pub const Context = struct {
    /// The request ID, which identifies the request that triggered the function invocation.
    request_id: []const u8,
    /// The date that the function times out in Unix time milliseconds.
    deadline_ms: u64 = 0,
    /// The ARN of the Lambda function, version, or alias that's specified in the invocation.
    invoked_function_arn: []const u8 = "unknown",
    /// The AWS X-Ray tracing header.
    trace_id: []const u8 = "unknown",

    fn remaining_time_ms(self: *@This()) u64 {
        return std.time.milliTimestamp() - self.deadline_ms();
    }
};

/// The type of a lambda function handler
/// Currently accepting an allocator, request context, and bytes associated with event and error union with bytes returned in response
pub fn Handler(
    comptime Ctx: type,
    comptime handleFn: fn (context: Ctx, std.mem.Allocator, ctx: Context, event: []const u8) anyerror![]const u8,
) type {
    return struct {
        context: Ctx,
        pub fn handle(self: *@This(), allocator: std.mem.Allocator, ctx: Context, event: []const u8) anyerror![]const u8 {
            return handleFn(self.context, allocator, ctx, event);
        }
    };
}

/// Wraps a free standing const fn handler in a type which implements the Handle interface. This exists as
/// convenience for generating a handler type from a fn.
///
pub fn wrap(f: *const fn (std.mem.Allocator, Context, []const u8) anyerror![]const u8) Wrap() {
    return .{ .f = f };
}

/// A type which is intended to wrap a const fn handler function
pub fn Wrap() type {
    return struct {
        f: *const fn (std.mem.Allocator, Context, []const u8) anyerror![]const u8,
        const Self = @This();
        pub const Wrapped = Handler(*Self, handle);
        pub fn handler(self: *Self) Wrapped {
            return .{ .context = self };
        }

        pub fn handle(self: *Self, allocator: std.mem.Allocator, ctx: Context, event: []const u8) anyerror![]const u8 {
            return self.f(allocator, ctx, event);
        }
    };
}

/// Creates a new runtime and drives lambda event loop, reporting back responses and error
/// to the underlying lambda execution environment.
///
/// Use as follows, create a zig exe named `bootstrap` with an entrypoint that looks like this
///
/// ```
/// const lambda = @import("lambda");
/// const std = @import("std");
///
/// pub fn main() !void {
///   var wrapped = lambda.wrap(handler);
///   try lambda.run(null, wrapped.handler());
/// }
///
/// fn handler(allocator: std.mem.Allocator, ctx: lambda.Context, event: []const u8) anyerror![]const u8 {
///     _ = allocator;
///     return event;
/// }
/// ```
///
/// When an allocator is not provided the allocator used defaults to the std library `GeneralPurposeAllocator`
pub fn run(allocator: ?std.mem.Allocator, handler: anytype) !void {
    log.info("starting runtime", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = allocator orelse gpa.allocator();
    const env = (try Env.fromOs()).?;
    var runtime = try Runtime.init(alloc, env, .{ .allocator = alloc });
    defer runtime.deinit();
    var events = try runtime.events();
    defer events.deinit();
    var hand = handler;
    while (try events.next()) |event| {
        var e = event;
        defer e.deinit();
        log.debug("invoking handler", .{});
        const response = hand.handle(runtime.allocator, e.context(), e.data) catch |err| {
            log.warn("catching handler error {s}", .{@errorName(err)});
            e.err(@errorReturnTrace(), err) catch |err2| {
                log.err("failed to report error {s}", .{@errorName(err2)});
            };
            continue;
        };
        e.response(response) catch |err| {
            log.err("failed to send response {s}", .{@errorName(err)});
            continue;
        };
    }
}

/// Lambda runtime environment
///
/// see also the official [aws documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html#configuration-envvars-runtime)
const Env = struct {
    /// The host and port of the runtime API.
    runtime_api: []const u8 = "127.0.0.1:9001",
    ///  The name of the function.
    function_name: []const u8 = "unknown",
    /// The amount of memory available to the function in MB.
    function_memory_size: i32 = 128,
    // todo: add others

    /// Resolve runtime env from os
    pub fn fromOs() !?Env {
        return .{
            .runtime_api = std.posix.getenv("AWS_LAMBDA_RUNTIME_API").?,
            .function_name = std.posix.getenv("AWS_LAMBDA_FUNCTION_NAME").?,
            .function_memory_size = try std.fmt.parseInt(i32, std.posix.getenv("AWS_LAMBDA_FUNCTION_MEMORY_SIZE").?, 10),
        };
    }
};

/// Allows the delayed deinit of a formatted string passed to std.Uri parse
const FormattedUri = struct {
    allocator: std.mem.Allocator,
    formatted: []const u8,
    uri: std.Uri,

    fn parse(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !FormattedUri {
        const formatted = try std.fmt.allocPrint(allocator, fmt, args);
        const uri = try std.Uri.parse(formatted);
        return .{
            .allocator = allocator,
            .formatted = formatted,
            .uri = uri,
        };
    }

    fn deinit(self: *@This()) void {
        self.allocator.free(self.formatted);
        self.* = undefined;
    }
};

/// Lambda runtime execution
const Runtime = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    uri: []const u8,

    const Self = @This();

    /// initializes a new Runtime instance
    fn init(allocator: std.mem.Allocator, env: Env, client: std.http.Client) !Self {
        const uri = try std.fmt.allocPrint(allocator, "http://{s}/2018-06-01/runtime", .{env.runtime_api});
        log.debug("init runtime with uri {s}", .{uri});
        return .{ .allocator = allocator, .client = client, .uri = uri };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.uri);
        self.client.deinit();
        self.* = undefined;
    }

    // returns an iterator over lambda events
    fn events(self: *Self) !EventIterator {
        return EventIterator.init(self.allocator, self.client, self.uri);
    }
};

/// An iterator over lambda events
const EventIterator = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    next_uri: FormattedUri,
    uri: []const u8,

    const Self = @This();

    fn init(allocator: std.mem.Allocator, client: std.http.Client, uri: []const u8) !Self {
        const next_uri = try FormattedUri.parse(allocator, "{s}/invocation/next", .{uri});
        return .{ .allocator = allocator, .client = client, .next_uri = next_uri, .uri = uri };
    }

    fn deinit(self: *Self) void {
        log.warn("inside deiniting event iter...", .{});
        self.next_uri.deinit();
        self.* = undefined;
    }

    fn next(self: *Self) !?Event {
        log.debug("requesting next event", .{});
        // same as std client.fetch(...) default server_header_buffer
        var server_header_buffer: [16 * 1024]u8 = undefined;
        var req = try self.client.open(.GET, self.next_uri.uri, .{
            .server_header_buffer = &server_header_buffer,
        });
        defer {
            log.debug("next request deinit", .{});
            req.deinit();
        }
        try req.send();
        try req.finish();
        try req.wait();
        log.debug("recieved next event", .{});

        var headers = req.response.iterateHeaders();
        var request_id: []const u8 = undefined;
        var invoked_function_arn: []const u8 = undefined;
        var deadline_ms: u64 = undefined;
        var trace_id: []const u8 = undefined;
        while (headers.next()) |hdr| {
            if (std.ascii.eqlIgnoreCase("Lambda-Runtime-Aws-Request-Id", hdr.name)) {
                request_id = hdr.value;
            }
            if (std.ascii.eqlIgnoreCase("Lambda-Runtime-Deadline-Ms", hdr.name)) {
                deadline_ms = try std.fmt.parseInt(u64, hdr.value, 10);
            }
            if (std.ascii.eqlIgnoreCase("Lambda-Runtime-Invoked-Function-Arn", hdr.name)) {
                invoked_function_arn = hdr.value;
            }
            if (std.ascii.eqlIgnoreCase("Lambda-Runtime-Trace-Id", hdr.name)) {
                trace_id = hdr.value;
            }
        }

        const content_length = @as(usize, @intCast(req.response.content_length.?));
        var payload = try std.ArrayList(u8).initCapacity(self.allocator, content_length);
        defer payload.deinit();
        try payload.resize(content_length);
        // make a copy of the response data that we own
        const data = try payload.toOwnedSlice();
        errdefer self.allocator.free(data);
        _ = try req.readAll(data);
        log.debug("constructing event with data {s} and request id {s}", .{ data, request_id });
        return .{
            .allocator = self.allocator,
            .data = data,
            .request_id = try self.allocator.dupe(u8, request_id),
            .deadline_ms = deadline_ms,
            .invoked_function_arn = try self.allocator.dupe(u8, invoked_function_arn),
            .trace_id = try self.allocator.dupe(u8, trace_id),
            .client = self.client,
            .uri = self.uri,
        };
    }
};

/// An event recieved from aws that a function is to respond to
/// Unhandled failures are handled by the exported `run(...)` function
const Event = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    request_id: []const u8,
    deadline_ms: u64,
    invoked_function_arn: []const u8,
    trace_id: []const u8,
    client: std.http.Client,
    uri: []const u8,

    const Self = @This();

    fn deinit(self: *Self) void {
        log.debug("deinit event", .{});
        self.allocator.free(self.data);
        self.allocator.free(self.request_id);
        self.allocator.free(self.invoked_function_arn);
        self.allocator.free(self.trace_id);
        self.* = undefined;
    }

    fn context(self: *Self) Context {
        return .{ .request_id = self.request_id, .deadline_ms = self.deadline_ms, .invoked_function_arn = self.invoked_function_arn, .trace_id = self.trace_id };
    }

    /// respond to this event
    /// see the [aws lambda docs](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-response) for more info
    fn response(self: *Self, payload: []const u8) !void {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/invocation/{s}/response", .{ self.uri, self.request_id });
        defer self.allocator.free(url);
        const body = try self.allocator.dupe(u8, payload);
        defer self.allocator.free(body);
        log.debug("sending response", .{});
        // fixme. self.client segfaults on every other success. we really shouldn't need a new client on every response
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();
        _ = try client.fetch(.{
            .location = .{ .url = url },
            .payload = body,
        });
        log.debug("response complete", .{});
    }

    /// see the [aws lambda docs](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-invokeerror) for more info
    fn err(self: *Self, trace: ?*std.builtin.StackTrace, caught: anytype) !void {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/invocation/{s}/error", .{ self.uri, self.request_id });
        defer self.allocator.free(url);
        const body = if (trace) |_|
            // fixme: allocPrint hangs when printing trace
            try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "errorMessage": "{s}",
                \\  "errorType": "Runtime.UnknownReason",
                \\  "stackTrace": ["todo"]
                \\}}
            , .{@errorName(caught)})
        else
            try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "errorMessage": "{s}",
                \\  "errorType": "Runtime.UnknownReason",
                \\  "stackTrace": []
                \\}}
            , .{@errorName(caught)});
        defer self.allocator.free(body);
        log.debug("sending error report", .{});
        _ = try self.client.fetch(.{
            .location = .{ .url = url },
            .payload = body,
            .extra_headers = &[_]std.http.Header{
                .{
                    .name = "Lambda-Runtime-Function-Error-Type",
                    .value = "Runtime.UnknownReason",
                },
            },
        });
        log.debug("error report complete", .{});
    }
};

test "Env defaults" {
    const env: Env = .{};
    try testing.expectEqualStrings("127.0.0.1:9001", env.runtime_api);
}

test "Runtime structure" {
    const allocator = std.testing.allocator;
    var runtime = try Runtime.init(allocator, .{}, .{ .allocator = allocator });
    defer runtime.deinit();
    try testing.expectEqualStrings("http://127.0.0.1:9001/2018-06-01/runtime", runtime.uri);
}

test "Events iterator" {
    const allocator = std.testing.allocator;
    var runtime = try Runtime.init(allocator, .{}, .{ .allocator = allocator });
    defer runtime.deinit();
    var events = try runtime.events();
    defer events.deinit();
    try testing.expectEqualStrings("/2018-06-01/runtime/invocation/next", events.next_uri.uri.path.percent_encoded);
}

test "Event structure" {
    const allocator = std.testing.allocator;
    const data =
        \\{"foo":"bar"}
    ;

    var event: Event = .{ .allocator = allocator, .data = try allocator.dupe(u8, data), .deadline_ms = 0, .request_id = try allocator.dupe(u8, "12345"), .trace_id = try allocator.dupe(u8, "trace_id"), .invoked_function_arn = try allocator.dupe(u8, "invoked_function_arn"), .client = .{ .allocator = allocator }, .uri = "http://127.0.0.1:9001/2018-06-01/runtime/invocation" };
    defer event.deinit();
    try testing.expectEqualStrings(data, event.data);
    try testing.expectEqualStrings("12345", event.request_id);
    try testing.expectEqualStrings("http://127.0.0.1:9001/2018-06-01/runtime/invocation", event.uri);
}

test "wrapped handler" {
    const allocator = std.testing.allocator;
    var wrapped = wrap(demo);
    var handler = wrapped.handler();
    try testing.expectEqualStrings("test", try handler.handle(allocator, .{ .request_id = "123" }, "test"));
}

test "custom handler" {
    const Echo = struct {
        const Self = @This();
        const EchoHandler = Handler(*Self, handle);
        pub fn handler(self: *Self) EchoHandler {
            return .{ .context = self };
        }
        pub fn handle(self: *Self, allocator: std.mem.Allocator, ctx: Context, event: []const u8) anyerror![]const u8 {
            _ = self;
            _ = allocator;
            _ = ctx;
            return event;
        }
    };
    const allocator = std.testing.allocator;
    var custom = Echo{};
    var handler = custom.handler();
    try testing.expectEqualStrings("test", try handler.handle(allocator, .{ .request_id = "123" }, "test"));
}

fn demo(allocator: std.mem.Allocator, context: Context, event: []const u8) ![]const u8 {
    _ = allocator;
    _ = context;
    //return error.Demo;
    return event;
}
