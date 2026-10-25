--!nonstrict
-- Run from the repository root: luau tests/promoter_test.luau
local promoter = require("../key-promoter/promoter")

local failures = 0
local function check(actual, expected, what)
    if actual ~= expected then
        failures += 1
        print(`FAIL {what}: expected {tostring(expected)}, got {tostring(actual)}`)
    end
end

local function bind(combo, description, command, classes, workspace)
    return { combo = combo, description = description, command = command or "", classes = classes or {}, workspace = workspace or "" }
end

local function comboOf(found)
    return found and found.combo or "none"
end

-- splitHint
local combo, description = promoter.splitHint("SUPER + B|Open Brave browser")
check(combo, "SUPER + B", "hint combo")
check(description, "Open Brave browser", "hint description")
combo, description = promoter.splitHint(" SUPER + 3 ")
check(combo, "SUPER + 3", "hint without description")
check(description, "", "missing description")

-- parseEvent
local event = promoter.parseEvent("openwindow>>5e24,4,dev.zed.Zed,main.rs, project")
check(event and event.class, "dev.zed.Zed", "openwindow class")
check(event and event.title, "main.rs, project", "title keeps its commas")
event = promoter.parseEvent("workspacev2>>13,8")
check(event and event.kind, "workspace", "workspace kind")
check(event and event.name, "8", "workspace name")
check((promoter.parseEvent("custom>>keypromoter:bind,SUPER + 3") or {}).combo, "SUPER + 3", "bind marker")
check((promoter.parseEvent("custom>>keypromoter:ui-launch,zeditor") or {}).program, "zeditor", "launch marker")
check((promoter.parseEvent("closelayer>>noctalia-panel") or {}).namespace, "noctalia-panel", "closelayer")
check((promoter.parseEvent("configreloaded>>") or {}).kind, "configreloaded", "configreloaded")
check(promoter.parseEvent("custom>>something-else"), nil, "foreign custom event")
check(promoter.parseEvent("activewindow>>a,b"), nil, "ignored event")

