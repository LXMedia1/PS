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

-- Path data (for nav mode)
local current_path = nil        -- Currently active path from LX_Nav {points}
local current_index = 1         -- Current waypoint index

-- Movement state
local state = STATE.IDLE
local is_moving_forward = false
local is_turning_left = false
local is_turning_right = false

-- Settings
local waypoint_threshold = 2.5  -- Distance to consider "arrived" (don't stop, just switch)
local turn_threshold = 0.15     -- Radians - stop turning when angle diff is small

-- Tab-out detection
local INPUT_BIT_FORWARD = 0x10    -- Input bit for move_forward
local is_tabbed_out = false       -- True when game window loses focus

-- Saved positions constants
local POSITIONS_FILE = "lx_mover_positions"

-- Nav path mode (always uses LX_Nav now)
local nav_mode = true  -- Always use LX_Nav pathfinding
local nav_target_pos = nil  -- Target position for nav mode
local nav_target_object = nil  -- Target object if following a moving target
local nav_last_update = 0  -- Last time path was updated
local saved_positions = {}  -- {name: {x, y, z, map_id}}

-- Path transition state
local old_path = nil  -- Previous path for smooth transitions
local transition_progress = 1.0  -- 0.0 = full old path, 1.0 = full new path
local transition_speed = 1.5  -- How fast to transition (per second)
local path_updating = false  -- True when path is being recalculated

-- Path smoothing settings
local smooth_enabled = true
local smooth_subdivisions = 3  -- Points to add between each original waypoint (balance between smooth and accurate)

-- Click-to-path mode
local click_to_path_mode = false
local prev_mouse_down = false

-----------------------------------------------------------
-- Path Smoothing (Cubic B-spline)
-----------------------------------------------------------

-- Cubic B-spline basis functions
local function bspline_basis(i, t)
    if i == 0 then
        return (1 - t)^3 / 6
    elseif i == 1 then
        return (3 * t^3 - 6 * t^2 + 4) / 6
    elseif i == 2 then
        return (-3 * t^3 + 3 * t^2 + 3 * t + 1) / 6
    elseif i == 3 then
        return t^3 / 6
    end
    return 0
end

-- Cubic B-spline interpolation between 4 control points
local function bspline_cubic(p0, p1, p2, p3, t)
    local b0 = bspline_basis(0, t)
    local b1 = bspline_basis(1, t)
    local b2 = bspline_basis(2, t)
    local b3 = bspline_basis(3, t)

    return {
        x = b0 * p0.x + b1 * p1.x + b2 * p2.x + b3 * p3.x,
        y = b0 * p0.y + b1 * p1.y + b2 * p2.y + b3 * p3.y,
        z = b0 * p0.z + b1 * p1.z + b2 * p2.z + b3 * p3.z
    }
end

-- Smooth a path using Cubic B-splines
local function smooth_path(points, subdivisions, is_loop)
    if #points < 3 then return points end

    local smoothed = {}
    local n = #points

    -- For each segment between control points
    for i = 1, n - 1 do
        -- Get 4 control points for B-spline
        local p0, p1, p2, p3

        if is_loop then
            p0 = points[((i - 2 + n) % n) + 1]
            p1 = points[((i - 1 + n) % n) + 1]
            p2 = points[(i % n) + 1]
            p3 = points[((i + 1) % n) + 1]
        else
            -- Clamp indices for non-looping paths
            p0 = points[math.max(1, i - 1)]
            p1 = points[i]
            p2 = points[math.min(n, i + 1)]
            p3 = points[math.min(n, i + 2)]
        end

        -- Generate interpolated points along the B-spline curve
        for j = 0, subdivisions do
            local t = j / subdivisions
            local interp = bspline_cubic(p0, p1, p2, p3, t)
            table.insert(smoothed, interp)
        end
    end

    -- Add final point if not looping
    if not is_loop then
        table.insert(smoothed, {x = points[n].x, y = points[n].y, z = points[n].z})
    end

    return smoothed
end

-----------------------------------------------------------
-- Saved Positions Management
-----------------------------------------------------------

local function load_saved_positions()
    local content = core.read_data_file(POSITIONS_FILE)
    saved_positions = {}

    if not content or content == "" then
        return
    end

    -- Parse JSON-like format: {"name":{"x":1,"y":2,"z":3,"map_id":1}}
    for name, x, y, z, map_id in content:gmatch('"([^"]+)":%s*{[^}]*"x":([%d%.%-]+),"y":([%d%.%-]+),"z":([%d%.%-]+),"map_id":(%d+)') do
        saved_positions[name] = {
            x = tonumber(x),
            y = tonumber(y),
            z = tonumber(z),
            map_id = tonumber(map_id)
        }
    end
end

local function save_saved_positions()
    local lines = {}
    table.insert(lines, "{")

    local first = true
    for name, pos in pairs(saved_positions) do
        if not first then
            table.insert(lines, ",")
        end
        first = false

        local entry = string.format('"%s":{"x":%.2f,"y":%.2f,"z":%.2f,"map_id":%d}',
            name, pos.x, pos.y, pos.z, pos.map_id)
        table.insert(lines, entry)
    end

    table.insert(lines, "}")
    local content = table.concat(lines, "\n")

    core.create_data_file(POSITIONS_FILE)
    core.write_data_file(POSITIONS_FILE, content)
end

local function save_current_position(name)
    local player = core.object_manager.get_local_player()
    if not player then
        core.log_error("[LX_Mover] No local player")
        return false
    end

    local pos = player:get_position()
    local map_id = core.get_instance_id()

    if not pos or not map_id then
        core.log_error("[LX_Mover] Could not get player position")
        return false
    end

    saved_positions[name] = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        map_id = map_id
    }

    save_saved_positions()
    core.log("[LX_Mover] Saved position: " .. name)
    return true
