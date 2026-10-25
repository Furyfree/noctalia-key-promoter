-- Run from the repository root: lua tests/snippet_test.lua
-- A fake hl records binds and dispatches so the snippet runs under plain Lua.

local function new_dispatcher(name, arg)
    return setmetatable({ name = name, arg = arg }, { __name = "HL.Dispatcher" })
end

local binds, dispatched = {}, {}
_G.hl = {
    bind = function(keys, action, opts)
        local bind = { keys = keys, action = action, submap = opts and opts.submap_for_test or "" }
        table.insert(binds, bind)
        return bind
    end,
    dispatch = function(dispatcher)
        table.insert(dispatched, dispatcher)
        return { ok = true }
    end,
    dsp = {
        event = function(data) return new_dispatcher("event", data) end,
        exec_cmd = function(command, rules) return new_dispatcher("exec_cmd", { command, rules }) end,
        focus = function(target) return new_dispatcher("focus", target) end,
        window = {
            drag = function() return new_dispatcher("drag") end,
            close = function() return new_dispatcher("close") end,
        },
    },
}

local list_path = os.tmpname()
local real_getenv = os.getenv
os.getenv = function(name)
    if name == "XDG_RUNTIME_DIR" then return list_path:match("^(.*)/") end
    return real_getenv(name)
end
local snippet = dofile("hypr/key-promoter.lua")
os.getenv = real_getenv
list_path = snippet.list_path

local function check(actual, expected, what)
    if actual ~= expected then
        error(what .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function list_lines()
    local file = assert(io.open(list_path))
    local lines = {}
    for line in file:lines() do table.insert(lines, line) end
    file:close()
    return lines
end

local function run(bind)
    dispatched = {}
    local result = bind.action()
    return result
end

-- An exec bind announces itself, then runs its dispatcher.
local exec = hl.dsp.exec_cmd("uwsm-app -- zeditor", { float = true })
check(exec.arg[2].float, true, "exec_cmd keeps its rule table")
local bind = hl.bind("SUPER + SHIFT + Z", exec, { description = "Open Zed" })
check(type(bind.action), "function", "exec bind is wrapped")
check(run(bind).ok, true, "wrapper returns the dispatch result")
check(dispatched[1].name, "event", "marker comes first")
check(dispatched[1].arg, "keypromoter:bind,SUPER + SHIFT + Z", "marker data")
check(dispatched[2], exec, "then the bind's own dispatcher")

-- A Lua function action keeps its target and return value.
local opened = false
local launch = snippet.target(function() opened = true; return "done" end,
    { class = { "vesktop", "Vesktop" } })
bind = hl.bind("SUPER + SHIFT + D", launch, { description = "Focus or open Discord in Vesktop" })
check(run(bind), "done", "function result passes through")
check(opened, true, "function action ran")
check(dispatched[1].arg, "keypromoter:bind,SUPER + SHIFT + D", "function bind marker")

-- Drag binds stay unwrapped and unlisted.
local drag = hl.dsp.window.drag()
bind = hl.bind("SUPER + mouse:272", drag, { mouse = true, description = "Move window with mouse" })
check(bind.action, drag, "drag bind is not wrapped")

-- Wheel binds announce but are not listed.
bind = hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "r+1" }), { description = "Next workspace" })
check(type(bind.action), "function", "wheel bind is wrapped")

-- promote = false still announces, but is not listed.
bind = hl.bind("SUPER + Return", hl.dsp.exec_cmd("uwsm-app -- ghostty"),
    { description = "Open Ghostty terminal", promote = false })
check(type(bind.action), "function", "promote = false still announces")

-- Submap binds are not listed.
hl.bind("H", hl.dsp.window.close(), { description = "Submap key", submap_for_test = "resize" })

-- An explicit class and a workspace are listed.
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("uwsm-app -- 1password"),
    { description = "Focus or open 1Password", promote = { class = "com.onepassword.OnePassword" } })
hl.bind("SUPER + 8", function() end, { description = "Switch to local workspace\t8" })

local lines = list_lines()
check(#lines, 4, "listed binds")
check(lines[1], "SUPER + SHIFT + Z\tOpen Zed\tuwsm-app -- zeditor\t\t", "exec row")
check(lines[2], "SUPER + SHIFT + D\tFocus or open Discord in Vesktop\t\tvesktop,Vesktop\t", "target row")
check(lines[3], "SUPER + SHIFT + P\tFocus or open 1Password\tuwsm-app -- 1password\tcom.onepassword.OnePassword\t",
    "promote row")
check(lines[4], "SUPER + 8\tSwitch to local workspace 8\t\t\t", "tabs in fields become spaces")

-- A snippet error never costs a bind: keys that are not a string break the
-- bookkeeping, and the bind is registered unchanged.
local count = #binds
local plain = hl.dsp.window.close()
local ok = pcall(hl.bind, {}, plain, { description = "Close focused window" })
check(ok, true, "bind survives a snippet error")
check(#binds, count + 1, "bind still registered")
check(binds[#binds].action, plain, "bind registered unchanged")

os.remove(list_path)
print("snippet_test: ok")
