# zig lambda runtime

[![Main](https://github.com/softprops/zig-lambda-runtime/actions/workflows/main.yml/badge.svg)](https://github.com/softprops/zig-lambda-runtime/actions/workflows/main.yml)

A zig implementation of the [aws lambda runtime](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html)

Below is an example echo lambda that echo's the event that triggered it.

```zig
const std = @import("std");
const lambda = @import("lambda.zig");

pub fn main() anyerror!void {
    var wrapped = lambda.wrap(handler);
    try lambda.run(null, wrapped.handler());
}

fn handler(allocator: std.mem.Allocator, context: lambda.Context, event: []const u8) ![]const u8 {
    _ = allocator;
    _ = context;
    return event;
}
```
