local Lx_PathRecorder = {}

-- Import color and vectors
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local vec3 = require("common/geometry/vector_3")

local menu = nil
local initialized = false

-- Current state
local current_path = {
    name = "New Path",
    path_type = "loop", -- "loop" or "pingpong"
    points = {}
}

local saved_paths = {} -- List of saved path names
local selected_path_index = 0
local selected_point_index = 0
local is_recording = false
local last_record_key_state = false

-- UI Components
local ui = {}

-- Path folder for saved paths
local PATH_FOLDER = "pathrecorder/"
local MANIFEST_FILE = "pathrecorder/_manifest"

-- Colors for rendering
local COLOR_POINT = color.new(0, 255, 0, 255)
local COLOR_POINT_SELECTED = color.new(255, 255, 0, 255)
local COLOR_LINE = color.new(0, 200, 0, 200)
local COLOR_LINE_CLOSE = color.new(0, 150, 255, 200)

-----------------------------------------------------------
-- File Operations
-----------------------------------------------------------

local function ensure_folder_exists()
    if core.create_data_folder then
        core.create_data_folder(PATH_FOLDER)
    end
end

local function get_path_filename(name)
    return PATH_FOLDER .. name
end

local function save_path(path_data)
    if not path_data or not path_data.name or path_data.name == "" then
        core.log_error("[PathRecorder] Cannot save path: invalid name")
        return false
    end

    ensure_folder_exists()
    local filename = get_path_filename(path_data.name)

    -- Build save string manually (simple JSON)
    local points_str = "["
    for i, p in ipairs(path_data.points) do
        if i > 1 then points_str = points_str .. "," end
        points_str = points_str .. string.format('{"x":%.2f,"y":%.2f,"z":%.2f}', p.x, p.y, p.z)
    end
    points_str = points_str .. "]"

    local json_str = string.format(
        '{"name":"%s","path_type":"%s","points":%s}',
        path_data.name,
        path_data.path_type or "loop",
        points_str
    )

    if core.create_data_file then
        core.create_data_file(filename)
    end
    core.write_data_file(filename, json_str)
    core.log("[PathRecorder] Saved path: " .. path_data.name .. " with " .. #path_data.points .. " points")
    return true
end

local function load_path(name)
    local filename = get_path_filename(name)
    local content = core.read_data_file(filename)

    if not content or content == "" then
        core.log_error("[PathRecorder] Could not load path: " .. name)
        return nil
    end

    -- Simple JSON parse for our format
    local path_data = {
        name = name,
        path_type = "loop",
        points = {}
    }

    -- Extract path_type
    local pt = content:match('"path_type":"([^"]+)"')
    if pt then path_data.path_type = pt end

    -- Extract points
    for x, y, z in content:gmatch('"x":([%d%.%-]+),"y":([%d%.%-]+),"z":([%d%.%-]+)') do
        table.insert(path_data.points, {
            x = tonumber(x),
            y = tonumber(y),
            z = tonumber(z)
        })
    end

    core.log("[PathRecorder] Loaded path: " .. name .. " with " .. #path_data.points .. " points")
    return path_data
end

local function delete_path_file(name)
    local filename = get_path_filename(name)
    -- Write empty to "delete"
    core.write_data_file(filename, "")
    core.log("[PathRecorder] Deleted path: " .. name)
end

local function refresh_path_list()
    -- Ensure folder exists
    ensure_folder_exists()

    -- Read manifest file
    local manifest_content = core.read_data_file(MANIFEST_FILE)
    saved_paths = {}

    if manifest_content and manifest_content ~= "" then
        for name in manifest_content:gmatch("([^\n]+)") do
            if name ~= "" then
                table.insert(saved_paths, name)
            end
        end
    end

    core.log("[PathRecorder] Loaded " .. #saved_paths .. " saved paths from manifest")

    -- Update UI if exists
    if ui.saved_path_list then
        ui.saved_path_list:set_items(saved_paths)
    end

    return saved_paths
end

local function save_manifest()
    ensure_folder_exists()
    local content = table.concat(saved_paths, "\n")
    if core.create_data_file then
        core.create_data_file(MANIFEST_FILE)
    end
    core.write_data_file(MANIFEST_FILE, content)
end

local function add_to_manifest(name)
    -- Check if already exists
    for _, n in ipairs(saved_paths) do
        if n == name then return end
    end
    table.insert(saved_paths, name)
    save_manifest()

    -- Update UI
    if ui.saved_path_list then
        ui.saved_path_list:set_items(saved_paths)
    end
end

local function remove_from_manifest(name)
    for i, n in ipairs(saved_paths) do
        if n == name then
            table.remove(saved_paths, i)
            save_manifest()
            return
        end
    end
end

-----------------------------------------------------------
-- Path Operations
-----------------------------------------------------------

local function add_point()
    local player = core.object_manager.get_local_player()
    if not player then return end

    local pos = player:get_position()
    if not pos then return end

    table.insert(current_path.points, {
        x = pos.x,
        y = pos.y,
        z = pos.z
    })

    core.log("[PathRecorder] Added point #" .. #current_path.points ..
             string.format(" at (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z))

    -- Update point list if UI exists
    if ui.point_list then
        local items = {}
        for i, p in ipairs(current_path.points) do
            table.insert(items, string.format("#%d (%.0f, %.0f)", i, p.x, p.y))
        end
        ui.point_list:set_items(items)
    end
end

local function delete_point(index)
    if index > 0 and index <= #current_path.points then
        table.remove(current_path.points, index)
        core.log("[PathRecorder] Deleted point #" .. index)

        -- Update UI
        if ui.point_list then
            local items = {}
            for i, p in ipairs(current_path.points) do
                table.insert(items, string.format("#%d (%.0f, %.0f)", i, p.x, p.y))
            end
            ui.point_list:set_items(items)
        end
    end
end

local function clear_points()
    current_path.points = {}
    selected_point_index = 0
    core.log("[PathRecorder] Cleared all points")

    if ui.point_list then
        ui.point_list:set_items({})
    end
end

local function connect_to_start()
    current_path.path_type = "loop"
    core.log("[PathRecorder] Path type set to: loop (connects end to start)")
    if ui.path_type_combo then
        ui.path_type_combo:set_value(1)
    end
end

local function set_pingpong()
    current_path.path_type = "pingpong"
    core.log("[PathRecorder] Path type set to: pingpong (reverses at ends)")
    if ui.path_type_combo then
        ui.path_type_combo:set_value(2)
    end
end

local function new_path()
    current_path = {
        name = "New Path",
        path_type = "loop",
        points = {}
    }
    selected_point_index = 0
    is_recording = false

    if ui.path_name_input then
        ui.path_name_input:set_value("New Path")
    end
    if ui.point_list then
        ui.point_list:set_items({})
    end

    core.log("[PathRecorder] Created new path")
end

-----------------------------------------------------------
-- Initialize UI
-----------------------------------------------------------

-- Layout dimensions (stored for custom render)
local layout = {
    menu_w = 520,
    menu_h = 380,
    padding = 12,
    title_h = 28,
    -- Panel positions (relative to menu)
    panels = {}
}

local function init()
    if initialized then return end

    local LX_UI = _G.LX_UI
    if not LX_UI then return end

    initialized = true
    refresh_path_list()

    local p = layout.padding
    local menu_w = layout.menu_w
    local menu_h = layout.menu_h

    menu = LX_UI.Menu:new("Path Recorder", menu_w, menu_h, "lx_path_recorder")
    menu.auto_height = false
    menu.height = menu_h

    -- Component shortcuts
    local Label = LX_UI.Label
    local TextInput = LX_UI.TextInput
    local Combobox = LX_UI.Combobox
    local Button = LX_UI.Button
    local Listbox = LX_UI.Listbox
    local Checkbox = LX_UI.Checkbox
    local Keybind = LX_UI.Keybind

    local btn_h = 26

    -- ============================================
    -- TOP ROW: Path Settings (Name + Type + Recording)
    -- ============================================
    local top_y = layout.title_h + p
    local top_panel_h = 70

    layout.panels.top = {x = p, y = top_y, w = menu_w - p*2, h = top_panel_h}

    -- Name input (left)
    ui.path_name_input = TextInput:new({
        text = "Path Name",
        x = p + 8,
        y = top_y + 8,
        width = 180,
        height = 24,
        default = "New Path",
        on_change = function(comp, value)
            current_path.name = value
        end
    })
    menu:add_component(ui.path_name_input)

    -- Type combo (middle)
    ui.path_type_combo = Combobox:new({
        text = "Type",
        x = p + 200,
        y = top_y + 8,
        width = 130,
        height = 24,
        items = {"Loop", "Ping-Pong"},
        default = 1,
        on_change = function(comp, value, text)
            current_path.path_type = value == 1 and "loop" or "pingpong"
        end
    })
    menu:add_component(ui.path_type_combo)

    -- Recording toggle (right side)
    ui.record_toggle = Checkbox:new({
        text = "REC",
        x = p + 345,
        y = top_y + 10,
        width = 60,
        height = 20,
        default = false,
        on_change = function(comp, value)
            is_recording = value
        end
    })
    menu:add_component(ui.record_toggle)

    -- Record keybind
    ui.record_key = Keybind:new({
        text = "Key",
        x = p + 410,
        y = top_y + 8,
        width = 75,
        height = 24,
        default = 0x52
    })
    menu:add_component(ui.record_key)

    -- Bottom row of top panel: action buttons
    local action_y = top_y + 40
    local action_btn_w = 80

    ui.new_btn = Button:new({
        text = "New",
        x = p + 8,
        y = action_y,
        width = action_btn_w,
        height = btn_h,
        on_click = function() new_path() end
    })
    menu:add_component(ui.new_btn)

    ui.save_btn = Button:new({
        text = "Save",
        x = p + 8 + action_btn_w + 6,
        y = action_y,
        width = action_btn_w,
        height = btn_h,
        style = "primary",
        on_click = function()
            if current_path.name and current_path.name ~= "" and #current_path.points > 0 then
                if ui.path_name_input then
                    current_path.name = ui.path_name_input:get_value()
                end
                if save_path(current_path) then
                    add_to_manifest(current_path.name)
                    ui.saved_path_list:set_items(saved_paths)
                end
            end
        end
    })
    menu:add_component(ui.save_btn)

    ui.add_point_btn = Button:new({
        text = "Add Point",
        x = p + 8 + (action_btn_w + 6) * 2,
        y = action_y,
        width = action_btn_w + 10,
        height = btn_h,
        style = "primary",
        on_click = function() add_point() end
    })
    menu:add_component(ui.add_point_btn)

    -- ============================================
    -- MAIN AREA: Two panels side by side
    -- ============================================
    local main_y = top_y + top_panel_h + p
    local main_h = menu_h - main_y - p - 30 -- leave space for status
    local left_w = 250
    local right_w = menu_w - p*2 - left_w - p

    -- LEFT PANEL: Current Points
    layout.panels.left = {x = p, y = main_y, w = left_w, h = main_h}

    local points_list_h = main_h - 50

    ui.point_list = Listbox:new({
        text = "Points",
        x = p + 8,
        y = main_y + 8,
        width = left_w - 16,
        height = points_list_h,
        items = {},
        default = 0,
        on_change = function(comp, value, text)
            selected_point_index = value
        end
    })
    menu:add_component(ui.point_list)

    -- Point action buttons
    local pts_btn_y = main_y + points_list_h + 12
    local pts_btn_w = (left_w - 24) / 2

    ui.del_point_btn = Button:new({
        text = "Delete Point",
        x = p + 8,
        y = pts_btn_y,
        width = pts_btn_w - 3,
        height = btn_h,
        on_click = function()
            if selected_point_index > 0 then
                delete_point(selected_point_index)
                selected_point_index = 0
            end
        end
    })
    menu:add_component(ui.del_point_btn)

    ui.clear_btn = Button:new({
        text = "Clear All",
        x = p + 8 + pts_btn_w + 3,
        y = pts_btn_y,
        width = pts_btn_w - 3,
        height = btn_h,
        on_click = function() clear_points() end
    })
    menu:add_component(ui.clear_btn)

    -- RIGHT PANEL: Saved Paths
    local right_x = p + left_w + p
    layout.panels.right = {x = right_x, y = main_y, w = right_w, h = main_h}

    local saved_list_h = main_h - 50

    ui.saved_path_list = Listbox:new({
        text = "Saved",
        x = right_x + 8,
        y = main_y + 8,
        width = right_w - 16,
        height = saved_list_h,
        items = saved_paths,
        default = 0,
        on_change = function(comp, value, text)
            selected_path_index = value
        end
    })
    menu:add_component(ui.saved_path_list)

    -- Saved paths action buttons
    local saved_btn_y = main_y + saved_list_h + 12
    local saved_btn_w = (right_w - 24) / 2

    ui.load_btn = Button:new({
        text = "Load",
        x = right_x + 8,
        y = saved_btn_y,
        width = saved_btn_w - 3,
        height = btn_h,
        style = "primary",
        on_click = function()
            if selected_path_index > 0 and saved_paths[selected_path_index] then
                local loaded = load_path(saved_paths[selected_path_index])
                if loaded then
                    current_path = loaded
                    if ui.path_name_input then
                        ui.path_name_input:set_value(current_path.name)
                    end
                    if ui.path_type_combo then
                        ui.path_type_combo:set_value(current_path.path_type == "loop" and 1 or 2)
                    end
                    if ui.point_list then
                        local items = {}
                        for i, pt in ipairs(current_path.points) do
                            table.insert(items, string.format("#%d (%.0f, %.0f)", i, pt.x, pt.y))
                        end
                        ui.point_list:set_items(items)
                    end
                end
            end
        end
    })
    menu:add_component(ui.load_btn)

    ui.delete_path_btn = Button:new({
        text = "Delete",
        x = right_x + 8 + saved_btn_w + 3,
        y = saved_btn_y,
        width = saved_btn_w - 3,
        height = btn_h,
        on_click = function()
            if selected_path_index > 0 and saved_paths[selected_path_index] then
                local name = saved_paths[selected_path_index]
                delete_path_file(name)
                remove_from_manifest(name)
                ui.saved_path_list:set_items(saved_paths)
                selected_path_index = 0
            end
        end
    })
    menu:add_component(ui.delete_path_btn)

    -- ============================================
    -- BOTTOM: Status bar
    -- ============================================
    ui.status_label = Label:new({
        text = "Ready",
        x = p,
        y = menu_h - 26,
        width = menu_w - p*2,
        height = 18
    })
    menu:add_component(ui.status_label)

    core.log("[Lx_PathRecorder] Initialized")
end

-- Custom panel background rendering
local function render_panels()
    if not menu or not menu.is_open or menu.is_collapsed then return end

    local mx = menu.x
    local my = menu.y
    local panel_bg = color.new(35, 35, 38, 255)
    local panel_border = color.new(55, 55, 60, 255)

    -- Draw panel backgrounds
    for name, panel in pairs(layout.panels) do
        local px = mx + panel.x
        local py = my + panel.y

        -- Panel background
        core.graphics.rect_2d_filled(
            vec2.new(px, py),
            panel.w,
            panel.h,
            panel_bg,
            4
        )

        -- Panel border
        core.graphics.rect_2d(
            vec2.new(px, py),
            panel.w,
            panel.h,
            panel_border,
            1,
            4
        )
    end

    -- Recording indicator (show even when not collapsed)
    if is_recording then
        local rec_x = mx + layout.menu_w - 70
        local rec_y = my + 6
        core.graphics.rect_2d_filled(vec2.new(rec_x, rec_y), 60, 16, color.new(200, 50, 50, 255), 8)
        core.graphics.text_2d("REC", vec2.new(rec_x + 30, rec_y + 2), 11, color.new(255, 255, 255, 255), true)
    end
end

-----------------------------------------------------------
-- Render path visualization
-----------------------------------------------------------

local function render_path()
    if #current_path.points == 0 then return end

    local points_2d = {}

    -- Convert 3D points to screen coordinates
    for i, p in ipairs(current_path.points) do
        local world_pos = vec3.new(p.x, p.y, p.z)
        local pos = core.graphics.w2s(world_pos)
        if pos and pos.x > 0 and pos.y > 0 then
            points_2d[i] = {x = pos.x, y = pos.y, valid = true}
        else
            points_2d[i] = {valid = false}
        end
    end

    -- Draw lines between points
    for i = 1, #current_path.points - 1 do
        if points_2d[i].valid and points_2d[i + 1].valid then
            core.graphics.line_2d(
                vec2.new(points_2d[i].x, points_2d[i].y),
                vec2.new(points_2d[i + 1].x, points_2d[i + 1].y),
                COLOR_LINE,
                2
            )
        end
    end

    -- Draw closing line for loop
    if current_path.path_type == "loop" and #current_path.points > 2 then
        local first = points_2d[1]
        local last = points_2d[#current_path.points]
        if first.valid and last.valid then
            core.graphics.line_2d(
                vec2.new(last.x, last.y),
                vec2.new(first.x, first.y),
                COLOR_LINE_CLOSE,
                2
            )
        end
    end

    -- Draw circles at each point
    for i, p2d in ipairs(points_2d) do
        if p2d.valid then
            local col = (i == selected_point_index) and COLOR_POINT_SELECTED or COLOR_POINT
            core.graphics.circle_2d_filled(
                vec2.new(p2d.x, p2d.y),
                8,
                col
            )
            -- Draw point number
            core.graphics.text_2d(
                tostring(i),
                vec2.new(p2d.x, p2d.y - 15),
                12,
                col,
                true
            )
        end
    end
end

-----------------------------------------------------------
-- Update (handle key press for recording)
-----------------------------------------------------------

local function on_update()
    if not initialized then
        init()
        return
    end

    if menu then
        menu:update()
    end

    -- Update status label with rich info
    if ui.status_label then
        local path_type = current_path.path_type == "loop" and "Loop" or "Ping-Pong"
        local status = string.format("%s | %d points | %s",
            current_path.name or "New Path",
            #current_path.points,
            path_type
        )
        ui.status_label:set_value(status)
    end

    -- Handle record key
    if is_recording and ui.record_key then
        local record_key = ui.record_key:get_value()
        if record_key and record_key > 0 then
            local key_down = core.input.is_key_pressed(record_key)
            if key_down and not last_record_key_state then
                add_point()
            end
            last_record_key_state = key_down
        end
    end
end

-----------------------------------------------------------
-- Render
-----------------------------------------------------------

local function on_render()
    if not initialized then
        init()
    end

    if menu and menu.is_open then
        -- Draw custom panel backgrounds first
        render_panels()

        -- Then render the menu and components
        menu:render()
    end

    -- Always render path if we have points
    render_path()
end

-----------------------------------------------------------
-- Register callbacks
-----------------------------------------------------------

core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)

core.log("[Lx_PathRecorder] Plugin loaded")

return Lx_PathRecorder
