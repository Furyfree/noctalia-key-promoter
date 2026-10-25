--!nonstrict
-- Key Promoter service: reads Hyprland's socket2, decides with promoter.luau
-- and shows hints as Noctalia notifications.
local promoter = require("./promoter.luau")

local LIST_NAME = "hypr-key-promoter.tsv"
local WRAPPER = "key-promoter-launch"
local TICK_MS = 100
local IDLE_MS = 60000
local TOAST = "furyfree/key-promoter:toast"
local TOAST_MS = 2500

local toastShownAt = nil -- when the corner box last got a hint; nil while closed

local source = "none" -- where the binds came from: snippet, hyprctl or none
local shadows = false -- runtime shadow binds announce key presses
local counts = {}
local tracker

local function countsPath(): string
    return noctalia.pluginDataDir() .. "/counts.json"
end

local function loadCounts()
    local raw = noctalia.readFile(countsPath())
    local ok, decoded = pcall(noctalia.json.decode, raw or "")
    counts = if ok and type(decoded) == "table" then decoded else {}
end

local function saveCounts()
    noctalia.mkdirAll(noctalia.pluginDataDir())
    noctalia.writeFile(countsPath(), noctalia.json.encode(counts))
end

local function wrapperConfigured(): boolean
    local command = noctalia.getSetting("shell.launch_apps_custom_command")
    return type(command) == "string" and string.find(command, WRAPPER, 1, true) ~= nil
end

local function currentSettings()
    local seconds = tonumber(noctalia.getConfig("cooldown_s")) or 10
    return {
        appLaunches = noctalia.getConfig("app_launches") ~= false,
        -- Without bind markers every workspace change looks unannounced.
        workspaceSwitches = noctalia.getConfig("workspace_switches") ~= false and (source == "snippet" or shadows),
        launchWindowMs = tonumber(noctalia.getConfig("launch_window_ms")) or 3000,
        cooldownMs = seconds * 1000,
        launcherLayers = noctalia.getConfig("launcher_layers") or {},
        wrapper = wrapperConfigured(),
        toast = noctalia.getConfig("notifications") ~= true,
    }
end

local function rebuildTracker()
    tracker = promoter.newTracker(currentSettings(), tracker and tracker.binds or {}, noctalia.nowMs())
end

local function useBinds(binds, from: string)
    source = from
    rebuildTracker()
    tracker:setBinds(binds)
end

-- Adds a shadow bind per keyboard bind so key presses announce themselves
-- without the snippet. Hyprland drops them on reload, so this runs per load.
local function addShadows(entries)
    local chunks = promoter.shadowCode(promoter.shadowCombos(entries))
    local pending, failed = #chunks, false
    for _, code in chunks do
        noctalia.runAsync({ "hyprctl", "eval", code }, function(result)
            pending -= 1
            failed = failed or result.exitCode ~= 0
            if pending == 0 then
                shadows = not failed
                if failed then
                    noctalia.log("key-promoter: could not add shadow binds")
                end
                rebuildTracker()
            end
        end)
    end
end

local function loadBinds()
    shadows = false
    noctalia.runAsync({ "hyprctl", "binds", "-j" }, function(result)
        local ok, entries = pcall(noctalia.json.decode, result.stdout or "")
        if result.exitCode ~= 0 or not ok or type(entries) ~= "table" then
            entries = nil
        end
        local runtime = noctalia.getenv("XDG_RUNTIME_DIR")
        local raw = runtime and noctalia.readFile(`{runtime}/{LIST_NAME}`)
        if raw and raw ~= "" then
            useBinds(promoter.parseBindList(raw), "snippet")
        elseif entries then
            useBinds(promoter.bindsFromHyprctl(entries), "hyprctl")
        else
            useBinds({}, "none")
        end
        if entries then
            addShadows(entries)
        end
    end)
end

local function toggleToast()
    tracker:expectOwnPanel()
    noctalia.togglePanel(TOAST)
end

