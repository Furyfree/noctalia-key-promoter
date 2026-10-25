#!/bin/sh
# Run from the repository root: sh tests/service_test.sh
# luau cannot require a Noctalia service, so join the fake host, the service and
# the cases into one script next to promoter.luau and run that.
set -eu

script=.service_test.luau
trap 'rm -f -- "$script"' EXIT
{
    cat tests/service_stub.luau
    # luau resolves "./promoter"; Noctalia wants the file name.
    sed 's|require("./promoter.luau")|require("./promoter")|' service.luau
    cat tests/service_cases.luau
} > "$script"
luau "$script"
