--!nonstrict
-- Pure logic for the Key Promoter. No Noctalia calls, so plain Luau can test it.
local M = {}

M.VERSION = "0.1.0"

-- Fixed rule timings in milliseconds.
M.BIND_QUIET_MS = 750 -- a workspace change this soon after a bind came from it
-- Shadow binds run after the real bind, so their marker follows the workspace
-- change. Wait this long before deciding.
M.SETTLE_MS = 250
M.EXPLAIN_MS = 1500 -- a closed layer, new window or urgent app explains a workspace change
M.SLOW_APP_MS = 10000 -- a window this soon after its own bind answers that bind
M.STARTUP_MS = 3000
M.HINT_GAP_MS = 1500
M.MIN_SCORE = 20

-- Layers whose closing explains a workspace change.
M.EXPLAINING_LAYERS = {
    ["noctalia-panel"] = true,
    ["noctalia-attached-panel"] = true,
    ["noctalia-window-switcher"] = true,
    ["noctalia-overview-launcher"] = true,
    ["noctalia-notification"] = true,
}

local function trim(value: string): string
    return (string.match(value, "^%s*(.-)%s*$")) or ""
end

-- Splits an IPC "show" payload, "SUPER + B|Open Brave browser", into combo and description.
function M.splitHint(payload: string): (string, string)
    local combo, description = string.match(payload, "^(.-)|(.*)$")
    if combo then
        return trim(combo), trim(description)
    end
    return trim(payload), ""
end

-- Events --------------------------------------------------------------------

-- Splits at most `count` commas; the last field keeps any further commas.
local function splitFields(data: string, count: number): { string }
    local fields = {}
    local rest = data
    for _ = 1, count do
        local field, after = string.match(rest, "^([^,]*),(.*)$")
        if not field then
            break
        end
        table.insert(fields, field)
        rest = after
    end
    table.insert(fields, rest)
    return fields
end

-- Parses one socket2 line into an event table, or nil for events the plugin ignores.
function M.parseEvent(line: string): { [string]: any }?
    local name, data = string.match(line, "^([%w]+)>>(.*)$")
    if not name then
        return nil
    end
    if name == "openwindow" then
        local f = splitFields(data, 3)
        return { kind = "openwindow", address = f[1], workspace = f[2], class = f[3] or "", title = f[4] or "" }
    elseif name == "workspacev2" then
        local f = splitFields(data, 1)
        return { kind = "workspace", id = f[1], name = f[2] or "" }
    elseif name == "openlayer" or name == "closelayer" then
        return { kind = name, namespace = data }
    elseif name == "urgent" then
        return { kind = "urgent" }
    elseif name == "configreloaded" then
        return { kind = "configreloaded" }
    elseif name == "custom" then
        local keys = string.match(data, "^keypromoter:bind,(.*)$")
        if keys then
            return { kind = "bind", combo = keys }
        end
        local program = string.match(data, "^keypromoter:ui%-launch,(.*)$")
        if program then
            return { kind = "launch", program = program }
        end
    end
    return nil
end

-- Binds ---------------------------------------------------------------------

local function splitList(value: string): { string }
    local items = {}
    for item in string.gmatch(value, "[^,]+") do
        item = trim(item)
        if item ~= "" then
            table.insert(items, item)
        end
    end
    return items
end

-- Parses the snippet's bind list: combo, description, command, classes, workspace per line.
function M.parseBindList(text: string): { { [string]: any } }
    local binds = {}
    for line in string.gmatch(text, "[^\n]+") do
        local f = string.split(line, "\t")
        if f[1] and f[1] ~= "" then
            table.insert(binds, {
                combo = f[1],
                description = f[2] or "",
                command = f[3] or "",
                classes = splitList(f[4] or ""),
                workspace = f[5] or "",
            })
        end
    end
    return binds
end

local MODIFIERS = {
    { 64, "SUPER" },
    { 4, "CTRL" },
    { 8, "ALT" },
    { 1, "SHIFT" },
    { 2, "CAPS" },
    { 16, "MOD2" },
    { 32, "MOD3" },
    { 128, "MOD5" },
}

-- Builds "SUPER + SHIFT + Z" from a `hyprctl binds -j` entry.
function M.comboFromHyprctl(entry): string
    local parts = {}
    for _, modifier in MODIFIERS do
        if bit32.band(entry.modmask or 0, modifier[1]) ~= 0 then
            table.insert(parts, modifier[2])
        end
    end
    local key = entry.key or ""
    if key == "" and (entry.keycode or 0) > 0 then
        key = `code:{entry.keycode}`
    end
    table.insert(parts, key)
    return table.concat(parts, " + ")
