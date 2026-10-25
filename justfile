# Run every check
check: test lint

# Unit tests for the plugin logic, the Hyprland snippet and the wrapper syntax
test:
    luau tests/promoter_test.luau
    sh tests/service_test.sh
    lua tests/snippet_test.lua
    sh -n bin/key-promoter-launch
    sh tests/wrapper_test.sh

# Cross-check declared settings against the plugin code
lint:
    noctalia plugins lint .
