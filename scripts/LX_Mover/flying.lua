-- Flying Module for LX_Mover
-- Handles 3D flying movement, automatic mounting/dismounting, adaptive altitude control
-- Separate from ground movement to prevent breaking existing functionality

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local vec3 = require("common/geometry/vector_3")
local enums = require("common/enums")

local Flying = {}

-- ============================================================================
-- STATE MACHINE
-- ============================================================================

local FlightState = {
    GROUNDED = "grounded",      -- On ground, not mounted
    MOUNTING = "mounting",       -- Waiting for mount cast to complete
    AIRBORNE = "airborne",      -- Flying in the air
    DESCENDING = "descending",  -- Controlled descent to land
    DISMOUNTING = "dismounting" -- Waiting for dismount to complete
}

-- ============================================================================
-- MODULE VARIABLES
-- ============================================================================

-- Current flight state
local flight_state = FlightState.GROUNDED

-- Mount management
local flight_mount_index = nil
local cached_flying_mounts = {}  -- {index1, index2, ...}
local mount_scan_complete = false
local mount_cast_start_time = 0
local current_map_id = nil

-- Landing control
local landing_target_z = 0
local is_descending_to_land = false

-- Vertical movement state
local is_moving_up = false
local is_moving_down = false

-- Path analysis results
local path_analysis = nil  -- {should_fly, first_outdoor_idx, last_outdoor_idx, time_saved}

-- Flight parameters
local MIN_FLIGHT_ALTITUDE = 50   -- Minimum height above ground (yards)
local MAX_FLIGHT_ALTITUDE = 150  -- Maximum cruise altitude (yards)
local OBSTACLE_CLEARANCE = 20    -- Extra clearance above obstacles (yards)
local VERTICAL_THRESHOLD = 8.0   -- Z-distance threshold for vertical movement (yards)
local WAYPOINT_THRESHOLD = 8.0   -- Distance to advance waypoint (larger for flying)
local TIME_SAVE_THRESHOLD = 5.0  -- Minimum time saved to justify flying (seconds)

-- Manual controls
local is_manual_ascending = false
local SPACE_KEY = 0x20  -- VK_SPACE

-- Settings (exposed to main.lua)
Flying.enabled = false
Flying.dismount_on_arrival = false

-- ============================================================================
-- MOUNT MANAGEMENT
-- ============================================================================

