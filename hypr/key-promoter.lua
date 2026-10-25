-- Key Promoter for Hyprland: makes keyboard binds announce themselves on
-- socket2 and writes the bind list the Noctalia plugin reads.
-- Load it before any hl.bind call, including the host file's.
local M = {}

local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
M.list_path = runtime_dir and (runtime_dir .. "/hypr-key-promoter.tsv")

local weak = { __mode = "k" }
local commands = setmetatable({}, weak) -- dispatcher -> command it runs
local runs_on_release = setmetatable({}, weak) -- dispatchers Hyprland runs again on release
local targets = setmetatable({}, weak) -- action -> { class = ..., workspace = ... }
local rows = {}

local original_bind = hl.bind
local event = hl.dsp.event

-- Tells the snippet which window a Lua function action opens.
function M.target(action, opts)
    targets[action] = opts
    return action
end

-- Wraps a dispatcher factory so the snippet can recognise what it returns.
local function remember(owner, name, store, value)
    local factory = owner and owner[name]
    if type(factory) ~= "function" then
        return
    end
    owner[name] = function(...)
        local dispatcher = factory(...)
        if dispatcher ~= nil then
            store[dispatcher] = value(...)
        end
        return dispatcher
    end
end

local function first(argument)
    return argument
end
local function yes()
    return true
end

remember(hl.dsp, "exec_cmd", commands, first)
remember(hl.dsp, "exec_raw", commands, first)
remember(hl.dsp.window, "drag", runs_on_release, yes)
remember(hl.dsp.window, "resize", runs_on_release, yes)
remember(hl.dsp, "pass", runs_on_release, yes)
remember(hl.dsp, "global", runs_on_release, yes)
remember(hl.dsp, "send_shortcut", runs_on_release, yes)

local function skips_announcement(keys, action, opts)
    -- Drag binds would announce twice, on press and on release.
    return runs_on_release[action] or opts.mouse or string.find(keys, "mouse:", 1, true)
end

local function announced(keys, action, opts)
    if skips_announcement(keys, action, opts) then
        return action
    end
    local marker = event("keypromoter:bind," .. keys)
    if type(action) == "function" then
        return function(...)
            hl.dispatch(marker)
            return action(...)
        end
    end
    return function()
        hl.dispatch(marker)
        return hl.dispatch(action)
    end
end

local function field(value)
    if type(value) == "table" then
        value = table.concat(value, ",")
    end
    return (tostring(value or ""):gsub("[\t\r\n]", " "))
end

local function write_list()
    if not M.list_path then
        return
    end
    local temporary = M.list_path .. ".tmp"
    local file = assert(io.open(temporary, "w"))
    file:write(table.concat(rows))
    file:close()
    assert(os.rename(temporary, M.list_path))
end

local function record(keys, action, opts, bind)
    if opts.promote == false or skips_announcement(keys, action, opts)
        or string.find(keys, "mouse_", 1, true) then
        return
    end
    if bind and bind.submap and bind.submap ~= "" then
        return
    end
    local promote = type(opts.promote) == "table" and opts.promote or {}
    local target = targets[action] or {}
    table.insert(rows, table.concat({
        field(keys),
        field(opts.description or opts.desc),
        field(commands[action]),
        field(promote.class or target.class),
        field(promote.workspace or target.workspace),
    }, "\t") .. "\n")
    write_list()
end

hl.bind = function(keys, action, opts)
    local options = type(opts) == "table" and opts or {}
    local ok, wrapped = pcall(announced, keys, action, options)
    local bind = original_bind(keys, ok and wrapped or action, opts)
    pcall(record, keys, action, options, bind)
    return bind
end

-- Start each config load with an empty list.
pcall(write_list)

-- Tells the plugin's runtime shadow binds that binds already announce themselves.
KEY_PROMOTER_SNIPPET = true

return M
