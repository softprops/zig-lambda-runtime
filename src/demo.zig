const std = @import("std");
const lambda = @import("lambda.zig");
const log = std.log.scoped(.demo);

pub fn main() !void {
    var wrapped = lambda.wrap(handler);
    try lambda.run(null, wrapped.handler());
}

pub const Error = error{Demo};

fn handler(allocator: std.mem.Allocator, context: lambda.Context, event: []const u8) ![]const u8 {
    _ = allocator;
    log.debug("context {any}", .{context});
    //return error.Demo;
    return event;
}
