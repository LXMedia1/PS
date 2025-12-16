local LX_Mover = {}

-- Import dependencies
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local vec3 = require("common/geometry/vector_3")

-- State constants
local STATE = {
    IDLE = "idle",
    MOVING = "moving",
    PAUSED = "paused"
}

-- Plugin state
local menu = nil
local initialized = false
local ui = {}

-- Path data
local saved_paths = {}          -- List of path names from manifest
local current_path = nil        -- Currently loaded path {name, path_type, points}
local current_index = 1         -- Current waypoint index
local path_direction = 1        -- 1 = forward, -1 = backward (for pingpong)

-- Movement state
local state = STATE.IDLE
local is_moving_forward = false
local is_turning_left = false
local is_turning_right = false

-- Settings
local waypoint_threshold = 2.5  -- Distance to consider "arrived" (don't stop, just switch)
local turn_threshold = 0.15     -- Radians - stop turning when angle diff is small
local loop_enabled = true

-- Path file constants (same as PathRecorder)
local PATH_FOLDER = "pathrecorder/"
local MANIFEST_FILE = "pathrecorder/_manifest"

-- Path smoothing settings
local smooth_enabled = true
local smooth_subdivisions = 3  -- Points to add between each original waypoint

-----------------------------------------------------------
-- Path Smoothing (Catmull-Rom Spline)
-----------------------------------------------------------

-- Catmull-Rom spline interpolation
local function catmull_rom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t

    local x = 0.5 * ((2 * p1.x) +
        (-p0.x + p2.x) * t +
        (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)

    local y = 0.5 * ((2 * p1.y) +
        (-p0.y + p2.y) * t +
        (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)

    local z = 0.5 * ((2 * p1.z) +
        (-p0.z + p2.z) * t +
        (2 * p0.z - 5 * p1.z + 4 * p2.z - p3.z) * t2 +
        (-p0.z + 3 * p1.z - 3 * p2.z + p3.z) * t3)

    return {x = x, y = y, z = z}
end

-- Smooth a path using Catmull-Rom splines
local function smooth_path(points, subdivisions, is_loop)
    if #points < 3 then return points end

    local smoothed = {}
    local n = #points

    for i = 1, n do
        -- Get 4 control points for the spline
        local p0, p1, p2, p3

        if is_loop then
            p0 = points[((i - 2) % n) + 1]
            p1 = points[i]
            p2 = points[(i % n) + 1]
            p3 = points[((i + 1) % n) + 1]
        else
            -- Clamp indices for non-looping paths
            p0 = points[math.max(1, i - 1)]
            p1 = points[i]
            p2 = points[math.min(n, i + 1)]
            p3 = points[math.min(n, i + 2)]
        end

        -- Add the original point
        table.insert(smoothed, {x = p1.x, y = p1.y, z = p1.z})

        -- Add subdivided points (except for the last segment in non-loop)
        if is_loop or i < n then
            for j = 1, subdivisions do
                local t = j / (subdivisions + 1)
                local interp = catmull_rom(p0, p1, p2, p3, t)
                table.insert(smoothed, interp)
            end
        end
    end

    return smoothed
end

-----------------------------------------------------------
-- Path Loading (from PathRecorder format)
-----------------------------------------------------------

local function load_path(name)
    local filename = PATH_FOLDER .. name
    local content = core.read_data_file(filename)

    if not content or content == "" then
        core.log_error("[LX_Mover] Could not load path: " .. name)
        return nil
    end

    local path_data = {
        name = name,
        path_type = "loop",
        points = {},
        original_points = {}  -- Keep original for reference
    }

    -- Extract path_type
    local pt = content:match('"path_type":"([^"]+)"')
    if pt then path_data.path_type = pt end

    -- Extract points
    for x, y, z in content:gmatch('"x":([%d%.%-]+),"y":([%d%.%-]+),"z":([%d%.%-]+)') do
        table.insert(path_data.original_points, {
            x = tonumber(x),
            y = tonumber(y),
            z = tonumber(z)
        })
    end

    local original_count = #path_data.original_points

    -- Apply smoothing if enabled
    if smooth_enabled and original_count >= 3 then
        local is_loop = (path_data.path_type == "loop") or loop_enabled
        path_data.points = smooth_path(path_data.original_points, smooth_subdivisions, is_loop)
        core.log(string.format("[LX_Mover] Loaded path '%s': %d points -> %d smoothed",
            name, original_count, #path_data.points))
    else
        path_data.points = path_data.original_points
        core.log("[LX_Mover] Loaded path: " .. name .. " with " .. original_count .. " points")
    end

    return path_data
end

local function refresh_path_list()
    local manifest_content = core.read_data_file(MANIFEST_FILE)
    saved_paths = {}

    if manifest_content and manifest_content ~= "" then
        for name in manifest_content:gmatch("([^\n]+)") do
            if name ~= "" then
                table.insert(saved_paths, name)
            end
        end
    end

    core.log("[LX_Mover] Found " .. #saved_paths .. " saved paths")

    if ui.path_combo then
        ui.path_combo:set_items(saved_paths)
    end

    return saved_paths
end

-----------------------------------------------------------
-- Movement Control (Smooth - No Spam)
-----------------------------------------------------------

local function start_forward()
    if not is_moving_forward then
        core.input.move_forward_start()
        is_moving_forward = true
    end
end

local function stop_forward()
    if is_moving_forward then
        core.input.move_forward_stop()
        is_moving_forward = false
    end
end

local function start_turn_left()
    if not is_turning_left then
        -- Stop right turn first
        if is_turning_right then
            core.input.turn_right_stop()
            is_turning_right = false
        end
        core.input.turn_left_start()
        is_turning_left = true
    end
end

local function start_turn_right()
    if not is_turning_right then
        -- Stop left turn first
        if is_turning_left then
            core.input.turn_left_stop()
            is_turning_left = false
        end
        core.input.turn_right_start()
        is_turning_right = true
    end
end

local function stop_turning()
    if is_turning_left then
        core.input.turn_left_stop()
        is_turning_left = false
    end
    if is_turning_right then
        core.input.turn_right_stop()
        is_turning_right = false
    end
end

local function stop_all_movement()
    stop_forward()
    stop_turning()
end

-- Calculate which way to turn using cross product (more reliable)
-- Returns: positive = turn left, negative = turn right, ~0 = facing target
local function get_turn_direction(player, target_pos)
    local pos = player:get_position()
    local dir = player:get_direction()  -- Player's facing direction vector

    if not pos or not dir then return 0 end

    -- Direction to target
    local to_target_x = target_pos.x - pos.x
    local to_target_y = target_pos.y - pos.y

    -- Normalize
    local len = math.sqrt(to_target_x * to_target_x + to_target_y * to_target_y)
    if len < 0.001 then return 0 end
    to_target_x = to_target_x / len
    to_target_y = to_target_y / len

    -- Cross product (2D): dir.x * to_target.y - dir.y * to_target.x
    -- Positive = target is to the left, Negative = target is to the right
    local cross = dir.x * to_target_y - dir.y * to_target_x

    -- Dot product to check if we're facing roughly the right direction
    local dot = dir.x * to_target_x + dir.y * to_target_y

    -- If dot is very negative, we're facing away - need big turn
    -- If dot is positive and cross is small, we're facing target

    return cross, dot
end

-----------------------------------------------------------
-- Path Following Logic
-----------------------------------------------------------

local function get_current_waypoint()
    if not current_path or not current_path.points then return nil end
    if current_index < 1 or current_index > #current_path.points then return nil end

    local p = current_path.points[current_index]
    return vec3.new(p.x, p.y, p.z)
end

local function advance_to_next_waypoint()
    -- Move to next waypoint based on direction (NO STOPPING)
    current_index = current_index + path_direction

    local num_points = #current_path.points

    -- Handle path boundaries
    if path_direction == 1 and current_index > num_points then
        if current_path.path_type == "loop" or loop_enabled then
            current_index = 1
        elseif current_path.path_type == "pingpong" then
            path_direction = -1
            current_index = num_points - 1
        else
            state = STATE.IDLE
            stop_all_movement()
            core.log("[LX_Mover] Path complete")
            return false
        end
    elseif path_direction == -1 and current_index < 1 then
        if current_path.path_type == "pingpong" then
            path_direction = 1
            current_index = 2
        else
            current_index = num_points
        end
    end

    return true
end

local function find_closest_waypoint()
    if not current_path or #current_path.points == 0 then return 1 end

    local player = core.object_manager.get_local_player()
    if not player then return 1 end

    local pos = player:get_position()
    if not pos then return 1 end

    local closest_index = 1
    local closest_dist = math.huge

    for i, p in ipairs(current_path.points) do
        local wp = vec3.new(p.x, p.y, p.z)
        local dist = pos:dist_to(wp)
        if dist < closest_dist then
            closest_dist = dist
            closest_index = i
        end
    end

    core.log(string.format("[LX_Mover] Closest waypoint is #%d at distance %.1f", closest_index, closest_dist))
    return closest_index
end

local function start_path()
    if not current_path or #current_path.points == 0 then
        core.log_warning("[LX_Mover] No path loaded")
        return
    end

    -- Find closest waypoint to start from
    current_index = find_closest_waypoint()
    path_direction = 1
    state = STATE.MOVING

    -- Start moving forward immediately
    start_forward()

    core.log(string.format("[LX_Mover] Started path '%s' from point #%d", current_path.name, current_index))
end

local function pause_path()
    if state == STATE.MOVING then
        stop_all_movement()
        state = STATE.PAUSED
        core.log("[LX_Mover] Paused")
    end
end

local function resume_path()
    if state == STATE.PAUSED then
        state = STATE.MOVING
        start_forward()
        core.log("[LX_Mover] Resumed")
    end
end

local function stop_path()
    stop_all_movement()
    state = STATE.IDLE
    current_index = 1
    path_direction = 1
    core.log("[LX_Mover] Stopped")
end

-----------------------------------------------------------
-- Main Update Loop
-----------------------------------------------------------

-- Smooth turning settings
local turn_speed = 0.15  -- How fast to turn (0-1, higher = faster)

local function update_movement()
    if state ~= STATE.MOVING then return end
    if not current_path then return end

    local player = core.object_manager.get_local_player()
    if not player then return end

    local pos = player:get_position()
    if not pos then return end

    local target = get_current_waypoint()
    if not target then
        stop_path()
        return
    end

    -- Calculate distance to current waypoint
    local distance = pos:dist_to(target)

    -- Check if we've arrived at waypoint (NO STOPPING - just advance)
    if distance < waypoint_threshold then
        core.log(string.format("[LX_Mover] Reached point %d, dist=%.1f", current_index, distance))
        advance_to_next_waypoint()
        -- Get next target immediately for smooth transition
        target = get_current_waypoint()
        if not target then return end
        distance = pos:dist_to(target)
    end

    -- Make sure we're moving forward
    start_forward()

    -- Get player's current facing direction
    local dir = player:get_direction()
    if not dir then return end

    -- Calculate direction to target
    local to_target_x = target.x - pos.x
    local to_target_y = target.y - pos.y
    local to_target_z = target.z - pos.z

    -- Normalize target direction
    local len = math.sqrt(to_target_x * to_target_x + to_target_y * to_target_y + to_target_z * to_target_z)
    if len < 0.001 then return end
    to_target_x = to_target_x / len
    to_target_y = to_target_y / len
    to_target_z = to_target_z / len

    -- Interpolate (lerp) between current direction and target direction
    local new_dir_x = dir.x + (to_target_x - dir.x) * turn_speed
    local new_dir_y = dir.y + (to_target_y - dir.y) * turn_speed
    local new_dir_z = dir.z + (to_target_z - dir.z) * turn_speed

    -- Create a point to look at (current position + interpolated direction * some distance)
    local look_distance = 10  -- Look 10 units ahead
    local look_point = vec3.new(
        pos.x + new_dir_x * look_distance,
        pos.y + new_dir_y * look_distance,
        pos.z + new_dir_z * look_distance
    )

    -- Smooth look_at the interpolated point
    core.input.look_at(look_point)

    -- Log occasionally for debugging
    local cross, dot = get_turn_direction(player, target)
    if math.abs(cross) > 0.1 then
        core.log(string.format("[LX_Mover] Turning to point %d, cross=%.2f, dot=%.2f",
            current_index, cross, dot))
    end
end

-----------------------------------------------------------
-- Path Visualization
-----------------------------------------------------------

local function render_path()
    if not current_path or #current_path.points == 0 then return end

    local player = core.object_manager.get_local_player()
    local player_pos = player and player:get_position() or nil

    -- Colors
    local col_original = color.new(255, 80, 80, 150)       -- Red - original path
    local col_original_point = color.new(255, 100, 100, 200)
    local col_smooth = color.new(0, 200, 100, 200)         -- Green - smoothed path
    local col_current = color.new(255, 220, 0, 255)        -- Yellow - current target
    local col_player_line = color.new(255, 255, 0, 200)

    -- ========== DRAW ORIGINAL PATH (RED) ==========
    if current_path.original_points and #current_path.original_points > 0 then
        local orig_2d = {}

        -- Convert original points to screen
        for i, p in ipairs(current_path.original_points) do
            local world_pos = vec3.new(p.x, p.y, p.z)
            local screen = core.graphics.w2s(world_pos)
            if screen and screen.x > 0 and screen.y > 0 then
                orig_2d[i] = {x = screen.x, y = screen.y, valid = true}
            else
                orig_2d[i] = {valid = false}
            end
        end

        -- Draw original path lines
        for i = 1, #current_path.original_points - 1 do
            if orig_2d[i].valid and orig_2d[i + 1].valid then
                core.graphics.line_2d(
                    vec2.new(orig_2d[i].x, orig_2d[i].y),
                    vec2.new(orig_2d[i + 1].x, orig_2d[i + 1].y),
                    col_original,
                    2
                )
            end
        end

        -- Draw closing line for loop
        if (current_path.path_type == "loop" or loop_enabled) and #current_path.original_points > 2 then
            local first = orig_2d[1]
            local last = orig_2d[#current_path.original_points]
            if first.valid and last.valid then
                core.graphics.line_2d(
                    vec2.new(last.x, last.y),
                    vec2.new(first.x, first.y),
                    col_original,
                    2
                )
            end
        end

        -- Draw original waypoint markers
        for i, p2d in ipairs(orig_2d) do
            if p2d.valid then
                core.graphics.circle_2d_filled(
                    vec2.new(p2d.x, p2d.y),
                    5,
                    col_original_point
                )
            end
        end
    end

    -- ========== DRAW SMOOTHED PATH (GREEN) ==========
    local points_2d = {}

    -- Convert smoothed points to screen coordinates
    for i, p in ipairs(current_path.points) do
        local world_pos = vec3.new(p.x, p.y, p.z)
        local screen = core.graphics.w2s(world_pos)
        if screen and screen.x > 0 and screen.y > 0 then
            points_2d[i] = {x = screen.x, y = screen.y, valid = true}
        else
            points_2d[i] = {valid = false}
        end
    end

    -- Draw smoothed path lines
    for i = 1, #current_path.points - 1 do
        if points_2d[i].valid and points_2d[i + 1].valid then
            core.graphics.line_2d(
                vec2.new(points_2d[i].x, points_2d[i].y),
                vec2.new(points_2d[i + 1].x, points_2d[i + 1].y),
                col_smooth,
                2
            )
        end
    end

    -- Draw closing line for loop paths
    if (current_path.path_type == "loop" or loop_enabled) and #current_path.points > 2 then
        local first = points_2d[1]
        local last = points_2d[#current_path.points]
        if first.valid and last.valid then
            core.graphics.line_2d(
                vec2.new(last.x, last.y),
                vec2.new(first.x, first.y),
                col_smooth,
                2
            )
        end
    end

    -- Draw line from player to current target
    if state == STATE.MOVING and player_pos then
        local target = get_current_waypoint()
        if target then
            local player_screen = core.graphics.w2s(player_pos)
            local target_screen = core.graphics.w2s(target)
            if player_screen and target_screen and player_screen.x > 0 and target_screen.x > 0 then
                core.graphics.line_2d(
                    vec2.new(player_screen.x, player_screen.y),
                    vec2.new(target_screen.x, target_screen.y),
                    col_player_line,
                    3
                )
            end
        end
    end

    -- Draw current target marker (yellow, larger)
    if current_index >= 1 and current_index <= #current_path.points then
        local p2d = points_2d[current_index]
        if p2d and p2d.valid then
            core.graphics.circle_2d_filled(
                vec2.new(p2d.x, p2d.y),
                8,
                col_current
            )
        end
    end
end

-----------------------------------------------------------
-- UI Setup
-----------------------------------------------------------

local function init()
    if initialized then return end

    local LX_UI = _G.LX_UI
    if not LX_UI then return end

    initialized = true
    refresh_path_list()

    -- Layout
    local menu_w = 340
    local menu_h = 280
    local p = 12
    local btn_h = 28

    menu = LX_UI.Menu:new("LX Mover", menu_w, menu_h, "lx_mover")
    menu.auto_height = false
    menu.height = menu_h

    local Label = LX_UI.Label
    local Button = LX_UI.Button
    local Combobox = LX_UI.Combobox
    local Checkbox = LX_UI.Checkbox
    local ProgressBar = LX_UI.ProgressBar

    local y = 38

    -- Path Selection Section
    local header1 = Label:new({
        text = "PATH SELECTION",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 18,
        font_size = 11
    })
    menu:add_component(header1)
    y = y + 24

    -- Path dropdown
    ui.path_combo = Combobox:new({
        text = "",
        x = p,
        y = y,
        width = menu_w - p*2 - 70,
        height = 24,
        items = saved_paths,
        default = 1,
        on_change = function(comp, value, text)
            if text and text ~= "" then
                current_path = load_path(text)
                current_index = 1
                path_direction = 1
                state = STATE.IDLE
            end
        end
    })
    menu:add_component(ui.path_combo)

    -- Refresh button
    ui.refresh_btn = Button:new({
        text = "Refresh",
        x = menu_w - p - 65,
        y = y,
        width = 65,
        height = 24,
        on_click = function()
            refresh_path_list()
        end
    })
    menu:add_component(ui.refresh_btn)
    y = y + 32

    -- Path info label
    ui.path_info = Label:new({
        text = "No path loaded",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 18
    })
    menu:add_component(ui.path_info)
    y = y + 28

    -- Controls Section
    local header2 = Label:new({
        text = "CONTROLS",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 18,
        font_size = 11
    })
    menu:add_component(header2)
    y = y + 24

    -- Play/Pause/Stop buttons
    local btn_w = (menu_w - p*2 - 12) / 3

    ui.play_btn = Button:new({
        text = "Play",
        x = p,
        y = y,
        width = btn_w,
        height = btn_h,
        style = "primary",
        on_click = function()
            if state == STATE.IDLE then
                start_path()
            elseif state == STATE.PAUSED then
                resume_path()
            end
        end
    })
    menu:add_component(ui.play_btn)

    ui.pause_btn = Button:new({
        text = "Pause",
        x = p + btn_w + 6,
        y = y,
        width = btn_w,
        height = btn_h,
        on_click = function()
            pause_path()
        end
    })
    menu:add_component(ui.pause_btn)

    ui.stop_btn = Button:new({
        text = "Stop",
        x = p + (btn_w + 6) * 2,
        y = y,
        width = btn_w,
        height = btn_h,
        on_click = function()
            stop_path()
        end
    })
    menu:add_component(ui.stop_btn)
    y = y + btn_h + 10

    -- Progress bar
    ui.progress = ProgressBar:new({
        text = "Progress",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 16,
        value = 0,
        max_value = 100
    })
    menu:add_component(ui.progress)
    y = y + 28

    -- Settings Section
    local header3 = Label:new({
        text = "SETTINGS",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 18,
        font_size = 11
    })
    menu:add_component(header3)
    y = y + 24

    -- Loop checkbox
    ui.loop_check = Checkbox:new({
        text = "Loop continuously",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 20,
        default = true,
        on_change = function(comp, value)
            loop_enabled = value
        end
    })
    menu:add_component(ui.loop_check)
    y = y + 28

    -- Status label
    ui.status = Label:new({
        text = "Status: Idle",
        x = p,
        y = menu_h - 30,
        width = menu_w - p*2,
        height = 18
    })
    menu:add_component(ui.status)

    -- Load first path if available
    if #saved_paths > 0 then
        current_path = load_path(saved_paths[1])
    end

    core.log("[LX_Mover] Initialized")
end

-----------------------------------------------------------
-- Update UI
-----------------------------------------------------------

local function update_ui()
    if not ui.path_info then return end

    -- Update path info
    if current_path then
        local type_str = current_path.path_type == "loop" and "Loop" or "Ping-Pong"
        ui.path_info:set_value(#current_path.points .. " points | " .. type_str)
    else
        ui.path_info:set_value("No path loaded")
    end

    -- Update progress
    if current_path and #current_path.points > 0 then
        local progress = (current_index / #current_path.points) * 100
        ui.progress:set_value(math.floor(progress))
    else
        ui.progress:set_value(0)
    end

    -- Update status
    local status_text = "Status: "
    if state == STATE.IDLE then
        status_text = status_text .. "Idle"
    elseif state == STATE.MOVING then
        status_text = status_text .. "Moving to point " .. current_index
    elseif state == STATE.PAUSED then
        status_text = status_text .. "Paused at point " .. current_index
    elseif state == STATE.TRANSITIONING then
        status_text = status_text .. "Transitioning..."
    end
    ui.status:set_value(status_text)

    -- Update button text
    if ui.play_btn then
        if state == STATE.PAUSED then
            ui.play_btn.text = "Resume"
        else
            ui.play_btn.text = "Play"
        end
    end
end

-----------------------------------------------------------
-- Callbacks
-----------------------------------------------------------

local function on_update()
    if not initialized then
        init()
        return
    end

    if menu then
        menu:update()
    end

    update_movement()
    update_ui()
end

local function on_render()
    if not initialized then
        init()
    end

    if menu and menu.is_open then
        menu:render()
    end

    -- Always render path visualization when a path is loaded
    render_path()
end

-----------------------------------------------------------
-- Register
-----------------------------------------------------------

core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)

core.log("[LX_Mover] Plugin loaded")

return LX_Mover
