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
    GROUNDED = "grounded",          -- On ground, not mounted
    MOUNTING = "mounting",          -- Casting mount spell
    TAKING_OFF = "taking_off",      -- Mounted, jumping to start flying
    AIRBORNE = "airborne",          -- Actually flying in the air
    DESCENDING = "descending",      -- Controlled descent to land
    DISMOUNTING = "dismounting"     -- Waiting for dismount to complete
}

-- ============================================================================
-- MODULE VARIABLES
-- ============================================================================

-- Debug logging
local debug_log_file = "flying_debug.txt"
local debug_log_initialized = false

local function init_debug_log()
    if not debug_log_initialized then
        core.create_log_file(debug_log_file)
        core.write_log_file(debug_log_file, "=== Flying Debug Log Started ===\n")
        debug_log_initialized = true
    end
end

local function log_debug(message)
    init_debug_log()
    local timestamp = string.format("[%.2f] ", core.time and core.time() or 0)
    core.write_log_file(debug_log_file, timestamp .. message .. "\n")
end

-- Flight control testing
local flight_test_active = false
local flight_test_stage = 0
local flight_test_start_time = 0

-- Obstacle detection visualization
local obstacle_scan_results = {}  -- Stores last scan results for rendering
local last_obstacle_scan_time = 0
local show_obstacle_visualization = true  -- Show obstacle rays by default
local flight_test_start_pos = nil
local flight_test_log_file = "flight_control_test.txt"

local function init_flight_test_log()
    core.create_log_file(flight_test_log_file)
    core.write_log_file(flight_test_log_file, "=== FLIGHT CONTROL TEST ===\n")
    core.write_log_file(flight_test_log_file, "Testing different methods to control flight direction and altitude\n\n")
end

local function log_flight_test(message)
    local timestamp = string.format("[%.2f] ", core.time and core.time() or 0)
    core.write_log_file(flight_test_log_file, timestamp .. message .. "\n")
    core.log("[Flight Test] " .. message)
end

-- Current flight state
local flight_state = FlightState.GROUNDED

-- Mount management
local flight_mount_index = nil
local cached_flying_mounts = {}  -- {index1, index2, ...}
local mount_scan_complete = false
local mount_cast_start_time = 0
local takeoff_start_time = 0
local takeoff_start_z = 0
local has_jumped_for_takeoff = false
local current_map_id = nil

-- Landing control
local landing_target_z = 0
local is_descending_to_land = false

-- Vertical movement state
local is_moving_up = false
local is_moving_down = false
local is_moving_forward = false

-- Stabilized cruise altitude (prevents constant up/down adjustments)
local locked_cruise_altitude = nil
local last_terrain_check_time = 0
local last_obstacle_boost_target = nil  -- Track last boosted target to prevent spam

-- Path analysis results
local path_analysis = nil  -- {should_fly, first_outdoor_idx, last_outdoor_idx, time_saved}

