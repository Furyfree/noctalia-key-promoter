--!nonstrict
-- Key Promoter service: reads Hyprland's socket2, decides with promoter.luau
-- and shows hints in the corner box or as Noctalia notifications.
local promoter = require("./promoter.luau")

local LIST_NAME = "hypr-key-promoter.tsv"
local WRAPPER = "key-promoter-launch"
local TICK_MS = 100
local IDLE_MS = 60000
local TOAST = "furyfree/key-promoter:hint-box-" -- plus the row count: hint-box-1..3
local TOAST_MS = 2500 -- how long each hint row stays
local TOAST_ROWS = 3

local rows = {} -- hints in the box, oldest first: { combo, description, at }
local openBox = 0 -- the row count of the box on screen; 0 while closed

local source = "none" -- where the binds came from: snippet, hyprctl or none
local shadows = false -- runtime shadow binds announce key presses
local counts = {} -- hints shown per shortcut, for stats
local unbound = {} -- shell launches of apps without a shortcut; see promoter.countUnbound
local tracker

local function dataPath(name: string): string
    return `{noctalia.pluginDataDir()}/{name}`
end

local function loadJson(name: string)
    local ok, decoded = pcall(noctalia.json.decode, noctalia.readFile(dataPath(name)) or "")
    return if ok and type(decoded) == "table" then decoded else {}
end

local function saveJson(name: string, value)
    noctalia.mkdirAll(noctalia.pluginDataDir())
    noctalia.writeFile(dataPath(name), noctalia.json.encode(value))
end

local function saveCounts()
    saveJson("counts.json", counts)
end

local function wrapperConfigured(): boolean
    local command = noctalia.getSetting("shell.launch_apps_custom_command")
    return type(command) == "string" and string.find(command, WRAPPER, 1, true) ~= nil
end

local function currentSettings()
    return {
        appLaunches = noctalia.getConfig("app_launches") ~= false,
        -- Without bind markers every workspace change looks unannounced.
        workspaceSwitches = noctalia.getConfig("workspace_switches") ~= false and (source == "snippet" or shadows),
        wrapper = wrapperConfigured(),
        toast = noctalia.getConfig("notifications") ~= true,
        ignore = noctalia.getConfig("ignore") or {},
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

local function toggleToast(size: number)
    tracker:expectOwnPanel()
    noctalia.togglePanel(TOAST .. size)
end

-- Publishes the rows and shows the box that fits them: the new size opens
-- before the old one closes, so the corner never goes empty in between.
local function syncBox()
    noctalia.state.set("hints", table.clone(rows))
    local size = #rows
    if size == openBox then
        return
    end
    if size > 0 then
        toggleToast(size)
    end
    if openBox > 0 then
        toggleToast(openBox)
    end
    openBox = size
end

-- Shows a hint in the corner box, or as a notification when the user prefers.
-- The box stacks up to TOAST_ROWS hints, each leaving after TOAST_MS. An
-- empty combo shows the text alone.
local function present(combo: string, description: string)
    if not tracker.settings.toast then
        noctalia.notify(if combo ~= "" then combo else "Key Promoter", description)
        return
    end
    if #rows >= TOAST_ROWS then
        table.remove(rows, 1)
    end
    table.insert(rows, { combo = combo, description = description, at = noctalia.nowMs() })
    syncBox()
    noctalia.setUpdateInterval(TICK_MS)
end

-- Drops rows whose time is up; the box shrinks and closes with them.
local function expireRows(now: number)
    local kept = {}
    for _, row in rows do
        if now - row.at < TOAST_MS then
            table.insert(kept, row)
        end
    end
    if #kept ~= #rows then
        rows = kept
        syncBox()
    end
end

local function show(hint)
    counts[hint.combo] = (counts[hint.combo] or 0) + 1
    saveCounts()
    present(hint.combo, hint.description)
end


-- Suggests a shortcut once an app without one was opened from the shell
-- `suggest_after` times within the `suggest_period`. Wall-clock time, so the
-- saved launches still count after a restart.
local function countUnbound(app)
    local threshold = tonumber(noctalia.getConfig("suggest_after")) or 5
    if threshold <= 0 then
        return
    end
    local periodMs = promoter.SUGGEST_PERIOD_MS[noctalia.getConfig("suggest_period")] or promoter.SUGGEST_PERIOD_MS.day
    local suggest = promoter.countUnbound(unbound, string.lower(app.class), os.time() * 1000, threshold, periodMs)
    saveJson("unbound.json", unbound)
    if suggest then
        present("", `No shortcut found for {promoter.appName(app.class, app.title)}`)
    end
end

local function handleResult(result)
    if not result then
        return
    elseif result.unbound then
        countUnbound(result)
    else
        show(result)
    end
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
    handleResult(tracker:handle(event, noctalia.nowMs()))
    if tracker:hasPending() then
        noctalia.setUpdateInterval(TICK_MS)
    end
end

-- Noctalia calls update() on the interval; it only runs fast while a launch
-- or workspace change waits to be decided or the corner box is showing.
function update()
    local now = noctalia.nowMs()
    handleResult(tracker:tick(now))
    expireRows(now)
    if not tracker:hasPending() and #rows == 0 then
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

counts = loadJson("counts.json")
unbound = loadJson("unbound.json")
rebuildTracker()
loadBinds()
watchEvents()
noctalia.log(`key-promoter {promoter.VERSION}: started`)
