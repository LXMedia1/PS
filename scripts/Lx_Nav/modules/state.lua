--[[
    Lx_Nav State Management
    Author: Lexxer

    Shared state for navigation: start/end points, path, search state.
]]

local State = {}

-- Search states
State.SEARCH_IDLE = 0
State.SEARCH_IN_PROGRESS = 1
State.SEARCH_FOUND = 2
State.SEARCH_FAILED = 3

-- Current state
State.search_state = State.SEARCH_IDLE

-- Start and end points (world coordinates)
State.start_point = nil   -- {x, y, z, mapId}
State.end_point = nil     -- {x, y, z, mapId}

-- Start and end nodes (graph node indices)
State.start_node = nil
State.end_node = nil

-- Current path (list of waypoints after smoothing)
State.path = nil          -- {{x, y, z}, ...}
State.path_length = 0     -- Total distance

-- Raw polygon path (before smoothing)
State.polygon_path = nil  -- {node_index, ...}

-- Search statistics
State.stats = {
    nodes_processed = 0,
    nodes_in_open = 0,
    nodes_in_closed = 0,
    frames_elapsed = 0,
    time_elapsed_ms = 0,
}

-- Current loaded map
State.current_map_id = nil
State.graph = nil         -- Loaded PSNG data

-- Visualization settings
State.show_path = true
State.show_debug = true

-- Set start point
function State.set_start(x, y, z, mapId)
    State.start_point = {x = x, y = y, z = z, mapId = mapId}
    State.start_node = nil  -- Will be resolved when pathfinding starts
    State.clear_path()
end

-- Set end point
function State.set_end(x, y, z, mapId)
    State.end_point = {x = x, y = y, z = z, mapId = mapId}
    State.end_node = nil
    State.clear_path()
end

-- Clear current path
function State.clear_path()
    State.path = nil
    State.path_length = 0
    State.polygon_path = nil
    State.search_state = State.SEARCH_IDLE
    State.reset_stats()
end

-- Clear all (start, end, path)
function State.clear_all()
    State.start_point = nil
    State.end_point = nil
    State.start_node = nil
    State.end_node = nil
    State.clear_path()
end

-- Reset search statistics
function State.reset_stats()
    State.stats.nodes_processed = 0
    State.stats.nodes_in_open = 0
    State.stats.nodes_in_closed = 0
    State.stats.frames_elapsed = 0
    State.stats.time_elapsed_ms = 0
end

-- Get search state as string
function State.get_state_string()
    if State.search_state == State.SEARCH_IDLE then
        return "Idle"
    elseif State.search_state == State.SEARCH_IN_PROGRESS then
        return "Searching..."
    elseif State.search_state == State.SEARCH_FOUND then
        return "Path Found"
    else
        return "No Path"
    end
end

-- Check if we have valid start and end points
function State.has_valid_endpoints()
    return State.start_point ~= nil and State.end_point ~= nil
end

-- Check if endpoints are on the same map
function State.same_map()
    if not State.has_valid_endpoints() then
        return false
    end
    return State.start_point.mapId == State.end_point.mapId
end

return State
