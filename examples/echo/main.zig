//! a basic echo example
const std = @import("std");
const lambda = @import("lambda");
const log = std.log.scoped(.demo);

pub fn main() !void {
    var wrapped = lambda.wrap(handler);
    try lambda.run(null, wrapped.handler());
}

pub const Error = error{Demo};

fn handler(allocator: std.mem.Allocator, context: lambda.Context, event: []const u8) ![]const u8 {
    _ = context;
    _ = allocator;
    // 👇 to trigger a failed invocation, simply return an error
    //return error.Demo;
    // 👇 echo back the event
    return event;
}
