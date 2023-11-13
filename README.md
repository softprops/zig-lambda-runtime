# zig lambda runtime

[![Main](https://github.com/softprops/zig-lambda-runtime/actions/workflows/main.yml/badge.svg)](https://github.com/softprops/zig-lambda-runtime/actions/workflows/main.yml)

A zig implementation of the [aws lambda runtime](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html)

Below is an example echo lambda that echo's the event that triggered it.

```zig
const std = @import("std");
const lambda = @import("lambda.zig");

pub fn main() anyerror!void {
    // ❶ wrap a free standing fn in a handler type
    var wrapped = lambda.wrap(handler);
    // ❷ start the runtime with this handler
    try lambda.run(null, wrapped.handler());
}

fn handler(allocator: std.mem.Allocator, context: lambda.Context, event: []const u8) ![]const u8 {
    _ = allocator;
    _ = context;
    return event;
}
```

## deploying

This library targets the provided lambda runtime, prefer `provided.al2023` the latest, which assumes an executable named `bootstrap`.

To produce one of these, add the following in you in `build.zig``

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    //
    var exe = b.addExecutable(.{
        .name = "bootstrap",
        .root_source_file = .{ .path = "src/demo.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);
}
```

Then build an arm linux binary by running `zig build -Dtarget=aarch64-linux`

Package your function in zip file (aws lambda assumes a zip file) `zip -jq lambda.zip zig-out/bin/bootstrap`

Create a `template.yml` sam deployment template

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31

Resources:
  Function:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: provided.al2023
      Architectures:
        - arm64
      MemorySize: 128
      CodeUri: "lambda.zip"
      FunctionName: !Sub "${AWS::StackName}"
      Handler: handler
      Policies:
        - AWSLambdaBasicExecutionRole
```

Then run `sam deploy` to deploy it