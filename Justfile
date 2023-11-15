# to use this `brew install just` and run `just`

[private]
default:
  @just --list --list-heading $'Available recipes: \n'

# run tests
test:
    @zig build test --summary all

# format sources
fmt:
    @zig fmt src

# build and package demo lambda for deployment
package:
    @zig build echo-example -Dtarget=aarch64-linux --summary all
    @zip -jq lambda.zip zig-out/bin/bootstrap

# deploy demo lambda
deploy: package
    @cd infra && sam deploy

# sync demo lambda code
sync: package
    @cd infra && sam sync

doc:
    @zig build-lib src/lambda.zig -femit-docs