-- Callback for when flying completes (set by main.lua)
local on_flight_complete_callback = nil

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
Flying.debug_mode = false  -- Debug mode: always fly (ignores time threshold)

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
            -- Type 424 = Flying mounts (confirmed from testing)
            -- Type 230 = Ground mounts
            -- Type 231 = Aquatic mounts
            local is_flying = (mount_info.mount_type == 424)

            if is_flying then
                table.insert(cached_flying_mounts, i)
                core.log("[Flying] Found: " .. mount_info.mount_name .. " (type=" .. mount_info.mount_type .. ")")
            end
        end
    end

    mount_scan_complete = true
    core.log("[Flying] Scan complete. Found " .. #cached_flying_mounts .. " flying mounts")
end

--- Test API values during mounting/flying - logs continuous status
local api_test_active = false
local api_test_start_time = 0

function Flying.test_api_values()
    if api_test_active then
        api_test_active = false
        core.log("[Flying API Test] STOPPED - check logs above")
        return
    end

    api_test_active = true
    api_test_start_time = core.time and core.time() or 0
    core.log("========== FLYING API TEST START ==========")
    core.log("[Flying API Test] Mount your flying mount manually!")
    core.log("[Flying API Test] Then jump to start flying.")
    core.log("[Flying API Test] Logging API values every 0.2s for 15 seconds...")
    core.log("[Flying API Test] Click 'Test API Values' again to stop early")
end

--- Update API test (called from Flying.update)
local function update_api_test(player)
    if not api_test_active then return end

    local elapsed = (core.time and core.time() or 0) - api_test_start_time

    if elapsed > 15.0 then
        api_test_active = false
        core.log("========== FLYING API TEST COMPLETE ==========")
        return
    end

    -- Log every 0.2s
    if math.floor(elapsed * 5) ~= math.floor((elapsed - 0.016) * 5) then
        local pos = player:get_position()
        local is_casting = player:is_casting_spell()
        local is_mounted = player:is_mounted()
        local is_flying = player:is_flying()
        local is_indoors = player:is_indoors()
        local is_outdoors = player:is_outdoors()

        core.log(string.format("[%.1fs] casting=%s mounted=%s flying=%s indoor=%s outdoor=%s z=%.1f",
            elapsed,
            tostring(is_casting),
            tostring(is_mounted),
            tostring(is_flying),
            tostring(is_indoors),
            tostring(is_outdoors),
            pos and pos.z or 0
        ))
    end
end

--- Test mount scanning - writes ALL mounts to log file for analysis
function Flying.test_mount_scan()
    local filename = "mount_scan.txt"

    core.log("[Flying Test] Starting mount scan - writing to " .. filename)

    -- Create log file
    core.create_log_file(filename)

    local mount_count = core.spell_book.get_mount_count()
    local log_lines = {}

    table.insert(log_lines, "========== MOUNT SCAN TEST ==========")
    table.insert(log_lines, "[Flying Test] Total mounts: " .. mount_count)
    table.insert(log_lines, "")

    local usable_count = 0
    local flying_count = 0
    local type_stats = {}  -- Track mount_type distribution

    for i = 1, mount_count do
        local mount_info = core.spell_book.get_mount_info(i)

        if mount_info then
            local status = ""
            if mount_info.is_usable then
                usable_count = usable_count + 1
                status = "[USABLE]"
            else
                status = "[LOCKED]"
            end

            -- Check if type 424 (flying)
            local is_flying = (mount_info.mount_type == 424)

            if is_flying and mount_info.is_usable then
                flying_count = flying_count + 1
                status = status .. " [FLYING]"
            end

            -- Track type statistics
            type_stats[mount_info.mount_type] = (type_stats[mount_info.mount_type] or 0) + 1

            local line = string.format("[Mount %d] %s type=%d spell_id=%d %s",
                i, mount_info.mount_name, mount_info.mount_type,
                mount_info.spell_id or 0, status)
            table.insert(log_lines, line)
        end
    end

    table.insert(log_lines, "")
    table.insert(log_lines, "========================================")
    table.insert(log_lines, string.format("[Flying Test] Summary: %d total, %d usable, %d flying (type 424)",
        mount_count, usable_count, flying_count))
    table.insert(log_lines, "")
    table.insert(log_lines, "Mount Type Distribution:")
    for mount_type, count in pairs(type_stats) do
        table.insert(log_lines, string.format("  Type %d: %d mounts", mount_type, count))
    end
    table.insert(log_lines, "========================================")

    -- Write all lines to log file
    local full_log = table.concat(log_lines, "\n")
    core.write_log_file(filename, full_log)

    core.log("[Flying Test] Mount scan complete!")
    core.log("[Flying Test] Log written to: scripts_log/" .. filename)
    core.log(string.format("[Flying Test] Summary: %d total, %d usable, %d flying (type 424)",
        mount_count, usable_count, flying_count))

    return flying_count
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
    -- Check for ALL collidable objects: Terrain + Buildings (WMO) + Objects (Doodads)
    local collision_flags = enums.collision_flags.Terrain +
                           enums.collision_flags.WmoCollision +
                           enums.collision_flags.DoodadCollision

    for i = #path.points, 1, -1 do
        local wp = path.points[i]
        local wp_pos = vec3.new(wp.x, wp.y, wp.z)
        local up_pos = vec3.new(wp.x, wp.y, wp.z + 50)

        -- Trace upward - if blocked, it's indoor
        -- NOTE: trace_line returns FALSE when blocked, TRUE when clear
        local trace_result = core.graphics.trace_line(wp_pos, up_pos, collision_flags)
        local blocked = not trace_result  -- Invert

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

    -- Debug logging
    core.log(string.format("[Flying] Path analysis details: distance=%.1fy, ground_time=%.1fs, flight_time=%.1fs (overhead=%.1fs), time_saved=%.1fs",
        flight_distance, ground_time, flight_time, flight_overhead, time_saved))

    -- Only fly if time saved exceeds threshold (unless debug mode)
    if not Flying.debug_mode and time_saved < TIME_SAVE_THRESHOLD then
        core.log(string.format("[Flying] Path too short: time_saved=%.1fs < threshold=%.1fs", time_saved, TIME_SAVE_THRESHOLD))
        return {
            should_fly = false,
            reason = "too_short",
            time_saved = time_saved,
            distance = flight_distance
        }
    end

    if Flying.debug_mode and time_saved < TIME_SAVE_THRESHOLD then
        core.log("[Flying] DEBUG MODE: Flying anyway despite time_saved < threshold")
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

--- REAL-TIME obstacle scan EVERY FRAME from current position
--- Returns obstacle detection info and stores visualization data
--- @param pos vec3 current position
--- @param flight_dir_x number normalized flight direction X
--- @param flight_dir_y number normalized flight direction Y
--- @param current_altitude number current Z position
--- @return table {max_height, obstacle_very_close, obstacle_close, obstacle_ahead, obstacle_far, blocked_count, closest_distance}
local function realtime_obstacle_scan(pos, flight_dir_x, flight_dir_y, current_altitude)
    -- Check for ALL collidable objects: Terrain + Buildings (WMO) + Objects (Doodads)
    local collision_flags = enums.collision_flags.Terrain +
                           enums.collision_flags.WmoCollision +
                           enums.collision_flags.DoodadCollision
    local scan_results = {}

    -- Real-time scan configuration (every frame!)
    -- FOCUSED narrow corridor ahead (5x5 yard corridor) for faster reaction

    -- Horizontal angles: narrow forward corridor only (±20° = ~7 yard width at 20y distance)
    local horizontal_angles = {-20, -10, 0, 10, 20}  -- 5 angles

    -- Vertical offsets: check ahead and down for landing/terrain
    local vertical_offsets = {-15, -5, 0, 5, 10, 20}  -- 6 heights, including downward

    -- Distance steps: CLOSER focus for faster reaction
    local distance_steps = {5, 10, 20, 40}  -- 4 distances (was 15, 30, 50, 80)

    -- Total rays: 5 × 6 × 4 = 120 rays (was 312 - much faster!)

    -- Detection results (adjusted for narrow corridor)
    local max_obstacle_height = 0
    local obstacle_very_close = false  -- Within 5 yards - EMERGENCY!
    local obstacle_close = false       -- Within 10 yards - stop forward movement
    local obstacle_ahead = false       -- Within 20 yards - start climbing
    local obstacle_far = false         -- Within 40 yards - prepare
    local blocked_count = 0
    local closest_obstacle_distance = 999

    for _, h_angle in ipairs(horizontal_angles) do
        for _, v_offset in ipairs(vertical_offsets) do
            for _, dist in ipairs(distance_steps) do
                -- Calculate rotated direction (2D rotation)
                local angle_rad = math.rad(h_angle)
                local cos_a = math.cos(angle_rad)
                local sin_a = math.sin(angle_rad)

                local dir_x = flight_dir_x * cos_a - flight_dir_y * sin_a
                local dir_y = flight_dir_x * sin_a + flight_dir_y * cos_a

                -- Sample point
                local sample_x = pos.x + dir_x * dist
                local sample_y = pos.y + dir_y * dist
                local sample_z = current_altitude + v_offset

                local sample_point = vec3.new(sample_x, sample_y, sample_z)
                local ray_start = vec3.new(pos.x, pos.y, current_altitude)

                -- Raycast
                -- NOTE: trace_line returns FALSE when blocked, TRUE when clear (inverted logic!)
                local trace_result = core.graphics.trace_line(ray_start, sample_point, collision_flags)
                local blocked = not trace_result  -- Invert: blocked = NOT clear

                -- Store for visualization
                table.insert(scan_results, {
                    start_pos = ray_start,
                    end_pos = sample_point,
                    blocked = blocked,
                    distance = dist,
                    angle = h_angle,
                    height_offset = v_offset
                })

                -- Analyze results for flight control (narrow corridor - all rays are "forward")
                if blocked then
                    blocked_count = blocked_count + 1

                    -- Track closest obstacle
                    if dist < closest_obstacle_distance then
                        closest_obstacle_distance = dist
                    end

                    -- Categorize by distance for tiered reaction
                    if dist <= 5 then
                        obstacle_very_close = true  -- EMERGENCY - within 5 yards
                    end
                    if dist <= 10 then
                        obstacle_close = true  -- Stop forward movement
                    end
                    if dist <= 20 then
                        obstacle_ahead = true  -- Start climbing
                    end
                    if dist <= 40 then
                        obstacle_far = true  -- Prepare to react
                    end

                    -- Estimate obstacle height
                    local ground_h = get_ground_height(vec3.new(sample_x, sample_y, 0))
                    if ground_h then
                        for test_h = ground_h, ground_h + 100, 10 do
                            local test_from = vec3.new(sample_x, sample_y, test_h)
                            local test_to = vec3.new(sample_x, sample_y, test_h + 5)
                            -- NOTE: trace_line returns FALSE when blocked, TRUE when clear
                            local trace_clear = core.graphics.trace_line(test_from, test_to, collision_flags)
                            if trace_clear then  -- If clear, we're above the obstacle
                                if test_h > max_obstacle_height then
                                    max_obstacle_height = test_h
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Store results for rendering
    obstacle_scan_results = scan_results
    last_obstacle_scan_time = core.time and core.time() or 0

    return {
        max_height = max_obstacle_height,
        obstacle_very_close = obstacle_very_close,  -- <5y - EMERGENCY
        obstacle_close = obstacle_close,             -- <10y - stop forward
        obstacle_ahead = obstacle_ahead,             -- <20y - climb
        obstacle_far = obstacle_far,                 -- <40y - prepare
        blocked_count = blocked_count,
        closest_distance = closest_obstacle_distance
    }
end

--- Calculate adaptive altitude based on terrain ahead
--- @param pos vec3 current position
--- @param next_waypoint vec3 next waypoint
--- @return number target_altitude
local function calculate_adaptive_altitude(pos, destination)
    -- Get ground height at destination
    local dest_ground = get_ground_height(destination)
    if not dest_ground then
        dest_ground = destination.z  -- Fallback to destination Z if can't get ground height
    end

    -- Start at safe cruise altitude above destination ground
    local cruise_altitude = dest_ground + 100  -- 100 yards above destination ground

    -- DEBUG: Log what we calculated
    if not last_calc_log_time then last_calc_log_time = 0 end
    local now = core.time and core.time() or 0
    if now - last_calc_log_time > 2.0 then
        log_debug(string.format("Altitude calc: dest_ground=%.1f, base_cruise=%.1f", dest_ground, cruise_altitude))
        last_calc_log_time = now
    end

    -- Check if path is clear using trace_line
    -- Check for ALL collidable objects: Terrain + Buildings (WMO) + Objects (Doodads)
    local collision_flags = enums.collision_flags.Terrain +
                           enums.collision_flags.WmoCollision +
                           enums.collision_flags.DoodadCollision

    -- Test flight path at cruise altitude
    local test_start = vec3.new(pos.x, pos.y, cruise_altitude)
    local test_end = vec3.new(destination.x, destination.y, cruise_altitude)

    -- Check for obstacles along the path
    -- NOTE: trace_line returns FALSE when blocked, TRUE when clear
    local trace_clear = core.graphics.trace_line(test_start, test_end, collision_flags)

    if not trace_clear then
        -- Path blocked at cruise altitude, go higher
        cruise_altitude = cruise_altitude + 50
    end

    -- Sample ground heights to ensure we're high enough
    local max_ground = -math.huge
    for i = 0, 3 do
        local t = i / 3
        local sample_x = pos.x + (destination.x - pos.x) * t
        local sample_y = pos.y + (destination.y - pos.y) * t
        local sample_pos = vec3.new(sample_x, sample_y, pos.z)

        local ground_z = get_ground_height(sample_pos)
        if ground_z and ground_z > max_ground then
            max_ground = ground_z
        end
    end

    -- Ensure we're at least MIN_FLIGHT_ALTITUDE above highest ground
    if max_ground ~= -math.huge then
        local min_safe = max_ground + MIN_FLIGHT_ALTITUDE
        if cruise_altitude < min_safe then
            cruise_altitude = min_safe
        end
    end

    return cruise_altitude
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

    -- Forward movement is started in AIRBORNE state
    -- Here we control look direction and vertical movement

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
-- MOVEMENT CONTROL HELPERS
-- ============================================================================

--- Stop all movement commands
local function stop_all_movement()
    core.input.move_forward_stop()
    core.input.move_backward_stop()
    core.input.turn_left_stop()
    core.input.turn_right_stop()
    core.input.move_up_stop()
    core.input.move_down_stop()
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

    -- STOP FORWARD MOVEMENT - we're landing!
    core.input.move_forward_stop()

    -- Stop any upward movement
    if is_moving_up then
        core.input.move_up_stop()
        is_moving_up = false
    end

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
            -- Safe to dismount - STOP ALL MOVEMENT
            stop_all_movement()
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
        -- Still run API test even when flying disabled
        if player and api_test_active then
            update_api_test(player)
        end
        return false  -- Ground movement should handle
    end

    if not player then return false end

    -- Run API test if active
    if api_test_active then
        update_api_test(player)
    end

    -- Block normal flying while flight control test is running
    if flight_test_active then
        return true
    end

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
            -- CRITICAL: Check if already mounted! Don't call mount() if already on a mount!
            if player:is_mounted() then
                -- Already mounted, skip directly to takeoff
                local pos = player:get_position()
                takeoff_start_time = core.time and core.time() or 0
                takeoff_start_z = pos and pos.z or 0
                flight_state = FlightState.TAKING_OFF
                core.log("[Flying] Already mounted! Starting takeoff sequence...")
                return true
            end

            -- Not mounted, need to mount first
            local mount_idx = select_random_flying_mount()
            if mount_idx then
                flight_mount_index = mount_idx

                -- Reset all flight state variables for new flight
                locked_cruise_altitude = nil
                last_obstacle_boost_target = nil
                is_moving_up = false
                is_moving_down = false
                is_moving_forward = false
                last_terrain_check_time = 0

                core.input.mount(mount_idx)
                mount_cast_start_time = core.time and core.time() or 0

                local mount_info = core.spell_book.get_mount_info(mount_idx)
                if mount_info then
                    core.log("[Flying] Mounting " .. mount_info.mount_name .. "...")
                end

                flight_state = FlightState.MOUNTING
            else
                core.log_warning("[Flying] No usable flying mount, falling back to ground movement")
                path_analysis = {should_fly = false}
                return false  -- No mount available, let ground movement handle it
            end
            return true  -- Block ground movement - we're mounting!
        end
        return false  -- Let ground movement continue

    elseif flight_state == FlightState.MOUNTING then
        -- Wait for mount cast to complete - check ONLY is_mounted
        local is_mounted = player:is_mounted()
        local time_elapsed = (core.time and core.time() or 0) - mount_cast_start_time

        if is_mounted then
            -- Successfully mounted! Transition to takeoff
            local pos = player:get_position()
            takeoff_start_time = core.time and core.time() or 0
            takeoff_start_z = pos and pos.z or 0
            flight_state = FlightState.TAKING_OFF
            core.log("[Flying] Mounted! Starting takeoff sequence...")
            return true
        elseif time_elapsed > 3.0 then
            -- Timeout - mount cast failed
            core.log_warning("[Flying] Mount timeout after 3s - falling back to ground")
            flight_state = FlightState.GROUNDED
            return false
        end
        return true  -- Block ground movement while mounting

    elseif flight_state == FlightState.TAKING_OFF then
        -- Mounted on ground, need to jump ONCE and wait for actual liftoff
        local pos = player:get_position()
        if not pos then
            flight_state = FlightState.GROUNDED
            has_jumped_for_takeoff = false
            return false
        end

        local time_elapsed = (core.time and core.time() or 0) - takeoff_start_time
        local altitude_gained = pos.z - takeoff_start_z

        -- Jump ONCE after 0.3s using a flag to prevent spam
        if not has_jumped_for_takeoff and time_elapsed > 0.3 then
            core.input.jump()
            has_jumped_for_takeoff = true
            core.log("[Flying] Jumped to takeoff!")
        end

        -- If we gained ANY altitude (even 1 yard), we're flying!
        -- Now we need to look up and move forward to gain more altitude
        if altitude_gained > 1.0 then
            -- Transition to airborne - looking controls climb/descent automatically
            flight_state = FlightState.AIRBORNE
            has_jumped_for_takeoff = false  -- Reset for next time
            core.log("[Flying] Airborne! Climbing to cruise altitude... (gained " .. string.format("%.1f", altitude_gained) .. " yards)")
            return true
        elseif time_elapsed > 3.0 then
            -- Failed to takeoff after 3s - altitude stuck
            core.log_warning(string.format("[Flying] Failed to takeoff - altitude stuck at %.1f yards", altitude_gained))
            flight_state = FlightState.GROUNDED
            has_jumped_for_takeoff = false
            return false
        end

        -- Log altitude every 0.5s for debugging
        if math.floor(time_elapsed * 2) ~= math.floor((time_elapsed - 0.016) * 2) then
            core.log(string.format("[Flying] Taking off... altitude gained: %.1f", altitude_gained))
        end

        return true  -- Block ground movement while taking off

    elseif flight_state == FlightState.AIRBORNE then
        -- Main flying logic
        if not current_path or not current_path.points then
            -- No path, stay airborne but don't move
            return true
        end

        local pos = player:get_position()
        if not pos then
            flight_state = FlightState.GROUNDED
            return false
        end

        -- Get FINAL destination (ignore all intermediate waypoints - those are for ground!)
        local final_destination = current_path.points[#current_path.points]

        -- Calculate 2D distance to destination
        local dx = final_destination.x - pos.x
        local dy = final_destination.y - pos.y
        local distance_2d = math.sqrt(dx*dx + dy*dy)

        -- Check if reached destination (land when very close - within 10 yards)
        if distance_2d < 10.0 then
            core.log(string.format("[Flying] Reached destination (dist=%.1f), initiating landing...", distance_2d))
            log_debug(string.format("LANDING INITIATED: Distance=%.1f yards", distance_2d))
            initiate_landing(player)
            return true
        end

        -- Current altitude above ground
        local ground_height = get_ground_height(pos)
        if not ground_height then ground_height = pos.z end

        -- Minimum safe altitude: 5 yards above current ground
        local minimum_altitude = ground_height + 5

        -- Descent logic: start descending when close to destination
        local descent_start_distance = 50  -- Start descent 50 yards before destination

        -- Calculate normalized flight direction
        local dir_2d = math.sqrt(dx*dx + dy*dy)
        local flight_dir_x = dx / dir_2d
        local flight_dir_y = dy / dir_2d

        -- REAL-TIME OBSTACLE SCAN (EVERY FRAME FOR ALL PHASES!)
        local obstacle_data = realtime_obstacle_scan(pos, flight_dir_x, flight_dir_y, pos.z)

        -- Determine target altitude
        local flight_phase = "CRUISE"
        local target_altitude

        if distance_2d < descent_start_distance then
            -- DESCENDING - calculate smooth glide path
            flight_phase = "DESCEND"
            local dest_ground = get_ground_height(final_destination)
            if not dest_ground then dest_ground = final_destination.z end
            local landing_altitude = dest_ground + 5

            -- Calculate smooth glide path: linearly interpolate altitude based on distance
            -- At descent_start_distance: current altitude
            -- At destination: landing_altitude
            local descent_progress = 1.0 - (distance_2d / descent_start_distance)  -- 0.0 at start, 1.0 at end

            -- Use locked cruise altitude as starting point if we have it
            local start_altitude = locked_cruise_altitude or pos.z
            target_altitude = start_altitude - (start_altitude - landing_altitude) * descent_progress

        else
            -- CRUISING or CLIMBING
            -- Update cruise altitude based on detected obstacles
            local now = core.time and core.time() or 0
            if obstacle_data.max_height > 0 then
                local needed_altitude = obstacle_data.max_height + 40  -- 40 yards clearance over obstacles

                if not locked_cruise_altitude then
                    locked_cruise_altitude = needed_altitude
                    last_terrain_check_time = now
                    log_debug(string.format("═══ GLIDE ALTITUDE SET (obstacles: %.1f) ═══", obstacle_data.max_height))
                elseif needed_altitude > locked_cruise_altitude then
                    local old_cruise = locked_cruise_altitude
                    locked_cruise_altitude = needed_altitude
                    last_terrain_check_time = now
                    log_debug(string.format("═══ GLIDE ALTITUDE RAISED: %.1f → %.1f (obstacle: %.1f) ═══",
                        old_cruise, locked_cruise_altitude, obstacle_data.max_height))
                end
            end

            -- Sample terrain heights ahead to find the HIGHEST point on entire path
            if not locked_cruise_altitude or (now - last_terrain_check_time > 5.0) then
                local max_terrain_ahead = ground_height
                -- Sample the ENTIRE remaining path to find highest point
                for i = 1, 10 do
                    local t = i / 10
                    local sample_x = pos.x + (final_destination.x - pos.x) * t
                    local sample_y = pos.y + (final_destination.y - pos.y) * t
                    local sample_pos = vec3.new(sample_x, sample_y, pos.z)
                    local ground_h = get_ground_height(sample_pos)
                    if ground_h and ground_h > max_terrain_ahead then
                        max_terrain_ahead = ground_h
                    end
                end

                -- GLIDE STRATEGY: Climb to highest terrain + 50 yards ONCE
                -- Then naturally glide down, only climbing when too low or obstacle
                local initial_cruise_altitude = max_terrain_ahead + 50  -- 50 yard buffer above highest point
                if not locked_cruise_altitude then
                    locked_cruise_altitude = initial_cruise_altitude
                    last_terrain_check_time = now
                    log_debug(string.format("═══ GLIDE ALTITUDE INITIALIZED: %.1f (max terrain: %.1f + 50y buffer) ═══",
                        locked_cruise_altitude, max_terrain_ahead))
                elseif initial_cruise_altitude > (locked_cruise_altitude + 30) then
                    -- Only raise if significantly higher terrain ahead
                    locked_cruise_altitude = initial_cruise_altitude
                    last_terrain_check_time = now
                    log_debug(string.format("═══ GLIDE ALTITUDE RAISED: %.1f (new max terrain: %.1f) ═══",
                        locked_cruise_altitude, max_terrain_ahead))
                else
                    last_terrain_check_time = now
                end
            end

            -- If no cruise altitude set, use minimum safe altitude
            if not locked_cruise_altitude then
                locked_cruise_altitude = ground_height + 50
                log_debug(string.format("No cruise altitude - using minimum: %.1f", locked_cruise_altitude))
            end

            -- Determine flight phase based on distance to destination
            local descent_start_distance = 100  -- Start natural descent 100 yards from destination

            if distance_2d < descent_start_distance then
                -- DESCEND PHASE: Natural glide down to landing height
                flight_phase = "DESCEND"
                local dest_ground = get_ground_height(final_destination)
                target_altitude = (dest_ground or ground_height) + 10  -- Land at 10 yards above destination
            elseif pos.z >= locked_cruise_altitude - 5 then
                -- GLIDE PHASE: At or above cruise altitude - let gravity pull us down naturally
                flight_phase = "GLIDE"
                target_altitude = ground_height + 30  -- Minimum safe altitude during glide
            else
                -- CLIMB PHASE: Below cruise altitude - climb to it
                flight_phase = "CLIMB"
                target_altitude = locked_cruise_altitude
            end
        end

        -- Ensure we never go below minimum safe altitude
        target_altitude = math.max(target_altitude, minimum_altitude)

        local altitude_diff = target_altitude - pos.z

        -- DETAILED flight logging with real-time obstacle status
        if not last_altitude_log_frame then last_altitude_log_frame = 0 end
        local current_frame = (core.time and core.time() or 0) * 60
        if current_frame - last_altitude_log_frame > 15 then  -- Log every ~0.25s
            -- Build detailed status string
            local vertical_status = "LEVEL"
            if is_moving_up then
                vertical_status = "↑ CLIMBING"
            elseif is_moving_down then
                vertical_status = "↓ DESCENDING"
            end

            -- Build obstacle status (tiered detection)
            local obs_status = "CLEAR"
            if obstacle_data.obstacle_very_close then
                obs_status = string.format("🚨🚨 VERY CLOSE! %.1fy", obstacle_data.closest_distance)
            elseif obstacle_data.obstacle_close then
                obs_status = string.format("⚠️ CLOSE! %.1fy", obstacle_data.closest_distance)
            elseif obstacle_data.obstacle_ahead then
                obs_status = string.format("AHEAD %.1fy (%d rays)", obstacle_data.closest_distance, obstacle_data.blocked_count)
            elseif obstacle_data.obstacle_far then
                obs_status = string.format("FAR %.1fy", obstacle_data.closest_distance)
            end

            -- More descriptive phase names for logging
            local phase_display = flight_phase
            if flight_phase == "GLIDE" then
                phase_display = "GLIDE ✈️"
            elseif flight_phase == "CLIMB" then
                phase_display = "CLIMB ⬆️"
            elseif flight_phase == "DESCEND" then
                phase_display = "DESCEND ⬇️"
            end

            log_debug(string.format("[%s] %s | Z: %.1f → %.1f (Δ%.1f) | Dist=%.1f | %s",
                phase_display, vertical_status, pos.z, target_altitude, altitude_diff, distance_2d, obs_status))

            if locked_cruise_altitude then
                log_debug(string.format("  Glide max: %.1f | Ground: %.1f | Clearance: %.1f | Blocked: %d/120",
                    locked_cruise_altitude, ground_height, pos.z - ground_height, obstacle_data.blocked_count))
            end

            if obstacle_data.max_height > 0 then
                log_debug(string.format("  Max obstacle height detected: %.1f yards", obstacle_data.max_height))
            end

            if flight_phase == "DESCEND" then
                local dest_ground = get_ground_height(final_destination)
                if dest_ground then
                    log_debug(string.format("  Glide: %.1f → %.1f (Δ%.1f over %.1f yards)",
                        pos.z, target_altitude, pos.z - target_altitude, distance_2d))
                end
            end

            last_altitude_log_frame = current_frame
        end

        -- Horizontal direction control (2D only)
        local dir = player:get_direction()
        if dir then
            local to_target_x = final_destination.x - pos.x
            local to_target_y = final_destination.y - pos.y
            local len_2d = math.sqrt(to_target_x * to_target_x + to_target_y * to_target_y)

            if len_2d > 0.001 then
                to_target_x = to_target_x / len_2d
                to_target_y = to_target_y / len_2d

                local turn_speed = 0.18
                local new_dir_x = dir.x + (to_target_x - dir.x) * turn_speed
                local new_dir_y = dir.y + (to_target_y - dir.y) * turn_speed

                local look_distance = 50
                local look_point = vec3.new(
                    pos.x + new_dir_x * look_distance,
                    pos.y + new_dir_y * look_distance,
                    pos.z  -- Keep current Z
                )

                core.input.look_at(look_point)
            end
        end

        -- Vertical control with REAL-TIME obstacle avoidance
        -- Tiered reaction system:
        -- 1. VERY CLOSE (<5y) - EMERGENCY! Stop forward + aggressive climb
        -- 2. CLOSE (<10y) - Stop forward + climb
        -- 3. AHEAD (<20y) - Start climbing early
        -- 4. FAR (<40y) - Prepare (increase target altitude)
        -- 5. Low ground clearance (<10y) - Climb

        local ground_clearance = pos.z - ground_height

        -- Emergency climb conditions
        local emergency_climb = (ground_clearance < 10 and altitude_diff > 0) or
                               obstacle_data.obstacle_very_close or
                               obstacle_data.obstacle_close

        -- Boost target altitude if obstacles detected (ONE TIME ONLY, not every frame!)
        -- Only boost if we don't already have a boosted target
        local boosted_target = locked_cruise_altitude and (locked_cruise_altitude + 30) or (pos.z + 50)
        if (obstacle_data.obstacle_ahead or obstacle_data.obstacle_close or obstacle_data.obstacle_very_close) and target_altitude < boosted_target then
            -- Only log if this is a NEW boost (different target than last time)
            if not last_obstacle_boost_target or math.abs(boosted_target - last_obstacle_boost_target) > 5 then
                local old_target = target_altitude
                target_altitude = boosted_target
                altitude_diff = target_altitude - pos.z
                last_obstacle_boost_target = boosted_target
                log_debug(string.format("🚨 OBSTACLE BOOST: %.1f → %.1f (+%.1f) | CurZ=%.1f | NewDiff=%.1f",
                    old_target, target_altitude, target_altitude - old_target, pos.z, altitude_diff))
            else
                -- Same boost target - just apply it without logging
                target_altitude = boosted_target
                altitude_diff = target_altitude - pos.z
            end
        else
            -- No obstacles - clear the boost tracker
            last_obstacle_boost_target = nil
        end

        -- NATURAL GLIDE STRATEGY: Only actively control altitude when needed
        -- CLIMB phase: Climb to cruise altitude
        -- GLIDE phase: Do NOTHING - let gravity pull you down naturally
        -- DESCEND phase: Actively descend to landing

        if flight_phase == "CLIMB" then
            -- CLIMB PHASE: Actively climb to cruise altitude
            if not is_moving_up and altitude_diff > 5 then
                core.input.move_up_start()
                is_moving_up = true
                log_debug(string.format("⬆️ CLIMBING to cruise altitude (diff=%.1f)", altitude_diff))
            elseif is_moving_up and altitude_diff < 2 then
                -- Reached cruise altitude - stop climbing and start gliding
                core.input.move_up_stop()
                is_moving_up = false
                log_debug(string.format("✈️ REACHED CRUISE - starting natural glide from %.1f yards", pos.z))
            end

        elseif flight_phase == "GLIDE" then
            -- GLIDE PHASE: Let gravity do the work - only intervene for safety

            -- Check if we need to climb for safety (emergency or obstacle)
            if emergency_climb or obstacle_data.obstacle_ahead then
                -- Safety intervention needed - climb!
                if not is_moving_up then
                    core.input.move_up_start()
                    is_moving_up = true
                    if obstacle_data.obstacle_very_close or obstacle_data.obstacle_close then
                        log_debug(string.format("🚨 GLIDE INTERRUPTED - obstacle %.1fy! Climbing.", obstacle_data.closest_distance))
                    else
                        log_debug(string.format("⚠️ GLIDE INTERRUPTED - low altitude %.1f! Climbing.", pos.z))
                    end
                end
                -- Keep climbing until safe
            else
                -- No emergency - safe to glide
                if is_moving_up then
                    core.input.move_up_stop()
                    is_moving_up = false
                    log_debug("✈️ GLIDING - stopped climb, resuming natural descent")
                end
            end

        elseif flight_phase == "DESCEND" then
            -- DESCEND PHASE: Actively descend to landing height
            if not is_moving_down and altitude_diff < -5 then
                core.input.move_down_start()
                is_moving_down = true
                log_debug(string.format("⬇️ DESCENDING to landing (diff=%.1f)", altitude_diff))
            elseif is_moving_down and altitude_diff > -2 then
                -- Close to landing height - stop descending
                core.input.move_down_stop()
                is_moving_down = false
                log_debug("🛬 APPROACHING LANDING - stopped descent")
            end
        end

        -- Forward movement control with obstacle avoidance
        -- STOP moving forward if obstacle very close (<10y) to prevent collision
        if obstacle_data.obstacle_very_close or obstacle_data.obstacle_close then
            -- STOP! Obstacle too close - only climb, don't move forward
            if is_moving_forward then
                core.input.move_forward_stop()
                is_moving_forward = false
                log_debug(string.format("🛑 STOPPED FORWARD - obstacle %.1fy! Climbing only.", obstacle_data.closest_distance))
            end
        else
            -- Safe to move forward
            if not is_moving_forward then
                core.input.move_forward_start()
                is_moving_forward = true
                log_debug("▶️ RESUMED FORWARD movement")
            end
        end

        return true

    elseif flight_state == FlightState.DESCENDING then
        -- Landing sequence
        update_landing_sequence(player)
        return true

    elseif flight_state == FlightState.DISMOUNTING then
        -- Wait for dismount to complete
        if not player:is_mounted() then
            flight_state = FlightState.GROUNDED
            core.log("[Flying] Landed and dismounted - flight complete!")

            -- Reset all flight state
            path_analysis = nil
            locked_cruise_altitude = nil
            last_obstacle_boost_target = nil
            is_moving_up = false
            is_moving_down = false
            is_moving_forward = false
            last_terrain_check_time = 0

            log_debug("Flight complete - all state reset")

            -- Signal path completion to main system
            if on_flight_complete_callback then
                on_flight_complete_callback()
            end

            return false  -- Ground can resume (but we signaled completion, so it should stop)
        end
        return true
    end

    return false
end

--- Analyze and prepare flight for a new path
--- @param path table
--- @param player game_object
function Flying.analyze_and_prepare_flight(path, player)
    core.log("[Flying] analyze_and_prepare_flight called (Flying.enabled=" .. tostring(Flying.enabled) .. ", player=" .. tostring(player ~= nil) .. ")")

    if not Flying.enabled then
        core.log("[Flying] Aborting: Flying.enabled is false")
        return
    end
    if not player then
        core.log("[Flying] Aborting: player is nil")
        return
    end

    core.log("[Flying] Running path analysis...")
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
    if flight_state == FlightState.MOUNTING then
        -- Cancel mounting process
        flight_state = FlightState.GROUNDED
        core.log("[Flying] Mounting cancelled")
    elseif flight_state == FlightState.AIRBORNE then
        local player = core.object_manager.get_local_player()
        if player then
            initiate_landing(player)
        end
    end
end

--- Force stop all flying (when user presses stop button)
function Flying.force_stop()
    core.log("[Flying] Force stop requested")

    -- Stop all movement immediately
    stop_all_movement()

    -- Reset all flying state
    flight_state = FlightState.GROUNDED
    path_analysis = nil
    locked_cruise_altitude = nil
    last_obstacle_boost_target = nil
    is_moving_up = false
    is_moving_down = false
    is_moving_forward = false
    last_terrain_check_time = 0
    is_descending_to_land = false

    log_debug("Force stop - all state reset")
end

--- Start flight control test
function Flying.start_flight_control_test()
    local player = core.object_manager.get_local_player()
    if not player then
        core.log("[Flight Test] ERROR: No player")
        return
    end

    if not player:is_flying() then
        core.log("[Flight Test] ERROR: You must be flying first! Mount up and fly into the air, then click the button.")
        return
    end

    init_flight_test_log()
    flight_test_active = true
    flight_test_stage = 1
    flight_test_start_time = core.time and core.time() or 0
    flight_test_start_pos = player:get_position()

    log_flight_test("==============================================")
    log_flight_test("FLIGHT CONTROL TEST STARTED")
    log_flight_test("==============================================")
    log_flight_test("Starting position: X=" .. string.format("%.1f", flight_test_start_pos.x) ..
                    " Y=" .. string.format("%.1f", flight_test_start_pos.y) ..
                    " Z=" .. string.format("%.1f", flight_test_start_pos.z))
    log_flight_test("")
    log_flight_test("Each test runs for 3 seconds")
    log_flight_test("Position changes will be logged for each method")
    log_flight_test("")

    core.log("[Flight Test] STARTED - check scripts_log/flight_control_test.txt for detailed results")
end

local function update_flight_control_test(player)
    if not flight_test_active then return end

    local elapsed = (core.time and core.time() or 0) - flight_test_start_time
    local pos = player:get_position()
    if not pos then return end

    local stage_duration = 3.0  -- Each test runs for 3 seconds

    -- Check if current stage is complete
    if elapsed >= stage_duration then
        -- Log results of completed stage
        local dx = pos.x - flight_test_start_pos.x
        local dy = pos.y - flight_test_start_pos.y
        local dz = pos.z - flight_test_start_pos.z
        local dist_2d = math.sqrt(dx*dx + dy*dy)
        local dist_3d = math.sqrt(dx*dx + dy*dy + dz*dz)

        log_flight_test("RESULT: Moved " .. string.format("%.1f", dist_2d) .. " yards horizontally, " ..
                       string.format("%.1f", dz) .. " yards vertically, " ..
                       string.format("%.1f", dist_3d) .. " yards total")
        log_flight_test("End position: X=" .. string.format("%.1f", pos.x) ..
                       " Y=" .. string.format("%.1f", pos.y) ..
                       " Z=" .. string.format("%.1f", pos.z))
        log_flight_test("")

        -- Stop current test's inputs
        stop_all_movement()

        -- Move to next stage
        flight_test_stage = flight_test_stage + 1
        flight_test_start_time = core.time and core.time() or 0
        flight_test_start_pos = pos

        -- Wait 0.5s between tests
        if flight_test_stage > 10 then
            log_flight_test("==============================================")
            log_flight_test("FLIGHT CONTROL TEST COMPLETE")
            log_flight_test("==============================================")
            log_flight_test("Review the results above to see which methods work best")
            core.log("[Flight Test] COMPLETE - check scripts_log/flight_control_test.txt for results")
            flight_test_active = false
            return
        end
    end

    -- Log ONCE at start of each stage
    if elapsed < 0.1 then
        if flight_test_stage == 1 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 1: Baseline - move_forward_start() ONLY")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Should move forward horizontally, no altitude change")
        elseif flight_test_stage == 2 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 2: look_at point 30 yards ahead (same Z)")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Should fly straight ahead horizontally")
        elseif flight_test_stage == 3 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 3: look_at point 30 yards ahead, 20 yards UP")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Should climb while moving forward")
        elseif flight_test_stage == 4 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 4: look_at point 30 yards ahead, 50 yards UP (steep climb)")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Should climb steeply")
        elseif flight_test_stage == 5 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 5: look_at point straight UP (10 yards ahead, 100 yards up)")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Should climb almost vertically")
        elseif flight_test_stage == 6 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 6: move_up_start() + move_forward_start() (no look_at)")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Might ascend, or might not work")
        elseif flight_test_stage == 7 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 7: move_down_start() + move_forward_start() (no look_at)")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Might descend, or might not work")
        elseif flight_test_stage == 8 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 8: look_at UP + move_up_start() + move_forward_start()")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Combined effect test")
        elseif flight_test_stage == 9 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 9: look_at DOWN + move_down_start() + move_forward_start()")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Combined descent test")
        elseif flight_test_stage == 10 then
            log_flight_test("----------------------------------------------")
            log_flight_test("TEST 10: look_at point 30 yards ahead, 30 yards DOWN (descending)")
            log_flight_test("----------------------------------------------")
            log_flight_test("Expected: Should descend while moving forward")
        end
    end

    -- Execute movement commands EVERY FRAME (like ground movement does)
    if flight_test_stage == 1 then
        core.input.move_forward_start()

    elseif flight_test_stage == 2 then
        local look_ahead = vec3.new(pos.x + 30, pos.y, pos.z)
        core.input.look_at(look_ahead)
        core.input.move_forward_start()

    elseif flight_test_stage == 3 then
        local look_up = vec3.new(pos.x + 30, pos.y, pos.z + 20)
        core.input.look_at(look_up)
        core.input.move_forward_start()

    elseif flight_test_stage == 4 then
        local look_steep = vec3.new(pos.x + 30, pos.y, pos.z + 50)
        core.input.look_at(look_steep)
        core.input.move_forward_start()

    elseif flight_test_stage == 5 then
        local look_vertical = vec3.new(pos.x + 10, pos.y, pos.z + 100)
        core.input.look_at(look_vertical)
        core.input.move_forward_start()

    elseif flight_test_stage == 6 then
        core.input.move_up_start()
        core.input.move_forward_start()

    elseif flight_test_stage == 7 then
        core.input.move_down_start()
        core.input.move_forward_start()

    elseif flight_test_stage == 8 then
        local look_up_combo = vec3.new(pos.x + 30, pos.y, pos.z + 50)
        core.input.look_at(look_up_combo)
        core.input.move_up_start()
        core.input.move_forward_start()

    elseif flight_test_stage == 9 then
        local look_down_combo = vec3.new(pos.x + 30, pos.y, pos.z - 30)
        core.input.look_at(look_down_combo)
        core.input.move_down_start()
        core.input.move_forward_start()

    elseif flight_test_stage == 10 then
        local look_down = vec3.new(pos.x + 30, pos.y, pos.z - 30)
        core.input.look_at(look_down)
        core.input.move_forward_start()
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

    -- Visualize obstacle scan results (if enabled)
    if show_obstacle_visualization and #obstacle_scan_results > 0 then
        local blocked_count = 0
        local clear_count = 0

        for _, scan in ipairs(obstacle_scan_results) do
            -- Convert 3D positions to screen coordinates
            local start_screen = core.graphics.w2s(scan.start_pos)
            local end_screen = core.graphics.w2s(scan.end_pos)

            if start_screen and end_screen then
                -- Draw ray line
                if scan.blocked then
                    -- RED for blocked rays
                    core.graphics.line_2d(start_screen, end_screen, color.new(255, 0, 0, 150), 1)
                    blocked_count = blocked_count + 1

                    -- Draw small circle at obstacle point
                    core.graphics.circle_2d_filled(end_screen, 3, color.new(255, 0, 0, 200))
                else
                    -- GREEN for clear rays (make them semi-transparent to reduce clutter)
                    core.graphics.line_2d(start_screen, end_screen, color.new(0, 255, 0, 50), 1)
                    clear_count = clear_count + 1
                end
            end
        end

        -- Display scan statistics
        local scan_age = (core.time and core.time() or 0) - last_obstacle_scan_time
        local total_rays = blocked_count + clear_count
        local scan_text = string.format("Obstacle Scan: %d blocked / %d clear (%d rays, %.1fs ago)",
            blocked_count, clear_count, total_rays, scan_age)
        core.graphics.text_2d(
            scan_text,
            vec2.new(screen_size.x / 2, 90),
            11,
            color.new(255, 200, 100, 255),
            true
        )

        -- Legend
        core.graphics.text_2d(
            "Green = Clear | Red = Obstacle",
            vec2.new(screen_size.x / 2, 105),
            10,
            color.new(200, 200, 200, 180),
            true
        )
    end
end

--- Set callback for when flying completes (called from main.lua)
--- @param callback function
function Flying.set_on_complete_callback(callback)
    on_flight_complete_callback = callback
end

--- Set obstacle visualization state
--- @param enabled boolean
function Flying.set_show_obstacle_viz(enabled)
    show_obstacle_visualization = enabled
end

--- Get obstacle visualization state
--- @return boolean
function Flying.get_show_obstacle_viz()
    return show_obstacle_visualization
end

-- Register global update callback for flight test (runs independently of path movement)
core.register_on_update_callback(function()
    if flight_test_active then
        local player = core.object_manager.get_local_player()
        if player then
            update_flight_control_test(player)
        end
    end
end)

-- Export module
return Flying
