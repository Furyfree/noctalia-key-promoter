# Key Promoter

Learn your Hyprland shortcuts. When you open an app from the launcher or switch
workspace by clicking the bar, a small box in the bottom-right corner shows the
key that does the same thing, like Key Promoter X in JetBrains IDEs. It uses
your own binds and their descriptions, and only speaks up when it has evidence
you did not use the keyboard.

## Plugin

| Field | Value |
| --- | --- |
| ID | `furyfree/key-promoter` |
| Entries | service: `service`; panel: `toast` |

## Requirements

- Hyprland 0.56 or newer with a Lua config (`hyprland.lua`).
- `hyprctl`, `socat` and `stdbuf` on `PATH`.
- Binds with a `description`. Workspace binds are recognised by descriptions
  ending in `workspace <name>`, such as "Switch to workspace 3".

## Usage

Enable **Key Promoter** under Settings → Plugins. Nothing else to set up.

- **App launches:** open an app from the launcher that has a bind, and the box
  shows that bind, for example `SUPER` `SHIFT` `Z` Open Zed ×2.
- **Workspace switches:** click a workspace on the bar, and the box shows the
  workspace key.

Pressing the shortcut itself never shows a hint. The `toast` panel is opened
and closed by the service; you do not open it yourself.

Preview the box:

```sh
noctalia msg plugin furyfree/key-promoter:service all show "SUPER + B|Open Brave browser"
```

### Optional extras

- **Better app matching:** `hypr/key-promoter.lua` records the command behind
  each bind. Copy or link it to `~/.config/hypr/conf.d/key-promoter.lua` and
  load it first in `hyprland.lua`, before any bind:

  ```lua
  pcall(require, "./conf.d/key-promoter.lua")
  ```

- **Dock and taskbar launches:** put `bin/key-promoter-launch` on `PATH` and
  set `launch_apps_custom_command = "key-promoter-launch $CMD"` under `[shell]`
  in Noctalia's config. It still starts apps through `uwsm-app`.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `app_launches` | `bool` | `true` | Hint when the launcher, dock or taskbar opens an app that has a bind. |
| `workspace_switches` | `bool` | `true` | Hint when the bar or mouse switches workspace. |
| `show_count` | `bool` | `true` | Show how often a shortcut was suggested (×N). |
| `notifications` | `bool` | `false` | Show hints as Noctalia notifications instead of the box. |
| `launch_window_ms` | `int` | `3000` | How long after a launch a new window counts, in milliseconds. |
| `cooldown_s` | `int` | `10` | Seconds before the same shortcut is suggested again. |
| `launcher_layers` | `string_list` | `noctalia-panel`, `noctalia-attached-panel` | Without the launch wrapper: layers whose closing arms a launch hint. |

The box's position and layer are set on the `toast` panel's row in the same
settings page.

## IPC

```sh
P=furyfree/key-promoter:service
noctalia msg plugin $P all show "SUPER + B|Open Brave browser"   # preview a hint
noctalia msg plugin $P all reload                                # reread binds
noctalia msg plugin $P all stats                                 # top 5 shortcuts, to the log
noctalia msg plugin $P all state                                 # status, to the log
noctalia msg plugin $P all reset                                 # clear counts
```

## Notes

- **Hidden binds:** while running, the plugin adds a copy of each keyboard bind
  with `hyprctl eval` that only sends an event telling it a key was pressed.
  Your binds work as before. The copies vanish on `hyprctl reload` and are
  added again. They have no description, so a keybind cheatsheet may list them
  as undescribed. With the snippet loaded, no copies are added.
- **Commands run:** `stdbuf -oL socat` on Hyprland's event socket,
  `hyprctl binds -j`, `hyprctl eval`, and `noctalia msg status` when the
  launch wrapper is not set up.
- **Files written:** `counts.json` in the plugin's data directory. The snippet
  writes its bind list to `$XDG_RUNTIME_DIR/hypr-key-promoter.tsv`.
- **No network access.**
- **Not detected:** actions that open no window, such as screenshots, and apps
  that steal focus without marking themselves urgent.

Inspired by Forrest Knight's
[Omarchy Key Promoter](https://github.com/ForrestKnight/omarchy-key-promoter).
