local LX_Demo = {}

local menu = nil
local initialized = false

local function init()
    if initialized then return end

    local LX_UI = _G.LX_UI
    if not LX_UI then return end

    initialized = true

    -- Create main menu window
    menu = LX_UI.Menu:new("LX_UI Demo", 320, 500, "lx_demo")

    -- Header section
    menu:add_header("General Settings")

    -- Checkbox
    local enable_cb = menu:add_checkbox("Enable Feature", nil, nil, true, function(comp, value)
        core.log("[Demo] Enable: " .. tostring(value))
    end)

    -- Another checkbox
    menu:add_checkbox("Show Overlay", nil, nil, false, function(comp, value)
        core.log("[Demo] Overlay: " .. tostring(value))
    end)

    -- Separator
    menu:add_separator()

    -- Slider section
    menu:add_header("Values")

    -- Integer slider
    local volume_slider = menu:add_slider("Volume", nil, nil, 0, 100, 75, function(comp, value)
        core.log("[Demo] Volume: " .. value)
    end)

    -- Another slider
    menu:add_slider("Speed", nil, nil, 1, 10, 5, function(comp, value)
        core.log("[Demo] Speed: " .. value)
    end)

    menu:add_separator()

    -- Combobox
    menu:add_header("Selection")

    menu:add_combobox("Mode", nil, nil, {"Easy", "Normal", "Hard", "Expert"}, 2, function(comp, value, text)
        core.log("[Demo] Mode: " .. text)
    end)

    -- Listbox
    menu:add_listbox("Targets", nil, nil, {"Player", "NPC", "Enemy", "All"}, 1, function(comp, value, text)
        core.log("[Demo] Target: " .. tostring(text))
    end, {height = 80})

    menu:add_separator()

    -- Input section
    menu:add_header("Input")

    -- Text input
    menu:add_textinput("Name", nil, nil, "Player1", function(comp, value)
        core.log("[Demo] Name: " .. value)
    end)

    -- Keybind
    menu:add_keybind("Toggle Key", nil, nil, 0x54, function(comp, key)
        core.log("[Demo] Key bound: " .. key)
    end)

    menu:add_separator()

    -- Visual section
    menu:add_header("Visual")

    -- Color picker
    menu:add_colorpicker("Highlight Color", nil, nil, {r = 255, g = 100, b = 50, a = 255}, function(comp, color)
        core.log("[Demo] Color: R=" .. color.r .. " G=" .. color.g .. " B=" .. color.b)
    end)

    -- Progress bar
    local progress = menu:add_progressbar("Loading", nil, nil, 65, 100)

    menu:add_separator()

    -- Tree node with nested content
    menu:add_header("Advanced")

    local tree = menu:add_treenode("More Options", nil, nil, false, function(comp, expanded)
        core.log("[Demo] Tree expanded: " .. tostring(expanded))
    end)

    menu:add_separator()

    -- Buttons
    menu:add_button("Save Settings", nil, nil, 140, 28, function()
        menu:save_all()
        core.log("[Demo] Settings saved!")
    end)

    menu:add_button("Reset Defaults", nil, nil, 140, 28, function()
        core.log("[Demo] Reset clicked!")
    end)

    -- Info label at bottom
    menu:add_separator()
    menu:add_label("LX_UI v" .. LX_UI.VERSION)

    core.log("[LX_Demo] UI initialized with " .. #menu.component_order .. " components")
end

-- Render callback
local function on_render()
    if not initialized then
        init()
    end

    if menu then
        menu:render()
    end
end

-- Update callback
local function on_update()
    if not initialized then
        init()
    end

    if menu then
        menu:update()
    end
end

-- Register callbacks
core.register_on_render_callback(on_render)
core.register_on_update_callback(on_update)

core.log("[LX_Demo] Plugin loaded")

return LX_Demo
