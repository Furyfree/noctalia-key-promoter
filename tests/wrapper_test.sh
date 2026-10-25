#!/bin/sh
# Run from the repository root: sh tests/wrapper_test.sh
# Fake hyprctl and uwsm-app record what the launch wrapper passes them.
set -eu

fake=$(mktemp -d)
trap 'rm -rf -- "$fake"' EXIT

cat > "$fake/hyprctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_DIR/hyprctl.args"
EOF
cat > "$fake/uwsm-app" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_DIR/uwsm-app.args"
EOF
chmod +x "$fake/hyprctl" "$fake/uwsm-app"

fail() {
    echo "wrapper_test: $1" >&2
    exit 1
}

launch() {
    rm -f "$fake"/*.args
    FAKE_DIR=$fake PATH="$fake:$PATH" sh key-promoter/bin/key-promoter-launch "$@"
}

# The marker names the program, then the app starts with its arguments unchanged.
launch /usr/bin/zeditor --new "two words"
[ "$(cat "$fake/hyprctl.args")" = "$(printf 'dispatch\nhl.dsp.event("keypromoter:ui-launch,zeditor")')" ] ||
    fail "marker command: $(cat "$fake/hyprctl.args")"
[ "$(cat "$fake/uwsm-app.args")" = "$(printf -- '--\n/usr/bin/zeditor\n--new\ntwo words')" ] ||
    fail "app arguments: $(cat "$fake/uwsm-app.args")"

# Characters that could break the Lua string never reach it.
launch 'evil")os.exit()--' arg
[ "$(cat "$fake/hyprctl.args")" = "$(printf 'dispatch\nhl.dsp.event("keypromoter:ui-launch,evilos.exit--")')" ] ||
    fail "unsafe name: $(cat "$fake/hyprctl.args")"

# The app still starts when hyprctl fails.
cat > "$fake/hyprctl" <<'EOF'
#!/bin/sh
exit 1
EOF
launch signal-desktop
[ -f "$fake/uwsm-app.args" ] || fail "app did not start after hyprctl failed"

echo "wrapper_test: ok"
