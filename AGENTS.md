# Key Promoter for Hyprland + Noctalia

Hints the Hyprland shortcut when an app is opened or a workspace switched
without the keyboard. It only hints on evidence: keyboard binds announce
themselves on Hyprland's socket2 (runtime shadow binds, or the snippet), and
the launch wrapper marks shell launches.

## Map

The repo is a Noctalia git plugin source: `catalog.toml` at the root indexes
the plugin, which lives in `key-promoter/` (the store's folder layout). Keep
the catalog row in step with `plugin.toml` (version, `plugin_api`, metadata).
Paths below are inside `key-promoter/` unless they start with `tests/`.

- `plugin.toml`, `translations/en.json`: Noctalia manifest and setting labels.
  Every setting needs a `label_key`.
- `README.md`, `thumbnail.webp`: the plugin's store page and card.
- `service.luau`: Noctalia service: socket2 stream, shadow binds through
  `hyprctl eval`, hints, IPC.
- `toast.luau`: the corner box, drawn by three persistent panels (`hint-box-1`..
  `hint-box-3`, one per row count, since persistent panels have a fixed height).
  The service opens the one that fits, new before old, and passes the hints
  through `noctalia.state`. The swap can blink faintly. Once Noctalia supports
  `height = "content"` for persistent panels (`panel-content-height`, API 42,
  unreleased and not yet for persistent panels), replace the three with one
  panel that fits its rows.
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
