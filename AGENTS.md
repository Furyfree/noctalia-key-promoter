# Key Promoter for Hyprland + Noctalia

Hints the Hyprland shortcut when an app is opened or a workspace switched
without the keyboard. It only hints on evidence: keyboard binds announce
themselves on Hyprland's socket2 (runtime shadow binds, or the snippet), and
the launch wrapper marks shell launches.

## Map

- `plugin.toml`, `translations/en.json`: Noctalia manifest and setting labels.
  Every setting needs a `label_key`.
- `service.luau`: Noctalia service: socket2 stream, shadow binds through
  `hyprctl eval`, hints, IPC.
- `toast.luau`: the corner box, a persistent panel that never takes focus. The
  service opens and closes it and passes the hint through `noctalia.state`.
- `promoter.luau`: pure logic with no Noctalia calls, tested under plain Luau.
- `hypr/key-promoter.lua`: Hyprland Lua snippet (Lua 5.5, not Luau). Wraps
  `hl.bind` and writes the bind list to `$XDG_RUNTIME_DIR`.
- `bin/key-promoter-launch`: wrapper for Noctalia's
  `launch_apps_custom_command`; sends the `ui-launch` marker.
- `tests/`: `*_test.luau` run with `luau`, `*_test.lua` with `lua`,
  `*_test.sh` with `sh`.

## Rules

- A snippet error must never cost the user a bind: wrap bookkeeping in `pcall`.
- The snippet passes `description` through to `hl.bind` unchanged.
- Hyprland 0.56 with a Lua config: send markers with
  `hyprctl dispatch 'hl.dsp.event("…")'`; `hyprctl dispatch event` fails.
- Shadow binds run after the real bind, so their marker follows its effect:
  workspace changes wait `SETTLE_MS` before a decision.
- The corner box is a `noctalia-panel` layer: tell the tracker before opening
  or closing it, or its events count as the user's.

## Verify

`nix develop -c just check`. A login session test is still needed for
behaviour on the desktop.
