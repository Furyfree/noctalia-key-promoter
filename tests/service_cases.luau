--!nonstrict
-- Cases for service.luau, run after it on the fake host in tests/service_stub.luau.
local failures = 0
local function check(actual, expected, what)
    if actual ~= expected then
        failures += 1
        print(`FAIL {what}: expected {tostring(expected)}, got {tostring(actual)}`)
    end
end

local function at(ms, line)
    host.now = ms
    host.stream(line)
end

-- Lets the service's update tick decide pending workspace changes.
local function settle(ms)
    host.now = ms
    update()
end

local function lastNote()
    local note = host.notes[#host.notes]
    return note and `{note.title}|{note.body}` or "none"
end

local function lastLog()
    return host.logs[#host.logs] or ""
end

-- Resolves the oldest pending async call with stdout and exit code.
local function answer(stdout, exitCode)
    local call = table.remove(host.async, 1)
    call.callback({ stdout = stdout, stderr = "", exitCode = exitCode or 0 })
    return call.argv
end

-- Start-up: socat on the right socket, binds from the snippet's list, shadow
-- binds for every keyboard bind Hyprland reports.
check(string.find(host.streamCommand, "/run/user/1000/hypr/abc/.socket2.sock", 1, true) ~= nil, true, "socket path")
host.json["startup-binds"] = {
    { modmask = 65, key = "Z", description = "Open Zed", dispatcher = "__lua" },
    { modmask = 64, key = "3", description = "Switch to local workspace 3", dispatcher = "__lua" },
    { modmask = 64, key = "mouse:272", description = "Move window with mouse", dispatcher = "__lua" },
}
check(table.concat(answer("startup-binds"), " "), "hyprctl binds -j", "binds asked at start")
local evalCall = host.async[1]
check(evalCall and evalCall.argv[2], "eval", "shadow binds added with hyprctl eval")
check(string.find(evalCall.argv[3], '"SUPER + SHIFT + Z"', 1, true) ~= nil, true, "shadow for a keyboard bind")
check(string.find(evalCall.argv[3], "mouse:272", 1, true), nil, "no shadow for a drag bind")
answer("")
onIpc("state", nil)
check(string.find(lastLog(), "2 binds from snippet", 1, true) ~= nil, true, "state: binds from snippet")
check(string.find(lastLog(), "shadow binds on", 1, true) ~= nil, true, "state: shadow binds on")
check(string.find(lastLog(), "wrapper found", 1, true) ~= nil, true, "state: wrapper found")

-- A shell launch shows a hint with its count, and the count is saved.
at(5000, "custom>>keypromoter:ui-launch,zeditor")
at(5500, "openwindow>>1,1,dev.zed.Zed,Zed")
check(lastNote(), "SUPER + SHIFT + Z|Open Zed  ×1", "launch hint")
check(host.json["encoded"]["SUPER + SHIFT + Z"], 1, "count saved")

-- A bar click on a workspace hints; a key press does not.
at(8000, "workspacev2>>3,3")
settle(8000 + 300)
check(lastNote(), "SUPER + 3|Switch to local workspace 3  ×1", "workspace hint")
local before = #host.notes
at(30000, "custom>>keypromoter:bind,SUPER + 3")
at(30100, "workspacev2>>3,3")
settle(30100 + 300)
check(#host.notes, before, "announced switch stays quiet")

-- Show count off.
host.config.show_count = false
at(50000, "workspacev2>>3,3")
settle(50000 + 300)
check(lastNote(), "SUPER + 3|Switch to local workspace 3", "no count")
host.config.show_count = true

-- Without the wrapper, only the launcher arms a launch hint.
host.settings["shell.launch_apps_custom_command"] = "uwsm-app -- $CMD"
onConfigChanged()
host.json["status-launcher"] = { activePanelId = "launcher" }
host.json["status-settings"] = { activePanelId = "control-center" }
at(60000, "openlayer>>noctalia-panel")
check(table.concat(answer("status-settings"), " "), "noctalia msg status", "status asked on panel open")
at(61000, "closelayer>>noctalia-panel")
before = #host.notes
at(61500, "openwindow>>2,1,dev.zed.Zed,Zed")
check(#host.notes, before, "other panel does not arm")
at(80000, "openlayer>>noctalia-panel")
answer("status-launcher")
at(81000, "closelayer>>noctalia-panel")
at(81500, "openwindow>>3,1,dev.zed.Zed,Zed")
check(lastNote(), "SUPER + SHIFT + Z|Open Zed  ×2", "launcher arms in the fallback")

-- No snippet list: binds from hyprctl; shadow binds still announce key presses.
host.files["/run/user/1000/hypr-key-promoter.tsv"] = nil
host.json["binds"] = { { modmask = 64, key = "3", description = "Switch to local workspace 3", dispatcher = "__lua" } }
onIpc("reload", nil)
check(table.concat(answer("binds"), " "), "hyprctl binds -j", "hyprctl fallback asked")
answer("")
onIpc("state", nil)
check(string.find(lastLog(), "1 binds from hyprctl", 1, true) ~= nil, true, "state: binds from hyprctl")
check(string.find(lastLog(), "workspaces true", 1, true) ~= nil, true, "workspace hints on with shadow binds")

-- Shadow binds fail and there is no snippet: workspace hints stay off.
onIpc("reload", nil)
answer("binds")
answer("", 1)
onIpc("state", nil)
check(string.find(lastLog(), "shadow binds off", 1, true) ~= nil, true, "state: shadow binds off")
check(string.find(lastLog(), "workspaces false", 1, true) ~= nil, true, "workspace hints off without markers")
before = #host.notes
at(100000, "workspacev2>>3,3")
settle(100000 + 300)
check(#host.notes, before, "no workspace hint without markers")

-- A Hyprland reload rereads the snippet's list and adds shadow binds again.
host.files["/run/user/1000/hypr-key-promoter.tsv"] = "SUPER + 3\tSwitch to local workspace 3\t\t\t\n"
at(110000, "configreloaded>>")
check(table.concat(answer("binds"), " "), "hyprctl binds -j", "binds asked after reload")
check(host.async[1] and host.async[1].argv[2], "eval", "shadow binds added after reload")
answer("")
onIpc("state", nil)
check(string.find(lastLog(), "1 binds from snippet", 1, true) ~= nil, true, "configreloaded rereads the list")

-- IPC commands.
onIpc("show", "SUPER + B|Open Brave browser")
check(lastNote(), "SUPER + B|Open Brave browser", "show")
onIpc("stats", nil)
check(string.find(lastLog(), "SUPER + 3 ×2", 1, true) ~= nil, true, "stats lists the top shortcut")
onIpc("reset", nil)
check(next(host.json["encoded"]), nil, "reset clears counts")
onIpc("nonsense", nil)
check(string.find(lastLog(), "unknown command", 1, true) ~= nil, true, "unknown command")

-- The corner box: the service sets the hint, opens the panel once, and closes it.
host.config.notifications = false
onConfigChanged()
local notesBefore = #host.notes
host.now = 200000
onIpc("show", "SUPER + B|Open Brave browser")
check(host.state.hint and host.state.hint.combo, "SUPER + B", "box gets the hint")
check(host.toggled, "furyfree/key-promoter:toast", "box panel id")
check(host.toggles, 1, "box opened")
check(host.interval, 100, "fast ticks while the box shows")
check(#host.notes, notesBefore, "no notification when the box is on")
host.now = 201000
onIpc("show", "SUPER + 3|Switch to local workspace 3")
check(host.toggles, 1, "a second hint reuses the open box")
at(201010, "openlayer>>noctalia-panel")
check(#host.async, 0, "the box opening is not taken for the launcher")
settle(203600)
check(host.toggles, 2, "box closes after 2.5 s")
check(host.interval, 60000, "ticks slow down again")
at(203610, "closelayer>>noctalia-panel")
at(210000, "workspacev2>>3,3")
settle(210300)
check(host.state.hint.combo, "SUPER + 3", "the box closing explains nothing")

if failures > 0 then
    error(`{failures} check(s) failed`)
end
print("service_test: ok")
