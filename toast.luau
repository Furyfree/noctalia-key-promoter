--!nonstrict
-- Key Promoter toast: shows the current hint as key caps in a small corner box.
-- The service sets the "hint" state and opens and closes this panel.

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

local function render()
    local hint = noctalia.state.get("hint")
    if type(hint) ~= "table" then
        return
    end
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
    if hint.count then
        table.insert(items, ui.label({ text = `×{hint.count}`, fontSize = 12, color = "primary" }))
    end
    pcall(panel.render, ui.row({ gap = 6, align = "center", flexGrow = 1 }, items))
end

function onOpen()
    render()
end

noctalia.state.watch("hint", render)