--- Scan all mounts and cache flying mount indices
local function scan_flying_mounts()
    if mount_scan_complete then return end

    cached_flying_mounts = {}
    local mount_count = core.spell_book.get_mount_count()

    core.log("[Flying] Scanning " .. mount_count .. " mounts for flying capability...")

    for i = 1, mount_count do
        local mount_info = core.spell_book.get_mount_info(i)

        if mount_info and mount_info.is_usable then
            -- TODO: Need to determine correct mount_type value for flying mounts
            -- Hypothesis: mount_type == 247 or 248 indicates flying
            -- For now, use name-based detection as fallback

            local is_flying = false

            -- Approach 1: Check mount_type (needs testing)
            if mount_info.mount_type == 247 or mount_info.mount_type == 248 then
                is_flying = true
            end

            -- Approach 2: Name-based detection (fallback)
            if not is_flying then
                local name_lower = mount_info.mount_name:lower()
                is_flying = name_lower:find("drake")
                         or name_lower:find("wyrm")
                         or name_lower:find("proto%-drake")
                         or name_lower:find("wind rider")
                         or name_lower:find("gryphon")
                         or name_lower:find("hippogryph")
                         or name_lower:find("netherdrake")
                         or name_lower:find("phoenix")
                         or name_lower:find("rocket")
                         or name_lower:find("flying")
            end

            if is_flying then
                table.insert(cached_flying_mounts, i)
                core.log("[Flying] Found: " .. mount_info.mount_name .. " (type=" .. mount_info.mount_type .. ")")
            end
        end
    end

    mount_scan_complete = true
    core.log("[Flying] Scan complete. Found " .. #cached_flying_mounts .. " flying mounts")
end

--- Select a random flying mount from available pool
--- @return number|nil mount_index
local function select_random_flying_mount()
    if #cached_flying_mounts == 0 then
        core.log_warning("[Flying] No flying mounts available!")
        return nil
    end

    -- Random selection
    math.randomseed(core.time and core.time() or 0)
    local random_idx = math.random(1, #cached_flying_mounts)
    local mount_idx = cached_flying_mounts[random_idx]

    -- Verify still usable
    local mount_info = core.spell_book.get_mount_info(mount_idx)
    if mount_info and mount_info.is_usable then
        return mount_idx
    end

    -- Fallback: try first usable mount
    for _, idx in ipairs(cached_flying_mounts) do
        local info = core.spell_book.get_mount_info(idx)
        if info and info.is_usable then
            return idx
        end
    end

    return nil
end

-- ============================================================================
-- PATH ANALYSIS
-- ============================================================================

--- Calculate total distance along path between waypoints
--- @param start_idx number
--- @param end_idx number
--- @param path table
--- @return number distance
local function calculate_path_distance(start_idx, end_idx, path)
    local total_dist = 0
    for i = start_idx, end_idx - 1 do
        local p1 = path.points[i]
        local p2 = path.points[i + 1]
        local dx = p2.x - p1.x
        local dy = p2.y - p1.y
        local dz = p2.z - p1.z
        total_dist = total_dist + math.sqrt(dx*dx + dy*dy + dz*dz)
    end
    return total_dist
end

--- Analyze path to determine if flying is worthwhile
--- @param path table {points = {{x,y,z}...}}
--- @param player game_object
--- @return table {should_fly, reason, last_outdoor_idx, time_saved}
function Flying.analyze_path(path, player)
    if not path or not path.points or #path.points < 2 then
        return {should_fly = false, reason = "invalid_path"}
    end

    local player_speed = player:get_movement_speed_max() or 7.0
    local flight_speed = player:get_flight_speed_max() or 14.0

    -- Scan backwards from END to find last outdoor waypoint
    local last_outdoor_idx = nil
    local collision_flags = enums.collision_flags.Terrain

    for i = #path.points, 1, -1 do
        local wp = path.points[i]
        local wp_pos = vec3.new(wp.x, wp.y, wp.z)
        local up_pos = vec3.new(wp.x, wp.y, wp.z + 50)

        -- Trace upward - if blocked, it's indoor
        local blocked = core.graphics.trace_line(wp_pos, up_pos, collision_flags)

        if not blocked then
            last_outdoor_idx = i
            break
        end
    end

    if not last_outdoor_idx or last_outdoor_idx < 2 then
        return {should_fly = false, reason = "all_indoor"}
    end

    -- Calculate flight distance (start to last outdoor point)
    local flight_distance = calculate_path_distance(1, last_outdoor_idx, path)

    -- Ground time
    local ground_time = flight_distance / player_speed

    -- Flight time = overhead + travel
    -- Get actual mount cast time if possible
    local cast_time = 1.5  -- Default estimate
    if flight_mount_index then
        local mount_info = core.spell_book.get_mount_info(flight_mount_index)
        if mount_info and mount_info.spell_id then
            local actual_cast = core.spell_book.get_spell_cast_time(mount_info.spell_id)
            if actual_cast and actual_cast > 0 then
                cast_time = actual_cast
            end
        end
    end

    local flight_overhead = cast_time + 2.5  -- cast + accel (1s) + land (1.5s)
    local flight_time = flight_overhead + (flight_distance / flight_speed)

    local time_saved = ground_time - flight_time

    -- Only fly if time saved exceeds threshold
    if time_saved < TIME_SAVE_THRESHOLD then
        return {
            should_fly = false,
            reason = "too_short",
            time_saved = time_saved,
            distance = flight_distance
        }
    end

    return {
        should_fly = true,
        reason = "worthwhile",
        last_outdoor_idx = last_outdoor_idx,
        time_saved = time_saved,
        distance = flight_distance
    }
end

-- ============================================================================
-- HEIGHT & TERRAIN DETECTION
-- ============================================================================

--- Get ground height at position (safe wrapper)
--- @param pos vec3
--- @return number|nil ground_z
local function get_ground_height(pos)
    if not pos then return nil end

    local ground_z = core.get_height_for_position(pos)
    return ground_z
end

--- Calculate adaptive altitude based on terrain ahead
--- @param pos vec3 current position
--- @param next_waypoint vec3 next waypoint
--- @return number target_altitude
local function calculate_adaptive_altitude(pos, next_waypoint)
    local max_ground = -math.huge

    -- Sample ground heights ahead (5 samples)
    for i = 0, 5 do
        local t = i / 5
        local sample_x = pos.x + (next_waypoint.x - pos.x) * t
        local sample_y = pos.y + (next_waypoint.y - pos.y) * t
        local sample_pos = vec3.new(sample_x, sample_y, pos.z)

        local ground_z = get_ground_height(sample_pos)
        if ground_z and ground_z > max_ground then
            max_ground = ground_z
        end
    end

    -- Fallback if no ground detected
    if max_ground == -math.huge then
        max_ground = pos.z - 50  -- Assume 50 yards below current
    end

    -- Base altitude: highest ground + minimum clearance
    local target_alt = max_ground + MIN_FLIGHT_ALTITUDE

    -- TODO: Check for obstacles using trace_line at different heights

    -- Clamp to maximum altitude
    target_alt = math.min(target_alt, max_ground + MAX_FLIGHT_ALTITUDE)

    return target_alt
end

-- ============================================================================
-- 3D MOVEMENT CONTROL
-- ============================================================================

--- Update 3D flying movement toward waypoint
--- @param player game_object
--- @param current_path table
--- @param current_index number
local function update_3d_movement(player, current_path, current_index)
    if not current_path or not current_path.points then return end
    if current_index > #current_path.points then return end

    local pos = player:get_position()
    if not pos then return end

    local waypoint = current_path.points[current_index]
    local target = vec3.new(waypoint.x, waypoint.y, waypoint.z)

    -- Calculate adaptive altitude
    local target_altitude = calculate_adaptive_altitude(pos, target)
    target.z = target_altitude

    -- Calculate 3D distance
    local dx = target.x - pos.x
    local dy = target.y - pos.y
    local dz = target.z - pos.z
    local distance_3d = math.sqrt(dx*dx + dy*dy + dz*dz)

    -- Check if close enough to advance waypoint
    if distance_3d < WAYPOINT_THRESHOLD then
        -- Advance handled by main.lua
        return
    end

    -- Forward movement (handled by main.lua's start_forward)
    -- Here we only control look direction and vertical

    -- 3D look_at for smooth turning
    core.input.look_at(target)

    -- Vertical movement control
    local z_diff = target.z - pos.z

    if z_diff > VERTICAL_THRESHOLD then
        -- Need to climb
        if not is_moving_up then
            core.input.move_up_start()
            is_moving_up = true
        end
        if is_moving_down then
            core.input.move_down_stop()
            is_moving_down = false
        end
    elseif z_diff < -VERTICAL_THRESHOLD then
        -- Need to descend
        if not is_moving_down then
            core.input.move_down_start()
            is_moving_down = true
        end
        if is_moving_up then
            core.input.move_up_stop()
            is_moving_up = false
        end
    else
        -- Level flight
        if is_moving_up then
            core.input.move_up_stop()
            is_moving_up = false
        end
        if is_moving_down then
            core.input.move_down_stop()
            is_moving_down = false
        end
    end
end

-- ============================================================================
-- LANDING CONTROL
-- ============================================================================

--- Check if player should dismount
--- @param player game_object
--- @param current_index number
--- @param path_points table
--- @return boolean should_land
--- @return string|nil reason
local function should_dismount(player, current_index, path_points)
    -- 1. Reached end of path
    if current_index >= #path_points then
        return true, "destination_reached"
    end

    -- 2. Entered indoor area during flight
    if player:is_indoors() and player:is_flying() then
        return true, "entered_indoors"
    end

    -- 3. Approaching last outdoor waypoint
    if path_analysis and path_analysis.last_outdoor_idx then
        if current_index >= path_analysis.last_outdoor_idx then
            return true, "approaching_indoor_zone"
        end
    end

    -- 4. User preference: dismount on arrival
    if Flying.dismount_on_arrival and current_index >= #path_points - 2 then
        return true, "user_preference_arrival"
    end

    return false, nil
end

--- Initiate landing sequence
--- @param player game_object
local function initiate_landing(player)
    local pos = player:get_position()
    if not pos then return end

    -- Get ground height at current position
    local ground_z = get_ground_height(pos)

    if ground_z then
        landing_target_z = ground_z + 5  -- Land 5 yards above ground
    else
        -- Fallback if height detection fails
        landing_target_z = pos.z - 50
        core.log_warning("[Flying] Height detection failed, using fallback landing")
    end

    flight_state = FlightState.DESCENDING
    is_descending_to_land = true

    core.log("[Flying] Initiating landing to altitude " .. string.format("%.1f", landing_target_z))
end

--- Update landing sequence
--- @param player game_object
local function update_landing_sequence(player)
    local pos = player:get_position()
    if not pos then return end

    -- Descend toward target altitude
    if pos.z > landing_target_z + 2 then
        if not is_moving_down then
            core.input.move_down_start()
            is_moving_down = true
        end
    else
        -- Close to landing altitude
        if is_moving_down then
            core.input.move_down_stop()
            is_moving_down = false
        end

        -- Double-check we're close to ground before dismounting
        local current_ground = get_ground_height(pos)
        if current_ground and (pos.z - current_ground) < 10 then
            -- Safe to dismount
            core.input.dismount()
            flight_state = FlightState.DISMOUNTING
            is_descending_to_land = false
            core.log("[Flying] Dismounting at altitude " .. string.format("%.1f", pos.z))
        else
            -- Still too high, continue descending
            core.log_warning("[Flying] Still too high (Z=" .. string.format("%.1f", pos.z) .. "), continuing descent")
        end
    end
end

-- ============================================================================
-- MANUAL CONTROLS
-- ============================================================================

--- Handle manual flight controls (space bar for ascend)
--- @param player game_object
local function handle_manual_flight_controls(player)
    if not player:is_flying() then return end

    -- Space bar = ascend
    if core.input.is_key_pressed(SPACE_KEY) then
        if not is_manual_ascending then
            core.input.move_up_start()
            is_manual_ascending = true
        end
    else
        if is_manual_ascending then
            core.input.move_up_stop()
            is_manual_ascending = false
        end
    end
end

-- ============================================================================
-- MAIN UPDATE LOOP
-- ============================================================================

--- Main flying module update function
--- @param player game_object
--- @param current_path table|nil
--- @param current_index number
--- @return boolean true if flying is handling movement, false otherwise
function Flying.update(player, current_path, current_index)
    if not Flying.enabled then
        return false  -- Ground movement should handle
    end

    if not player then return false end

    -- Ensure mounts are scanned
    if not mount_scan_complete then
        scan_flying_mounts()
    end

    -- Check for map change (re-scan mounts if zone changed)
    local map_id = core.get_map_id and core.get_map_id() or 0
    if map_id ~= current_map_id and current_map_id ~= nil then
        core.log("[Flying] Map changed, re-scanning mounts...")
        mount_scan_complete = false
        cached_flying_mounts = {}
        current_map_id = map_id
        scan_flying_mounts()
    end
    current_map_id = map_id

    -- Handle manual controls
    handle_manual_flight_controls(player)

    -- STATE MACHINE
    if flight_state == FlightState.GROUNDED then
        -- Check if we should mount
        if player:is_outdoors() and path_analysis and path_analysis.should_fly then
            local mount_idx = select_random_flying_mount()
            if mount_idx then
                flight_mount_index = mount_idx
                core.input.mount(mount_idx)
                mount_cast_start_time = core.time and core.time() or 0

                local mount_info = core.spell_book.get_mount_info(mount_idx)
                if mount_info then
                    core.log("[Flying] Mounting " .. mount_info.mount_name .. "...")
                end

                flight_state = FlightState.MOUNTING
            else
                core.log_warning("[Flying] No usable flying mount, falling back to ground movement")
                path_analysis = {should_fly = false}  -- Disable for this path
            end
        end
        return false  -- Let ground movement continue

    elseif flight_state == FlightState.MOUNTING then
        -- Wait for mount cast to complete
        if player:is_flying() then
            flight_state = FlightState.AIRBORNE
            core.log("[Flying] Airborne!")
            return true
        elseif not player:is_casting_spell() and ((core.time and core.time() or 0) - mount_cast_start_time > 0.5) then
            -- Cast finished but not flying = failed/interrupted
            core.log_warning("[Flying] Mount cast failed or interrupted, retrying...")
            flight_state = FlightState.GROUNDED
            return false
        end
        return true  -- Block ground movement while mounting

    elseif flight_state == FlightState.AIRBORNE then
        -- Main flying logic
        if not current_path then
            -- No path, stay airborne but don't move
            return true
        end

        -- Check if should land
        local should_land, reason = should_dismount(player, current_index, current_path.points)
        if should_land then
            initiate_landing(player)
            return true
        end

        -- Continue flying
        update_3d_movement(player, current_path, current_index)
        return true

    elseif flight_state == FlightState.DESCENDING then
        -- Landing sequence
        update_landing_sequence(player)
        return true

    elseif flight_state == FlightState.DISMOUNTING then
        -- Wait for dismount to complete
        if not player:is_mounted() then
            flight_state = FlightState.GROUNDED
            core.log("[Flying] Landed and dismounted")
            path_analysis = nil  -- Clear analysis for next path
            return false  -- Resume ground movement
        end
        return true
    end

    return false
end

--- Analyze and prepare flight for a new path
--- @param path table
--- @param player game_object
function Flying.analyze_and_prepare_flight(path, player)
    if not Flying.enabled then return end
    if not player then return end

    path_analysis = Flying.analyze_path(path, player)

    if path_analysis.should_fly then
        core.log(string.format("[Flying] Path analysis: Will fly! Distance=%.1f yards, Time saved=%.1f seconds",
            path_analysis.distance or 0, path_analysis.time_saved or 0))
    else
        core.log("[Flying] Path analysis: Using ground movement (" .. (path_analysis.reason or "unknown") .. ")")
    end
end

--- Force dismount (emergency or user-requested)
function Flying.force_dismount()
    if flight_state == FlightState.AIRBORNE or flight_state == FlightState.MOUNTING then
        local player = core.object_manager.get_local_player()
        if player then
            initiate_landing(player)
        end
    end
end

--- Get current flight state (for UI display)
--- @return string
function Flying.get_state()
    return flight_state
end

-- ============================================================================
-- RENDERING
-- ============================================================================

--- Render flight-specific visualizations
--- @param current_path table|nil
--- @param current_index number
function Flying.render(current_path, current_index)
    if flight_state == FlightState.GROUNDED then return end

    local player = core.object_manager.get_local_player()
    if not player then return end

    local pos = player:get_position()
    if not pos then return end

    local screen_size = core.graphics.get_screen_size()
    if not screen_size then return end

    -- Altitude display
    local ground_z = get_ground_height(pos)
    if ground_z then
        local altitude = pos.z - ground_z
        local alt_text = string.format("Altitude: %.1f yards", altitude)
        core.graphics.text_2d(
            alt_text,
            vec2.new(screen_size.x / 2, 50),
            14,
            color.new(100, 200, 255, 255),
            true
        )
    end

    -- Flight state
    local state_text = "Flight: " .. flight_state:upper()
    core.graphics.text_2d(
        state_text,
        vec2.new(screen_size.x / 2, 70),
        12,
        color.new(255, 255, 255, 200),
        true
    )

    -- TODO: 3D path visualization, target altitude circle, etc.
end

-- Export module
return Flying