-- parseBindList
local parsed = promoter.parseBindList("SUPER + D\tOpen Discord\t\tvesktop,Vesktop\t\nSUPER + 8\tSwitch to local workspace 8\t\t\t\n")
check(#parsed, 2, "bind list rows")
check(parsed[1].classes[2], "Vesktop", "class list")
check(parsed[2].command, "", "empty command")

-- bindsFromHyprctl
local fallback = promoter.bindsFromHyprctl({
    { modmask = 65, key = "Z", description = "Open Zed", dispatcher = "__lua", arg = "" },
    { modmask = 64, key = "mouse:272", description = "Move", dispatcher = "__lua", mouse = true },
    { modmask = 0, key = "H", description = "Left", submap = "resize" },
    { modmask = 4, key = "T", description = "Terminal", dispatcher = "exec", arg = "ghostty" },
})
check(#fallback, 2, "fallback skips mouse and submap binds")
check(fallback[1].combo, "SUPER + SHIFT + Z", "fallback combo")
check(fallback[1].command, "", "lua bind has no command")
check(fallback[2].command, "ghostty", "exec bind keeps its command")

-- shadow binds
local combos = promoter.shadowCombos({
    { modmask = 65, key = "Z" },
    { modmask = 65, key = "Z" },
    { modmask = 64, key = "mouse:272", mouse = true },
    { modmask = 64, key = "mouse_down" },
    { modmask = 0, key = "H", submap = "resize" },
    { modmask = 0, key = "", catch_all = true },
    { modmask = 0, key = "", keycode = 107 },
    { modmask = 0, key = "XF86AudioMute" },
})
check(table.concat(combos, "|"), "SUPER + SHIFT + Z|SUPER + mouse_down|code:107|XF86AudioMute", "shadow combos")
local many = {}
for i = 1, 45 do
    table.insert(many, `SUPER + F{i}`)
end
local chunks = promoter.shadowCode(many)
check(#chunks, 3, "shadow code chunks")
check(string.find(chunks[1], '"SUPER + F20"', 1, true) ~= nil, true, "first chunk holds 20 combos")
check(string.find(chunks[1], '"SUPER + F21"', 1, true), nil, "second chunk starts at 21")
check(string.find(promoter.shadowCode({ 'A"B' })[1], '"A\\"B"', 1, true) ~= nil, true, "combos are quoted")

-- program
check(promoter.program("uwsm-app -- zeditor"), "zeditor", "uwsm-app")
check(promoter.program("uwsm app -- nautilus"), "nautilus", "uwsm app")
check(promoter.program("env GDK_BACKEND=x11 FOO=1 /usr/bin/Signal-Desktop --flag"), "signal-desktop", "env and path")
check(promoter.program("flatpak run --branch=stable com.example.App"), "com.example.app", "flatpak app id")
check(promoter.program("gtk-launch org.gnome.Nautilus.desktop"), "org.gnome.nautilus", "desktop id")
check(promoter.program("launch tui btop"), "btop", "launch tui")
check(promoter.program("systemd-run --user --scope app2unit -- obsidian"), "obsidian", "systemd-run and app2unit")
local _, args = promoter.program("uwsm-app -- 1password --quick-access")
check(args, 1, "argument count")
check(promoter.program(""), nil, "empty command")

-- suggestable
check(promoter.suggestable(bind("XF86AudioMute", "Mute")), false, "media key")
check(promoter.suggestable(bind("SUPER + mouse_down", "Next")), false, "wheel")
check(promoter.suggestable(bind("H", "Left")), false, "bare letter")
check(promoter.suggestable(bind("Print", "Capture")), true, "bare named key")

-- matchWindow on small lists
local binds = {
    bind("SUPER + SHIFT + P", "Focus or open 1Password", "uwsm-app -- 1password"),
    bind("CTRL + SHIFT + Space", "Open 1Password Quick Access", "uwsm-app -- 1password --quick-access"),
}
check(comboOf(promoter.matchWindow(binds, "1password", "")), "SUPER + SHIFT + P", "fewer arguments win")
binds = {
    bind("Print", "Capture screen region", "grim-region"),
    bind("SUPER + SHIFT + S", "Capture screen region", "grim-region"),
}
check(comboOf(promoter.matchWindow(binds, "grim-region", "")), "Print", "same action: fewest modifiers")
binds = {
    bind("SUPER + A", "Open A", "uwsm-app -- tool --a"),
    bind("SUPER + B", "Open B", "uwsm-app -- tool --b"),
}
check(comboOf(promoter.matchWindow(binds, "tool", "")), "none", "different actions tie: no hint")
binds = { bind("SUPER + T", "Open btop", "launch tui btop") }
check(comboOf(promoter.matchWindow(binds, "com.mitchellh.ghostty", "btop")), "none", "title words alone never hint")
binds = { bind("SUPER + X", "Open X", "my-wrapper --app x", { "org.example.X" }) }
check(comboOf(promoter.matchWindow(binds, "org.example.X", "")), "SUPER + X", "explicit class")

-- matchWorkspace
binds = {
    bind("SUPER + 8", "Switch to local workspace 8"),
    bind("SUPER + SHIFT + 8", "Move window to local workspace 8"),
    bind("SUPER + 0", "Switch to local workspace 10"),
    bind("SUPER + ALT + S", "Scratchpad", "", {}, "special"),
}
check(comboOf(promoter.matchWorkspace(binds, "8")), "SUPER + 8", "switch, not move")
check(comboOf(promoter.matchWorkspace(binds, "1")), "none", "workspace 1 is not workspace 10")
check(comboOf(promoter.matchWorkspace(binds, "special")), "SUPER + ALT + S", "explicit workspace")

-- The real desktop bind list, before the nix repo adds promote and target().
local desktop = promoter.parseBindList(require("./fixtures/desktop_binds"))
local windows = {
    { "dev.zed.Zed", "main.rs", "SUPER + SHIFT + Z" },
    { "md.obsidian.Obsidian", "Notes", "SUPER + SHIFT + O" },
    { "org.gnome.Nautilus", "Home", "SUPER + SHIFT + F" },
    { "signal", "Signal", "SUPER + SHIFT + G" },
    { "vesktop", "Discord", "SUPER + SHIFT + D" },
    { "vscodium", "VSCodium", "SUPER + SHIFT + V" },
    { "com.mitchellh.ghostty", "btop", "SUPER + Return" },
    { "com.onepassword.OnePassword", "1Password", "none" },
    { "com.t3tools.T3Code", "T3 Code (Beta)", "none" },
    { "brave-www.fotmob.com__-Default", "www.fotmob.com_/", "none" },
    { "org.mozilla.firefox", "Mozilla Firefox", "none" },
}
for _, case in windows do
    check(comboOf(promoter.matchWindow(desktop, case[1], case[2])), case[3], `real list: {case[1]}`)
end
check(comboOf(promoter.matchWorkspace(desktop, "8")), "SUPER + 8", "real list: workspace 8")
check(comboOf(promoter.matchWorkspace(desktop, "1")), "SUPER + 1", "real list: workspace 1")
check(comboOf(promoter.matchWorkspace(desktop, "10")), "SUPER + 0", "real list: workspace 10")

-- Tracker
local zedBinds = {
    bind("SUPER + SHIFT + Z", "Open Zed", "uwsm-app -- zeditor"),
    bind("SUPER + 3", "Switch to local workspace 3"),
}
local settings = {
    appLaunches = true, workspaceSwitches = true, launchWindowMs = 3000, cooldownMs = 10000,
    launcherLayers = { "noctalia-panel" }, wrapper = true,
}
local function feed(tracker, line, now)
    return tracker:handle(assert(promoter.parseEvent(line)), now)
end
local zedWindow = "openwindow>>1,1,dev.zed.Zed,Zed"
-- A workspace change, then the tick that decides once it has settled.
local function switch(tracker, now)
    feed(tracker, "workspacev2>>3,3", now)
    return tracker:tick(now + promoter.SETTLE_MS)
end

local t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 5000)
local hint = feed(t, zedWindow, 5500)
check(hint and hint.combo, "SUPER + SHIFT + Z", "shell launch hints")
check(hint and hint.description, "Open Zed", "hint description")

t = promoter.newTracker(settings, zedBinds, 0)
check(feed(t, zedWindow, 5500), nil, "window without a launch marker")

t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 5000)
check(feed(t, zedWindow, 9000), nil, "window after the launch window")

t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 5000)
feed(t, "custom>>keypromoter:bind,SUPER + 3", 5100)
check(feed(t, zedWindow, 5500), nil, "bind after the marker")

