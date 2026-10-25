--!nonstrict
-- Key Promoter toast: shows the current hints as key caps in a small corner box,
-- newest at the bottom. The service sets the "hints" state and opens and
-- closes this panel.

local function keycap(key: string)
    return ui.row({
        paddingH = 8,
        paddingV = 3,
        radius = 6,
        fill = "surface_variant",
        border = "primary/0.4",
        borderWidth = 1,
        align = "center",
    }, {
        ui.label({ text = key, fontSize = 13, fontWeight = "bold", color = "primary" }),
    })
end

local function hintRow(hint)
    local items = {}
    for key in string.gmatch(hint.combo or "", "[^+]+") do
        key = string.match(key, "^%s*(.-)%s*$")
        if key ~= "" then
            table.insert(items, keycap(key))
        end
    end
    table.insert(items, ui.label({
        text = hint.description or "",
        fontSize = 13,
        color = "on_surface",
        maxLines = 1,
        flexGrow = 1,
    }))
    return ui.row({ key = `{hint.at}`, gap = 6, align = "center" }, items)
end

local function render()
    local hints = noctalia.state.get("hints")
    if type(hints) ~= "table" then
        return
    end
    local items = {}
    for _, hint in hints do
        table.insert(items, hintRow(hint))
    end
    pcall(panel.render, ui.column({ gap = 8, justify = "end", flexGrow = 1 }, items))
end

function onOpen()
    render()
end

noctalia.state.watch("hints", render)
