--!nonstrict
-- A fake Noctalia host. tests/service_test.sh joins this file, service.luau and
-- tests/service_cases.luau into one script, since luau cannot require a service.
host = {
    now = 0,
    files = {},
    notes = {},
    logs = {},
    async = {},
    json = {},
    stream = nil,
    streamCommand = "",
    state = {},
    toggles = 0,
    toggleLog = {},
    encoded = 0,
    clock = 1800000000, -- os.time() in seconds
    config = {
        notifications = true,
        app_launches = true,
        workspace_switches = true,
        suggest_after = 5,
    },
    settings = { ["shell.launch_apps_custom_command"] = "key-promoter-launch $CMD" },
    env = { XDG_RUNTIME_DIR = "/run/user/1000", HYPRLAND_INSTANCE_SIGNATURE = "abc" },
}

host.files["/run/user/1000/hypr-key-promoter.tsv"] = table.concat({
    "SUPER + SHIFT + Z\tOpen Zed\tuwsm-app -- zeditor\t\t",
    "SUPER + 3\tSwitch to local workspace 3\t\t\t",
}, "\n") .. "\n"

-- Wall-clock time for the saved launch counts.
os = { time = function() return host.clock end }

-- Reads back a file the service saved as JSON.
function saved(path)
    return host.json[host.files[path] or ""]
end

noctalia = {
    pluginDataDir = function() return "/data" end,
    readFile = function(path) return host.files[path] end,
    writeFile = function(path, text)
        host.files[path] = text
        return true
    end,
    mkdirAll = function() return true end,
    -- JSON text in the tests is a key into host.json; encode stores a copy of
    -- the table under a fresh key, so saved files can be read back.
    json = {
        decode = function(text)
            local value = host.json[text]
            if value == nil then error("not JSON") end
            return value
        end,
        encode = function(value)
            host.encoded += 1
            local key = `encoded{host.encoded}`
            host.json[key] = value
            return key
        end,
    },
    getConfig = function(key) return host.config[key] end,
    getSetting = function(key) return host.settings[key] end,
    getenv = function(name) return host.env[name] end,
    nowMs = function() return host.now end,
    notify = function(title, body) table.insert(host.notes, { title = title, body = body }) end,
    log = function(message) table.insert(host.logs, message) end,
    runStream = function(command, onLine)
        host.streamCommand = command
        host.stream = onLine
    end,
    runAsync = function(argv, callback) table.insert(host.async, { argv = argv, callback = callback }) end,
    setUpdateInterval = function(ms) host.interval = ms end,
    togglePanel = function(id)
        host.toggles += 1
        host.toggled = id
        table.insert(host.toggleLog, (string.gsub(id, "^furyfree/key%-promoter:hint%-box%-", "")))
    end,
    state = {
        set = function(key, value) host.state[key] = value end,
        get = function(key) return host.state[key] end,
        watch = function() end,
    },
}