end

local function delete_saved_position(name)
    if saved_positions[name] then
        saved_positions[name] = nil
        save_saved_positions()
        core.log("[LX_Mover] Deleted position: " .. name)
        return true
    end
    return false
end

-----------------------------------------------------------
-- Nav Path Requests (using LX_Nav)
-----------------------------------------------------------

local function request_nav_path(target_pos)
    local LX_Nav = _G.LX_Nav
    if not LX_Nav then
        core.log_error("[LX_Mover] LX_Nav not available")
        return nil
    end

    -- Request path from LX_Nav
    -- Check if player is mounted and adjust wall distance
    local player = core.object_manager.get_local_player()
    local wall_distance = 2.0  -- Default: 2 yards from walls
    if player and player:is_mounted() then
        wall_distance = 4.0  -- Mounted: 4 yards from walls for wider clearance
    end

    local result = LX_Nav.request_path(target_pos, wall_distance)
    if not result or not result.path then
        core.log_error("[LX_Mover] Failed to get path from LX_Nav")
        return nil
    end

    -- Convert to our format with original points
    local original_points = {}
    for _, p in ipairs(result.path) do
        table.insert(original_points, {x = p.x, y = p.y, z = p.z})
    end

    local path_data = {
        name = "Nav Path",
        path_type = "once",  -- Nav paths are one-time, not loops
        points = {},
        original_points = original_points
    }

    -- Apply B-spline smoothing after wall-aware pathfinding
    -- The funnel path respects navmesh, and B-spline adds final smoothing
    if smooth_enabled and #original_points >= 3 then
        path_data.points = smooth_path(original_points, smooth_subdivisions, false)
    else
        path_data.points = original_points
    end

    core.log(string.format("[LX_Mover] Nav path created with %d waypoints (%d after smoothing, wall_dist=%.1f)",
        #original_points, #path_data.points, wall_distance))
    return path_data
end

local function request_path_to_position(target_pos, target_object)
    local path_data = request_nav_path(target_pos)
    if path_data then
        -- Save old path for smooth transition
        if current_path and nav_mode then
            old_path = current_path
            transition_progress = 0.0
        end

        current_path = path_data
        current_index = 1
        nav_mode = true
        nav_target_pos = target_pos
        nav_target_object = target_object  -- Store object reference if following a moving target
        nav_last_update = core.time and core.time() or 0  -- Initialize update timer
        path_updating = false
    end
    return path_data ~= nil
end

local function request_path_to_saved_position(name)
    local pos = saved_positions[name]
    if not pos then
        core.log_error("[LX_Mover] No saved position with name: " .. name)
        return false
    end

    -- Check if we're on the same map
    local map_id = core.get_instance_id()
    if map_id and map_id ~= pos.map_id then
        core.log_warning(string.format("[LX_Mover] Position %s is on a different map (current: %d, saved: %d)",
            name, map_id, pos.map_id))
        return false
    end

    return request_path_to_position(pos)
end

local function request_path_to_click()
    -- Enable click mode - next mouse click will set target
    core.log("[LX_Mover] Click on the map to set destination...")
    return true
end

local function request_path_to_target()
    local player = core.object_manager.get_local_player()
    if not player then
        core.log_error("[LX_Mover] No local player")
        return false
    end

    local target = player:get_target()
    if not target then
        core.log_error("[LX_Mover] No target selected")
        return false
    end

    local target_pos = target:get_position()
    if not target_pos then
        core.log_error("[LX_Mover] Could not get target position")
        return false
    end

    return request_path_to_position(target_pos, target)
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
    -- Move to next waypoint (NO STOPPING)
    current_index = current_index + 1

    local num_points = #current_path.points

    -- Handle path end (nav paths always stop at destination)
    if current_index > num_points then
        state = STATE.IDLE
        stop_all_movement()
        nav_target_pos = nil
        nav_target_object = nil
        current_path = nil  -- Clear path visualization
        old_path = nil
        core.log("[LX_Mover] Destination reached")
        return false
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

    return closest_index
end

local function start_path()
    if not current_path or #current_path.points == 0 then
        core.log_warning("[LX_Mover] No path loaded")
        return
    end

    -- Find closest waypoint to start from
    current_index = find_closest_waypoint()
    state = STATE.MOVING

    -- Start moving forward immediately
    start_forward()
end

local function pause_path()
    if state == STATE.MOVING then
        stop_all_movement()
        state = STATE.PAUSED
    end
end

local function resume_path()
    if state == STATE.PAUSED then
        state = STATE.MOVING
        start_forward()
    end
end

local function stop_path()
    stop_all_movement()
    state = STATE.IDLE
    current_index = 1
    nav_mode = false
    nav_target_pos = nil
    nav_target_object = nil
end

-----------------------------------------------------------
-- Main Update Loop
-----------------------------------------------------------

-- Base movement parameters (tuned for ~7 units/sec walking speed)
local base_speed = 7
local base_turn_speed = 0.08  -- Smooth direction changes (was 0.15, too fast)
local base_look_distance = 10
local base_threshold = 0.5  -- Reach waypoint before switching (was 2.5, caused corner cutting)

local function update_movement()
    if state ~= STATE.MOVING then return end
    if not current_path then return end

    local player = core.object_manager.get_local_player()
    if not player then return end

    local pos = player:get_position()
    if not pos then return end

    -- Update path transition
    if transition_progress < 1.0 then
        local dt = core.delta_time and core.delta_time() or 0.016
        transition_progress = math.min(1.0, transition_progress + transition_speed * dt)

        -- Clear old path when transition complete
        if transition_progress >= 1.0 then
            old_path = nil
        end
    end

    -- Update path if following a moving target
    if nav_mode and nav_target_object and not path_updating then
        local now = core.time and core.time() or 0
        -- Check target position every 0.5 seconds
        if now - nav_last_update > 0.5 then
            -- Use pcall to safely get position (target may be out of sight or temporarily invalid)
            local success, new_target_pos = pcall(function()
                return nav_target_object:get_position()
            end)

            if success and new_target_pos then
                -- Check if target has moved (> 3 yards)
                local dx = new_target_pos.x - nav_target_pos.x
                local dy = new_target_pos.y - nav_target_pos.y
                local dz = new_target_pos.z - nav_target_pos.z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

                if dist > 3.0 then
                    -- Target moved, recalculate path with smoothing
                    core.log("[LX_Mover] Target moved, updating path...")
                    path_updating = true

                    -- Check if player is mounted and adjust wall distance
                    local player = core.object_manager.get_local_player()
                    local wall_distance = 2.0  -- Default: 2 yards from walls
                    if player and player:is_mounted() then
                        wall_distance = 4.0  -- Mounted: 4 yards from walls
                    end

                    -- Request new path from current position
                    local LX_Nav = _G.LX_Nav
                    if LX_Nav then
                        local result = LX_Nav.request_path(new_target_pos, wall_distance)
                        if result and result.path then
                            -- Convert and apply smoothing
                            local original_points = {}
                            for _, p in ipairs(result.path) do
                                table.insert(original_points, {x = p.x, y = p.y, z = p.z})
                            end

                            local new_path_data = {
                                name = "Nav Path",
                                path_type = "once",
                                points = {},
                                original_points = original_points
                            }

                            -- Apply B-spline smoothing after wall-aware pathfinding
                            if smooth_enabled and #original_points >= 3 then
                                new_path_data.points = smooth_path(original_points, smooth_subdivisions, false)
                            else
                                new_path_data.points = original_points
                            end

                            -- Save old path for smooth transition
                            old_path = current_path
                            transition_progress = 0.0
                            current_path = new_path_data
                            nav_target_pos = new_target_pos

                            -- Find closest waypoint on new path to maintain smooth movement
                            current_index = find_closest_waypoint()
                        end
                    end

                    path_updating = false
                    nav_last_update = now
                end
            end
            nav_last_update = now
        end
    end

    local target = get_current_waypoint()
    if not target then
        stop_path()
        return
    end

    -- Get current movement speed and calculate dynamic parameters
    local move_speed = player:get_movement_speed() or base_speed
    local speed_ratio = move_speed / base_speed

    -- Scale parameters with speed (faster = faster turning, further look-ahead)
    local turn_speed = math.min(base_turn_speed * speed_ratio, 0.5)  -- Cap at 0.5
    local look_distance = math.max(base_look_distance * speed_ratio, 10)  -- Min 10
    local threshold = math.max(math.min(base_threshold * speed_ratio, 8), 2)  -- Clamp 2-8

    -- Calculate 2D distance to current waypoint (ignore Z/height)
    local dx = target.x - pos.x
    local dy = target.y - pos.y
    local distance = math.sqrt(dx*dx + dy*dy)

    -- Check if we've arrived at waypoint (NO STOPPING - just advance)
    if distance < threshold then
        advance_to_next_waypoint()
        -- Get next target immediately for smooth transition
        target = get_current_waypoint()
        if not target then return end
        dx = target.x - pos.x
        dy = target.y - pos.y
        distance = math.sqrt(dx*dx + dy*dy)
    end

    -- Make sure we're moving forward
    start_forward()

    -- Get player's current facing direction
    local dir = player:get_direction()
    if not dir then return end

    -- Calculate 2D direction to target (ignore Z/height)
    local to_target_x = target.x - pos.x
    local to_target_y = target.y - pos.y

    -- Normalize target direction (2D only)
    local len = math.sqrt(to_target_x * to_target_x + to_target_y * to_target_y)
    if len < 0.001 then return end
    to_target_x = to_target_x / len
    to_target_y = to_target_y / len

    -- Interpolate (lerp) between current direction and target direction (X and Y only)
    local new_dir_x = dir.x + (to_target_x - dir.x) * turn_speed
    local new_dir_y = dir.y + (to_target_y - dir.y) * turn_speed
    -- Keep original Z direction (don't try to move up/down artificially)
    local new_dir_z = dir.z

    -- Create a point to look at (current position + interpolated direction * some distance)
    local look_point = vec3.new(
        pos.x + new_dir_x * look_distance,
        pos.y + new_dir_y * look_distance,
        pos.z + new_dir_z * look_distance
    )

    -- Smooth look_at the interpolated point
    core.input.look_at(look_point)
end

-----------------------------------------------------------
-- Tab-Out Detection & Auto-Resume
-----------------------------------------------------------

local last_reactivate_attempt = 0

local function update_tabbed_out()
    -- Only check when we're in moving state
    if state ~= STATE.MOVING then
        is_tabbed_out = false
        return
    end

    -- Check if API function exists
    if not core.input.is_input_bit_active then
        return
    end

    -- Check if input bit is active (game-level forward movement)
    local bit_active = core.input.is_input_bit_active(INPUT_BIT_FORWARD)
    is_tabbed_out = not bit_active

    -- When tabbed out, periodically try to re-activate movement
    if is_tabbed_out then
        local now = core.time and core.time() or 0
        if now - last_reactivate_attempt > 0.2 then
            last_reactivate_attempt = now
            core.input.move_forward_start()
            is_moving_forward = true
        end
    end
end

-----------------------------------------------------------
-- Path Visualization
-----------------------------------------------------------

local function render_path()
    if not current_path or #current_path.points == 0 then return end

    local player = core.object_manager.get_local_player()
    local player_pos = player and player:get_position() or nil
    if not player_pos then return end

    -- Colors
    local col_smooth = color.new(0, 200, 100, 200)  -- Green - smoothed path
    local col_original = color.new(255, 255, 255, 200)  -- White - original funnel path

    local points_2d = {}
    local original_2d = {}
    local display_points = {}

    -- ========== MORPH OLD PATH TO NEW PATH ==========
    if old_path and old_path.points and #old_path.points > 0 and transition_progress < 1.0 then
        -- Simultaneously blend all points with the same transition progress
        local old_count = #old_path.points
        local new_count = #current_path.points
        local t = transition_progress  -- Same blend factor for ALL points

        if old_count == new_count then
            -- Same number of points - direct 1:1 blending
            for i = 1, new_count do
                local old_p = old_path.points[i]
                local new_p = current_path.points[i]

                display_points[i] = {
                    x = old_p.x + (new_p.x - old_p.x) * t,
                    y = old_p.y + (new_p.y - old_p.y) * t,
                    z = old_p.z + (new_p.z - old_p.z) * t
                }
            end
        else
            -- Different number of points - interpolate to match new path length
            for i = 1, new_count do
                local new_p = current_path.points[i]

                -- Map to old path position (proportional)
                local old_t = (i - 1) / math.max(1, new_count - 1)
                local old_index = 1 + old_t * (old_count - 1)
                local old_i1 = math.floor(old_index)
                local old_i2 = math.min(old_count, old_i1 + 1)
                local frac = old_index - old_i1

                -- Interpolate position in old path
                local old_p1 = old_path.points[old_i1]
                local old_p2 = old_path.points[old_i2]
                local old_x = old_p1.x + (old_p2.x - old_p1.x) * frac
                local old_y = old_p1.y + (old_p2.y - old_p1.y) * frac
                local old_z = old_p1.z + (old_p2.z - old_p1.z) * frac

                -- Blend from old to new with same t for all points
                display_points[i] = {
                    x = old_x + (new_p.x - old_x) * t,
                    y = old_y + (new_p.y - old_y) * t,
                    z = old_z + (new_p.z - old_z) * t
                }
            end
        end
    else
        -- No transition, use current path directly
        display_points = current_path.points
    end

    -- Only draw path from current waypoint forward (not backward)
    local start_index = 1
    if current_index and current_index > 0 then
        start_index = current_index  -- Start from current waypoint, not behind
    end

    -- Convert display points to screen coordinates (only from start_index onwards)
    local player_screen = core.graphics.w2s(vec3.new(player_pos.x, player_pos.y, player_pos.z))

    for i = start_index, #display_points do
        local p = display_points[i]
        local world_pos = vec3.new(p.x, p.y, p.z)
        local screen = core.graphics.w2s(world_pos)
        if screen and screen.x > 0 and screen.y > 0 then
            points_2d[i] = {x = screen.x, y = screen.y, valid = true}
        else
            points_2d[i] = {valid = false}
        end
    end

    -- Draw line from player to first waypoint
    if player_screen and player_screen.x > 0 and player_screen.y > 0 and points_2d[start_index] and points_2d[start_index].valid then
        core.graphics.line_2d(
            vec2.new(player_screen.x, player_screen.y),
            vec2.new(points_2d[start_index].x, points_2d[start_index].y),
            col_smooth,
            2
        )
    end

    -- Draw morphing path (only from current position onwards)
    for i = start_index, #display_points - 1 do
        if points_2d[i] and points_2d[i].valid and points_2d[i + 1] and points_2d[i + 1].valid then
            core.graphics.line_2d(
                vec2.new(points_2d[i].x, points_2d[i].y),
                vec2.new(points_2d[i + 1].x, points_2d[i + 1].y),
                col_smooth,
                2
            )
        end
    end

    -- Draw original funnel path (before B-spline smoothing) in white
    if current_path.original_points and #current_path.original_points > 0 then
        -- Convert original points to screen coordinates
        for i = 1, #current_path.original_points do
            local p = current_path.original_points[i]
            local world_pos = vec3.new(p.x, p.y, p.z)
            local screen = core.graphics.w2s(world_pos)
            if screen and screen.x > 0 and screen.y > 0 then
                original_2d[i] = {x = screen.x, y = screen.y, valid = true}
            else
                original_2d[i] = {valid = false}
            end
        end

        -- Draw original path lines
        for i = 1, #current_path.original_points - 1 do
            if original_2d[i] and original_2d[i].valid and original_2d[i + 1] and original_2d[i + 1].valid then
                core.graphics.line_2d(
                    vec2.new(original_2d[i].x, original_2d[i].y),
                    vec2.new(original_2d[i + 1].x, original_2d[i + 1].y),
                    col_original,
                    1  -- Thinner line to differentiate
                )
            end
        end

        -- Draw waypoint markers on original path
        for i = 1, #current_path.original_points do
            if original_2d[i] and original_2d[i].valid then
                core.graphics.circle_2d_filled(
                    vec2.new(original_2d[i].x, original_2d[i].y),
                    3,
                    col_original
                )
            end
        end
    end
end

-----------------------------------------------------------
-- Saved Position Buttons Management
-----------------------------------------------------------

local function refresh_saved_position_buttons()
    if not menu or not ui.saved_pos_y_start then return end

    -- Remove old buttons
    for _, btn_data in ipairs(ui.saved_pos_buttons) do
        if btn_data.btn then
            menu:remove_component(btn_data.btn)
        end
        if btn_data.del_btn then
            menu:remove_component(btn_data.del_btn)
        end
    end
    ui.saved_pos_buttons = {}

    -- Create new buttons for each saved position
    local y = ui.saved_pos_y_start
    local p = 12
    local menu_w = 340
    local btn_h = 24
    local max_buttons = 4  -- Maximum buttons to show

    local count = 0
    for name, pos in pairs(saved_positions) do
        if count >= max_buttons then break end

        local btn_data = {}

        -- Go button (main button)
        btn_data.btn = _G.LX_UI.Button:new({
            text = name,
            x = p,
            y = y,
            width = menu_w - p*2 - 40,
            height = btn_h,
            style = "secondary",
            on_click = function()
                if request_path_to_saved_position(name) then
                    start_path()
                end
            end
        })
        menu:add_component(btn_data.btn)

        -- Delete button (X button on the right)
        btn_data.del_btn = _G.LX_UI.Button:new({
            text = "X",
            x = menu_w - p - 35,
            y = y,
            width = 35,
            height = btn_h,
            on_click = function()
                delete_saved_position(name)
                refresh_saved_position_buttons()
            end
        })
        menu:add_component(btn_data.del_btn)

        table.insert(ui.saved_pos_buttons, btn_data)
        y = y + btn_h + 4
        count = count + 1
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
    load_saved_positions()

    -- Layout
    local menu_w = 340
    local menu_h = 400  -- Compact size (nav mode only)
    local p = 12
    local btn_h = 28

    menu = LX_UI.Menu:new("LX Mover", menu_w, menu_h, "lx_mover")
    menu.auto_height = false
    menu.height = menu_h

    local Label = LX_UI.Label
    local Button = LX_UI.Button
    local ProgressBar = LX_UI.ProgressBar

    local y = 38

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

    -- Nav Path Section
    local header_nav = Label:new({
        text = "NAV PATH (LX_Nav)",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 18,
        font_size = 11
    })
    menu:add_component(header_nav)
    y = y + 24

    -- Nav path buttons (3 buttons in a row)
    local nav_btn_w = (menu_w - p*2 - 12) / 3

    ui.path_to_target_btn = Button:new({
        text = "To Target",
        x = p,
        y = y,
        width = nav_btn_w,
        height = btn_h - 4,
        on_click = function()
            if request_path_to_target() then
                start_path()
            end
        end
    })
    menu:add_component(ui.path_to_target_btn)

    ui.path_to_click_btn = Button:new({
        text = "To Click",
        x = p + nav_btn_w + 6,
        y = y,
        width = nav_btn_w,
        height = btn_h - 4,
        on_click = function()
            click_to_path_mode = true
            -- Consume the button click to prevent it from being treated as the map click
            prev_mouse_down = true
            core.log("[LX_Mover] Click on the map to set destination")
        end
    })
    menu:add_component(ui.path_to_click_btn)

    ui.save_pos_btn = Button:new({
        text = "Save Pos",
        x = p + (nav_btn_w + 6) * 2,
        y = y,
        width = nav_btn_w,
        height = btn_h - 4,
        on_click = function()
            -- Save position with auto-generated name
            local count = 0
            for _ in pairs(saved_positions) do count = count + 1 end
            local name = "Pos_" .. tostring(count + 1)

            if save_current_position(name) then
                core.log("[LX_Mover] Position saved as: " .. name)
                refresh_saved_position_buttons()
            end
        end
    })
    menu:add_component(ui.save_pos_btn)
    y = y + btn_h - 4 + 12

    -- Saved Positions header
    local header_saved = Label:new({
        text = "Saved Positions:",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 16,
        font_size = 10
    })
    menu:add_component(header_saved)
    y = y + 18

    -- Saved positions list (dynamic buttons created by refresh function)
    ui.saved_pos_buttons = {}
    ui.saved_pos_y_start = y
    ui.saved_pos_scroll = 0
    y = y + 105  -- Reserve space for saved position buttons (max 4 buttons at 24px + 4px spacing)

    -- Status label
    ui.status = Label:new({
        text = "Status: Idle",
        x = p,
        y = y,
        width = menu_w - p*2,
        height = 18
    })
    menu:add_component(ui.status)
    y = y + 22

    -- Create saved position buttons
    refresh_saved_position_buttons()
end

-----------------------------------------------------------
-- Update UI
-----------------------------------------------------------

local function update_ui()
    if not ui.progress then return end

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
-- Click Detection for Path-to-Click Mode
-----------------------------------------------------------

local click_state = {
    last_click_time = 0,
    pos_name_input = "",
    save_mode_active = false
}

local function handle_click_to_path()
    if not click_to_path_mode then return end

    -- Check for mouse click (left button)
    local is_mouse_down = core.input.is_key_pressed(0x01)  -- VK_LBUTTON

    -- Detect click edge (mouse was up, now down)
    if is_mouse_down and not prev_mouse_down then
        -- Get world position at cursor (same API as LX_Nav)
        local world_pos = core.graphics.get_cursor_world_position()
        if world_pos then
            core.log(string.format("[LX_Mover] Pathfinding to clicked position (%.1f, %.1f, %.1f)",
                world_pos.x, world_pos.y, world_pos.z))

            -- Request path to clicked position
            if request_path_to_position(world_pos, nil) then
                -- Start moving
                start_path()
            end

            click_to_path_mode = false
        else
            core.log_warning("[LX_Mover] Could not get world position at cursor")
            click_to_path_mode = false
        end
    end

    prev_mouse_down = is_mouse_down
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

    handle_click_to_path()
    update_movement()
    update_tabbed_out()
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

return LX_Mover