t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "custom>>keypromoter:bind,SUPER + SHIFT + Z", 1000)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 5000)
check(feed(t, zedWindow, 5500), nil, "slow app answering its own bind")

t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 5000)
feed(t, zedWindow, 5500)
check(feed(t, zedWindow, 5600), nil, "one hint per launch marker")

t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 5000)
feed(t, zedWindow, 5500)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 8000)
check(feed(t, zedWindow, 8500), nil, "cooldown for the same shortcut")

local fallbackSettings = table.clone(settings)
fallbackSettings.wrapper = false
t = promoter.newTracker(fallbackSettings, zedBinds, 0)
t:panelOpened("launcher")
feed(t, "closelayer>>noctalia-panel", 5000)
check(comboOf(feed(t, zedWindow, 5500)), "SUPER + SHIFT + Z", "fallback: launcher close arms")
t = promoter.newTracker(fallbackSettings, zedBinds, 0)
t:panelOpened("control-center")
feed(t, "closelayer>>noctalia-panel", 5000)
check(feed(t, zedWindow, 5500), nil, "fallback: other panels do not arm")

t = promoter.newTracker(settings, zedBinds, 0)
check(comboOf(switch(t, 5000)), "SUPER + 3", "unannounced workspace switch hints")
t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "custom>>keypromoter:bind,SUPER + 3", 4900)
check(switch(t, 5000), nil, "announced workspace switch")
t = promoter.newTracker(settings, zedBinds, 0)
check(switch(t, 1000), nil, "quiet at startup")
t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "closelayer>>noctalia-window-switcher", 4500)
check(switch(t, 5000), nil, "window switcher explains it")
t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "closelayer>>noctalia-panel-click-shield", 4500)
check(comboOf(switch(t, 5000)), "SUPER + 3", "click shield explains nothing")
t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "openwindow>>1,3,org.example.Other,Other", 4500)
check(switch(t, 5000), nil, "new window explains it")
t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "urgent>>abc", 4500)
check(switch(t, 5000), nil, "urgent app explains it")

t = promoter.newTracker(settings, zedBinds, 0)
switch(t, 5000) -- the plugin's hint
feed(t, "openlayer>>noctalia-notification", 5050)
feed(t, "closelayer>>noctalia-notification", 9000)
check(comboOf(switch(t, 20000)), "SUPER + 3", "own toast closing explains nothing")
t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "openlayer>>noctalia-notification", 4000)
feed(t, "closelayer>>noctalia-notification", 4500)
check(switch(t, 5000), nil, "other toast closing explains it")

t = promoter.newTracker(settings, zedBinds, 0)
switch(t, 5000)
feed(t, "custom>>keypromoter:ui-launch,zeditor", 5200)
check(feed(t, zedWindow, 5400), nil, "gap between any two hints")

-- Shadow binds: the marker follows the workspace change.
t = promoter.newTracker(settings, zedBinds, 0)
feed(t, "workspacev2>>3,3", 5000)
check(t:tick(5100), nil, "no decision before the change settles")
feed(t, "custom>>keypromoter:bind,SUPER + 3", 5001)
check(t:tick(5300), nil, "a marker right after the change counts as a key press")
check(t:hasPending(), false, "decision made")

-- The corner box is a noctalia-panel layer; its own events explain nothing.
t = promoter.newTracker(settings, zedBinds, 0)
t:expectOwnPanel()
check(t:isOwnPanelEvent(promoter.parseEvent("openlayer>>noctalia-panel")), true, "own box opening")
check(t:isOwnPanelEvent(promoter.parseEvent("closelayer>>noctalia-panel")), false, "only as many as expected")

local quiet = table.clone(settings)
quiet.workspaceSwitches = false
t = promoter.newTracker(quiet, zedBinds, 0)
check(switch(t, 5000), nil, "workspace hints off")

if failures > 0 then
    error(`{failures} check(s) failed`)
end
print("promoter_test: ok")
