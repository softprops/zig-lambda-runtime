//! a function url example
//! see also https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html
//! see also https://docs.aws.amazon.com/lambda/latest/dg/urls-invocation.html#urls-payloads
const std = @import("std");
const lambda = @import("lambda");
const log = std.log.scoped(.demo);

const ApiGatewayEvent = struct {
    headers: [][]const u8,
    rawPath: []const u8,
};

pub fn main() !void {
    var wrapped = lambda.wrap(handler);
    try lambda.run(null, wrapped.handler());
}

pub const Error = error{Demo};

fn handler(allocator: std.mem.Allocator, context: lambda.Context, event: []const u8) ![]const u8 {
    _ = allocator;
    log.debug("context {any}", .{context});
    log.debug("event {s}", .{event});
    //const data = try std.json.parseFromSlice(ApiGatewayEvent, allocator, event, .{ .ignore_unknown_fields = true });
    //defer data.deinit();
    //log.debug("data {any}", .{data});

    // 👇 lambda will imply 200 response with application/json content type when returning a json string
    return 
    \\{
    \\  "message": "hello world"
    \\}
    ;
}
