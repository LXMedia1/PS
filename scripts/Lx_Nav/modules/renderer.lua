--[[
    Lx_Nav Renderer
    Author: Lexxer

    Path visualization and debug overlay.
]]

local Config = require("modules/config")
local State = require("modules/state")

-- Common modules
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local vec3 = require("common/geometry/vector_3")

local Renderer = {}

-- Draw a 3D marker at a position
local function draw_marker(pos, marker_color, label)
    if not pos then return end

    local world_pos = vec3.new(pos.x, pos.y, pos.z)
    local screen_pos = core.graphics.w2s(world_pos)

    if screen_pos then
        -- Draw circle at screen position
        local col = color.new(marker_color.r, marker_color.g, marker_color.b, marker_color.a)
        core.graphics.circle_2d_filled(screen_pos, 8, col)

        -- Draw label
        if label then
            local label_pos = vec2.new(screen_pos.x, screen_pos.y - 15)
            core.graphics.text_2d(label, label_pos, 12, col, true)
        end
    end
end

-- Draw path line between waypoints
local function draw_path_line(path)
    if not path or #path < 2 then return end

    local path_color = color.new(
        Config.COLOR_PATH.r,
        Config.COLOR_PATH.g,
        Config.COLOR_PATH.b,
        Config.COLOR_PATH.a
    )

    for i = 2, #path do
        local p1 = path[i-1]
        local p2 = path[i]

        local world1 = vec3.new(p1.x, p1.y, p1.z)
        local world2 = vec3.new(p2.x, p2.y, p2.z)

        core.graphics.line_3d(world1, world2, path_color, Config.PATH_THICKNESS)
    end
end

-- Draw waypoint markers along path
local function draw_waypoints(path)
    if not path or #path == 0 then return end

    local wp_color = Config.COLOR_WAYPOINT

    -- Draw intermediate waypoints (skip start and end)
    for i = 2, #path - 1 do
        draw_marker(path[i], wp_color, nil)
    end
end

-- Render the path visualization
function Renderer.render_path()
    if not State.show_path then return end

    -- Draw start point
    if State.start_point then
        draw_marker(State.start_point, Config.COLOR_START, "START")
    end

    -- Draw end point
    if State.end_point then
        draw_marker(State.end_point, Config.COLOR_END, "END")
    end

    -- Draw path
    if State.path and #State.path > 0 then
        draw_path_line(State.path)
        draw_waypoints(State.path)
    end
end

-- Render debug overlay
function Renderer.render_debug_overlay()
    if not State.show_debug then return end

    local screen_size = core.graphics.get_screen_size()

    local x = 10
    local y = screen_size.y - 200

    local text_color = color.new(255, 255, 255, 255)
    local bg_color = color.new(0, 0, 0, 180)

    -- Background panel
    local panel_width = 250
    local panel_height = 180
    core.graphics.rect_2d_filled(vec2.new(x - 5, y - 5), panel_width, panel_height, bg_color, 4)

    -- Title
    core.graphics.text_2d("Lx_Nav", vec2.new(x, y), 14, text_color, false)
    y = y + 18

    -- Status
    local status_text = "Status: " .. State.get_state_string()
    core.graphics.text_2d(status_text, vec2.new(x, y), 12, text_color, false)
    y = y + 16

    -- Start point
    local start_text = "Start: "
    if State.start_point then
        start_text = start_text .. string.format("(%.0f, %.0f, %.0f)",
            State.start_point.x, State.start_point.y, State.start_point.z)
    else
        start_text = start_text .. "Not set"
    end
    core.graphics.text_2d(start_text, vec2.new(x, y), 11, text_color, false)
    y = y + 14

    -- End point
    local end_text = "End: "
    if State.end_point then
        end_text = end_text .. string.format("(%.0f, %.0f, %.0f)",
            State.end_point.x, State.end_point.y, State.end_point.z)
    else
        end_text = end_text .. "Not set"
    end
    core.graphics.text_2d(end_text, vec2.new(x, y), 11, text_color, false)
    y = y + 14

    -- Search stats
    if State.search_state ~= State.SEARCH_IDLE then
        y = y + 4

        core.graphics.text_2d(
            string.format("Nodes processed: %d", State.stats.nodes_processed),
            vec2.new(x, y), 11, text_color, false
        )
        y = y + 14

        core.graphics.text_2d(
            string.format("Open/Closed: %d / %d", State.stats.nodes_in_open, State.stats.nodes_in_closed),
            vec2.new(x, y), 11, text_color, false
        )
        y = y + 14

        core.graphics.text_2d(
            string.format("Frames: %d", State.stats.frames_elapsed),
            vec2.new(x, y), 11, text_color, false
        )
        y = y + 14
    end

    -- Path info
    if State.path and #State.path > 0 then
        y = y + 4

        core.graphics.text_2d(
            string.format("Path: %d waypoints", #State.path),
            vec2.new(x, y), 11, text_color, false
        )
        y = y + 14

        core.graphics.text_2d(
            string.format("Distance: %.1f yards", State.path_length),
            vec2.new(x, y), 11, text_color, false
        )
    end
end

return Renderer