end

-- Converts `hyprctl binds -j` entries into binds. Lua config binds have no command.
function M.bindsFromHyprctl(entries: { { [string]: any } }): { { [string]: any } }
    local binds = {}
    for _, entry in entries do
        if not entry.mouse and (entry.submap or "") == "" and (entry.description or "") ~= "" then
            table.insert(binds, {
                combo = M.comboFromHyprctl(entry),
                description = entry.description,
                command = if entry.dispatcher == "exec" then entry.arg or "" else "",
                classes = {},
                workspace = "",
            })
        end
    end
    return binds
end

-- Key combos that get a shadow bind: every keyboard bind outside submaps.
-- Drag binds (mouse:272) are left out; they would announce on press and release.
function M.shadowCombos(entries: { { [string]: any } }): { string }
    local combos, seen = {}, {}
    for _, entry in entries do
        local combo = M.comboFromHyprctl(entry)
        local key = string.match(combo, "([^+]*)$") or ""
        if (entry.submap or "") == "" and not entry.catch_all and trim(key) ~= ""
            and not string.find(combo, "mouse:", 1, true) and not seen[combo] then
            seen[combo] = true
            table.insert(combos, combo)
        end
    end
    return combos
end

-- Hyprland Lua for `hyprctl eval` that adds a shadow bind per combo, sending
-- only the bind marker. Hyprland runs every bind on a key, so the real bind
-- still works. Shadows last until the next config reload; the global table
-- stops a restarted plugin adding them twice, and the snippet makes them
-- unnecessary. Split into chunks to keep each request small.
function M.shadowCode(combos: { string }, chunkSize: number?): { string }
    local size = chunkSize or 20
    local chunks = {}
    for first = 1, #combos, size do
        local quoted = {}
        for i = first, math.min(first + size - 1, #combos) do
            table.insert(quoted, string.format("%q", combos[i]))
        end
        table.insert(chunks, "(function() if KEY_PROMOTER_SNIPPET then return end "
            .. "KEY_PROMOTER_SHADOWS = KEY_PROMOTER_SHADOWS or {} "
            .. `for _, keys in ipairs(\{{table.concat(quoted, ", ")}\}) do `
            .. "if not KEY_PROMOTER_SHADOWS[keys] then KEY_PROMOTER_SHADOWS[keys] = true "
            .. 'hl.bind(keys, hl.dsp.event("keypromoter:bind," .. keys)) end end end)()')
    end
    return chunks
end

local function modifierCount(combo: string): number
    local _, plus = string.gsub(combo, "%+", "")
    return plus
end

-- Binds never suggested: media keys, mouse and wheel keys, bare letters (submap keys).
function M.suggestable(bind): boolean
    local combo = bind.combo
    if string.find(combo, "XF86", 1, true) or string.find(string.lower(combo), "mouse", 1, true) then
        return false
    end
    local key = trim(string.match(combo, "([^+]*)$") or "")
    return modifierCount(combo) > 0 or #key > 1
end

-- Commands ------------------------------------------------------------------

local function tokens(command: string): { string }
    local list = {}
    local current, quote = "", nil
    for character in string.gmatch(command, ".") do
        if quote then
            if character == quote then
                quote = nil
            else
                current ..= character
            end
        elseif character == '"' or character == "'" then
            quote = character
        elseif character == " " or character == "\t" then
            if current ~= "" then
                table.insert(list, current)
            end
            current = ""
        else
            current ..= character
        end
    end
    if current ~= "" then
        table.insert(list, current)
    end
    return list
end

local SIMPLE_WRAPPERS = {
    ["uwsm-app"] = true,
    ["app2unit"] = true,
    ["setsid"] = true,
    ["nohup"] = true,
    ["gtk-launch"] = true,
    ["key-promoter-launch"] = true,
}

-- Finds the real program in a launch command and counts the arguments after it.
function M.program(command: string): (string?, number)
    local list = tokens(command)
    local i = 1
    while list[i] do
        local word = list[i]
        local base = string.match(word, "([^/]+)$") or word
        if SIMPLE_WRAPPERS[base] or word == "--" or string.find(word, "^[%w_]+=") then
            i += 1
        elseif base == "env" then
            i += 1
            while list[i] and string.find(list[i], "^%-") do
                i += 1
            end
        elseif base == "uwsm" and list[i + 1] == "app" then
            i += 2
        elseif base == "systemd-run" then
            i += 1
            while list[i] and string.find(list[i], "^%-") do
                i += 1
            end
        elseif base == "flatpak" and list[i + 1] == "run" then
            i += 2
            while list[i] and string.find(list[i], "^%-") do
                i += 1
            end
        elseif base == "launch" and list[i + 1] == "tui" then
            i += 2
        else
            local program = string.lower(string.gsub(base, "%.desktop$", "") :: string)
            return program, #list - i
        end
    end
    return nil, 0
end

-- Matching ------------------------------------------------------------------

local STOP_WORDS = {
    open = true, focus = true, toggle = true, the = true, ["and"] = true,
    ["for"] = true, with = true, ["in"] = true, ["or"] = true, to = true,
}

local function words(text: string): { string }
    local list = {}
    for word in string.gmatch(string.lower(text), "[%w]+") do
        if #word >= 3 and not STOP_WORDS[word] then
            table.insert(list, word)
        end
    end
    return list
end

local function lastSegment(class: string): string
    return string.match(class, "([^.]+)$") or class
end

-- Scores how well a bind names a window. Returns the base score (0 if nothing
-- but title words match) and the total.
function M.score(bind, class: string, title: string): (number, number)
    class = string.lower(class)
    title = string.lower(title)
    local segment = lastSegment(class)
    local base = 0
    for _, wanted in bind.classes do
        if string.lower(wanted) == class then
            base = 100
        end
    end
    local program, args = M.program(bind.command)
    if program and base < 100 then
        if program == class or program == segment then
            base = math.max(base, 50)
        elseif #program >= 3 and (string.find(class, program, 1, true)
            or string.sub(program, 1, #class) == class
            or (#segment >= 3 and string.sub(program, 1, #segment) == segment)) then
            base = math.max(base, 30)
        end
    end
    local bonus = 0
    for _, word in words(bind.description) do
        if base < 20 and #bind.command == 0 and (word == class or word == segment) then
            base = 20
        end
        if string.find(class, word, 1, true) or string.find(title, word, 1, true) then
            bonus += 1
        end
    end
    return base, base + bonus - 0.1 * args
end

local function sameAction(a, b): boolean
    return a.command == b.command and table.concat(a.classes, ",") == table.concat(b.classes, ",")
end

-- Picks one bind among the best-scoring ones, or nil if different actions tie.
local function pickWinner(best: { any }): any
    if #best == 0 then
        return nil
    end
    local winner = best[1]
    for i = 2, #best do
        if not sameAction(best[i], winner) then
            return nil
        end
        if modifierCount(best[i].combo) < modifierCount(winner.combo) then
            winner = best[i]
        end
    end
    return winner
end

-- Finds the bind that opens a window, or nil if none clearly does.
function M.matchWindow(binds, class: string, title: string)
    local best, bestScore = {}, -math.huge
    for _, bind in binds do
        if M.suggestable(bind) and not string.find(string.lower(bind.description), "workspace", 1, true) then
            local base, total = M.score(bind, class, title)
            if base >= M.MIN_SCORE then
                if total > bestScore + 1e-9 then
                    best, bestScore = { bind }, total
                elseif math.abs(total - bestScore) <= 1e-9 then
                    table.insert(best, bind)
                end
            end
        end
    end
    return pickWinner(best)
end

local MOVING_WORDS = { "move", "send", "carry", "follow" }

-- Finds the bind that switches to a workspace by its name.
function M.matchWorkspace(binds, name: string)
    local best = {}
    for _, bind in binds do
        if M.suggestable(bind) then
            local description = string.lower(bind.description)
            local matches = bind.workspace == name
            if not matches and bind.workspace == "" then
                matches = string.sub(description, -#("workspace " .. name)) == "workspace " .. string.lower(name)
                for _, word in MOVING_WORDS do
                    if string.find(description, word, 1, true) then
                        matches = false
                    end
                end
            end
            if matches then
                table.insert(best, bind)
            end
        end
    end
    return pickWinner(best)
end

-- Tracker -------------------------------------------------------------------

local Tracker = {}
Tracker.__index = Tracker

-- Settings: appLaunches, workspaceSwitches, launchWindowMs, cooldownMs,
-- launcherLayers (list) and wrapper (true when launch markers arrive).
function M.newTracker(settings, binds, nowMs: number)
    local layers = {}
    for _, name in settings.launcherLayers or {} do
        layers[name] = true
    end
    return setmetatable({
        settings = settings,
        binds = binds,
        launcherLayers = layers,
        startedAt = nowMs,
        lastBindAt = -math.huge,
        bindAt = {},
        armedAt = nil,
        launcherOpen = false,
        explainedAt = -math.huge,
        ownNotification = false,
        hintPending = false,
        lastHintAt = -math.huge,
        hintAt = {},
    }, Tracker)
end

function Tracker:setBinds(binds)
    self.binds = binds
end

-- The service reports the active panel id after a launcher layer opens.
function Tracker:panelOpened(id: string?)
    self.launcherOpen = id == "launcher"
end

-- The service is about to open or close the corner box, which is a
-- noctalia-panel layer; its next open or close event is not the user's.
function Tracker:expectOwnPanel()
    self.ownPanelEvents = (self.ownPanelEvents or 0) + 1
end

-- True for (and swallows) a layer event the corner box caused.
function Tracker:isOwnPanelEvent(event): boolean
    if (event.kind == "openlayer" or event.kind == "closelayer")
        and event.namespace == "noctalia-panel" and (self.ownPanelEvents or 0) > 0 then
        self.ownPanelEvents -= 1
        return true
    end
    return false
end

function Tracker:explain(nowMs: number)
    self.explainedAt = nowMs
end

function Tracker:hint(bind, nowMs: number)
    if nowMs - self.lastHintAt < M.HINT_GAP_MS then
        return nil
    end
    if nowMs - (self.hintAt[bind.combo] or -math.huge) < (self.settings.cooldownMs or 0) then
        return nil
    end
    self.lastHintAt = nowMs
    self.hintAt[bind.combo] = nowMs
    -- A notification hint opens the notification layer; the corner box does not.
    self.hintPending = not self.settings.toast
    return { combo = bind.combo, description = bind.description }
end

function Tracker:onWindow(event, nowMs: number)
    local armedAt = self.armedAt
    self.armedAt = nil
    self:explain(nowMs)
    if not self.settings.appLaunches or not armedAt then
        return nil
    end
    if nowMs - armedAt > (self.settings.launchWindowMs or 3000) or self.lastBindAt > armedAt then
        return nil
    end
    local bind = M.matchWindow(self.binds, event.class, event.title)
    if not bind or nowMs - (self.bindAt[bind.combo] or -math.huge) < M.SLOW_APP_MS then
        return nil
    end
    return self:hint(bind, nowMs)
end

-- Workspace changes wait M.SETTLE_MS for a marker that follows them; tick() decides.
function Tracker:onWorkspace(event, nowMs: number)
    self.pendingWorkspace = if self.settings.workspaceSwitches then { name = event.name, at = nowMs } else nil
    return nil
end

-- Call regularly; returns a workspace hint once a change has settled.
function Tracker:tick(nowMs: number)
    local pending = self.pendingWorkspace
    if not pending or nowMs - pending.at < M.SETTLE_MS then
        return nil
    end
    self.pendingWorkspace = nil
    if pending.at - self.startedAt < M.STARTUP_MS
        or pending.at - self.lastBindAt < M.BIND_QUIET_MS
        or self.lastBindAt >= pending.at
        or pending.at - self.explainedAt < M.EXPLAIN_MS then
        return nil
    end
    local bind = M.matchWorkspace(self.binds, pending.name)
    return bind and self:hint(bind, nowMs)
end

function Tracker:hasPending(): boolean
    return self.pendingWorkspace ~= nil
end

-- Feeds one parsed event; returns a hint { combo, description } or nil.
function Tracker:handle(event, nowMs: number)
    local kind = event.kind
    if kind == "bind" then
        self.lastBindAt = nowMs
        self.bindAt[event.combo] = nowMs
    elseif kind == "launch" then
        if self.settings.wrapper then
            self.armedAt = nowMs
        end
    elseif kind == "openlayer" then
        if event.namespace == "noctalia-notification" then
            self.ownNotification = self.hintPending
            self.hintPending = false
        end
    elseif kind == "closelayer" then
        local namespace = event.namespace
        if not self.settings.wrapper and self.launcherLayers[namespace] and self.launcherOpen then
            self.launcherOpen = false
            self.armedAt = nowMs
        end
        if namespace == "noctalia-notification" and self.ownNotification then
            self.ownNotification = false
        elseif M.EXPLAINING_LAYERS[namespace] then
            self:explain(nowMs)
        end
    elseif kind == "urgent" then
        self:explain(nowMs)
    elseif kind == "openwindow" then
        return self:onWindow(event, nowMs)
    elseif kind == "workspace" then
        return self:onWorkspace(event, nowMs)
    end
    return nil
end

return M