-- Shows a hint in the corner box, or as a notification when the user prefers.
local function present(combo: string, description: string, count: number?)
    if not tracker.settings.toast then
        noctalia.notify(combo, if count then `{description}  ×{count}` else description)
        return
    end
    noctalia.state.set("hint", { combo = combo, description = description, count = count })
    if not toastShownAt then
        toggleToast()
    end
    toastShownAt = noctalia.nowMs()
    noctalia.setUpdateInterval(TICK_MS)
end

local function show(hint)
    counts[hint.combo] = (counts[hint.combo] or 0) + 1
    saveCounts()
    present(hint.combo, hint.description, if noctalia.getConfig("show_count") ~= false then counts[hint.combo] else nil)
end

-- Fallback without the wrapper: only the launcher arms a launch hint.
local function checkPanel()
    noctalia.runAsync({ "noctalia", "msg", "status" }, function(result)
        local ok, status = pcall(noctalia.json.decode, result.stdout or "")
        tracker:panelOpened(if ok and type(status) == "table" then status.activePanelId else nil)
    end)
end

local function onLine(line: string)
    local event = promoter.parseEvent(line)
    if not event then
        return
    end
    if event.kind == "configreloaded" then
        loadBinds()
        return
    end
    if tracker:isOwnPanelEvent(event) then
        return
    end
    if event.kind == "openlayer" and not tracker.settings.wrapper and tracker.launcherLayers[event.namespace] then
        checkPanel()
    end
    local hint = tracker:handle(event, noctalia.nowMs())
    if hint then
        show(hint)
    end
    if tracker:hasPending() then
        noctalia.setUpdateInterval(TICK_MS)
    end
end

-- Noctalia calls update() on the interval; it only runs fast while a
-- workspace change waits to be decided or the corner box is showing.
function update()
    local now = noctalia.nowMs()
    local hint = tracker:tick(now)
    if hint then
        show(hint)
    end
    if toastShownAt and now - toastShownAt >= TOAST_MS then
        toastShownAt = nil
        toggleToast()
    end
    if not tracker:hasPending() and not toastShownAt then
        noctalia.setUpdateInterval(IDLE_MS)
    end
end

local function shellQuote(value: string): string
    return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function watchEvents()
    local runtime = noctalia.getenv("XDG_RUNTIME_DIR")
    local instance = noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE")
    if not runtime or not instance then
        noctalia.log("key-promoter: Hyprland socket not found")
        return
    end
    local socket = `{runtime}/hypr/{instance}/.socket2.sock`
    noctalia.runStream("stdbuf -oL socat -u UNIX-CONNECT:" .. shellQuote(socket) .. " -", onLine)
end

local function logStats()
    local combos = {}
    for combo, count in counts do
        table.insert(combos, { combo = combo, count = count })
    end
    table.sort(combos, function(a, b) return a.count > b.count end)
    local parts = {}
    for i = 1, math.min(5, #combos) do
        table.insert(parts, `{combos[i].combo} ×{combos[i].count}`)
    end
    noctalia.log(`key-promoter: top shortcuts: {if #parts > 0 then table.concat(parts, ", ") else "none"}`)
end

function onIpc(event, payload)
    if event == "show" then
        local combo, description = promoter.splitHint(tostring(payload or ""))
        present(combo, description)
    elseif event == "reload" then
        loadBinds()
    elseif event == "stats" then
        logStats()
    elseif event == "state" then
        noctalia.log(`key-promoter {promoter.VERSION}: {#tracker.binds} binds from {source}, `
            .. `shadow binds {if shadows then "on" else "off"}, `
            .. `wrapper {if tracker.settings.wrapper then "found" else "not found"}, `
            .. `launches {tostring(tracker.settings.appLaunches)}, workspaces {tostring(tracker.settings.workspaceSwitches)}`)
    elseif event == "reset" then
        counts = {}
        saveCounts()
    else
        noctalia.log(`key-promoter: unknown command '{event}'`)
    end
end

function onConfigChanged()
    rebuildTracker()
end

loadCounts()
rebuildTracker()
loadBinds()
watchEvents()
noctalia.log(`key-promoter {promoter.VERSION}: started`)
