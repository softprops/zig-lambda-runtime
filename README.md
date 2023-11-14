<div align="center">
  ⚡ 🦎
</div>
<h1 align="center">
  zig lambda runtime
</h1>

<p align="center">
  An implementation of the <a href="https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html">aws lambda runtime</a> for <a href="https://ziglang.org/">zig</a>
</p>

[![Main](https://github.com/softprops/zig-lambda-runtime/actions/workflows/main.yml/badge.svg)](https://github.com/softprops/zig-lambda-runtime/actions/workflows/main.yml) ![License Info](https://img.shields.io/github/license/softprops/typeid-java)

## 🍬 features

- ⚡ small and fast

  Zig is impressively fast and small by default and can be made even faster and smaller with common `optimize` compilation flags.
  ❄ avg cold start duration `11ms` 💾 avg memory `10MB` ⚡ avg duration `1-2ms`

- 📦 painless and easy packaging

  Zig comes with a self-contained build tool that makes cross compilation for aws deployment targets painless `zig build -Dtarget=aarch64-linux -Doptimize={ReleaseFast,ReleaseSmall}`

Coming soon...

- streaming response support

  By default aws lambda buffers and then returns a single response to client but can be made streaming with opt in configuration

- event struct types

  At present it is up to lambda functions themselves to parse the and self declare event payloads structures and serialize responses. We would like to provide structs for common aws lambda event and response types to make that easier

## examples

Below is an example echo lambda that echo's the event that triggered it.

```zig
const std = @import("std");
const lambda = @import("lambda.zig");

pub fn main() anyerror!void {
    // 👇 wrap a free standing fn in a handler type
    var wrapped = lambda.wrap(handler);
    // 👇 start the runtime with this handler
    try lambda.run(null, wrapped.handler());
}

fn handler(allocator: std.mem.Allocator, context: lambda.Context, event: []const u8) ![]const u8 {
    _ = allocator;
    _ = context;
    return event;
}
```

## 📼 installing

## 🔧 building

This library targets the provided lambda runtime, prefer `provided.al2023` the latest, which assumes an executable named `bootstrap`.

To produce one of these, add the following in your `build.zig` file

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // 👇 create an execuable named `boostrap`. the name `bootstrap` is important.
    var exe = b.addExecutable(.{
        .name = "bootstrap",
        .root_source_file = .{ .path = "src/demo.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);
}
```

Then build an arm linux executable by running `zig build -Dtarget=aarch64-linux`

> We're using `aarch64` because we'll be deploying to the `arm64` lambda runtime architecture below

Package your function in zip file (aws lambda assumes a zip file) `zip -jq lambda.zip zig-out/bin/bootstrap`

## 🪂 deploying

The follow shows how to deploy a lambda using a standard aws deployment tool, [aws sam cli](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html).

Create a `template.yml` sam deployment template

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31

Resources:
  Function:
    Type: AWS::Serverless::Function
    Properties:
      # 👇 use the latest provided runtime
      Runtime: provided.al2023
      # 👇 deploy on arm architecture, it's more cost effective
      Architectures:
        - arm64
      MemorySize: 128
      # 👇 the zip file containing your `bootstrap` binary
      CodeUri: "lambda.zip"
      # 👇 required for zip but not used by the zig runtime, put any value you like here
      Handler: handler
      FunctionName: !Sub "${AWS::StackName}"
      Policies:
        - AWSLambdaBasicExecutionRole
```

Then run `sam deploy` to deploy it

## 🥹 for budding ziglings

Does this look interesting but you're new to zig and feel left out? No problem, zig is young so most us of our new are as well. Here are some resources to help get you up to speed on zig

- [the official zig website](https://ziglang.org/)
- [zig's one-page language documentation](https://ziglang.org/documentation/0.11.0/)
- [ziglearn](https://ziglearn.org/)
- [ziglings exercises](https://github.com/ratfactor/ziglings)

\- softprops 2023
