--[[
    Lx_Nav A* Pathfinding
    Author: Lexxer

    Incremental A* pathfinding with frame budget.
    Processes nodes until time budget exhausted, continues next frame.
]]

local Config = require("modules/config")
local Utils = require("modules/utils")
local State = require("modules/state")
local BinaryHeap = require("modules/binary_heap")
local Loader = require("modules/loader")

local AStar = {}

-- Internal state
local open_heap = nil
local closed_set = nil
local g_scores = nil
local came_from = nil
local edge_used = nil  -- Track which edge was used to reach each node
local goal_node = nil
local start_time = 0

-- Initialize a new search
function AStar.start_search(graph, startNode, endNode)
    if not graph or not startNode or not endNode then
        Utils.log_error("Invalid parameters for A* search")
        return false
    end

    -- Reset state
    open_heap = BinaryHeap.new()
    closed_set = {}
    g_scores = {}
    came_from = {}
    edge_used = {}
    goal_node = endNode

    -- Initialize start node
    g_scores[startNode] = 0
    local h = AStar.heuristic(graph, startNode, endNode)
    open_heap:push(startNode, h)

    State.search_state = State.SEARCH_IN_PROGRESS
    State.reset_stats()
    start_time = core.time()

    Utils.file_log(string.format("A* search started: %d -> %d", startNode, endNode))
    return true
end

-- Heuristic function (Euclidean distance)
function AStar.heuristic(graph, nodeA, nodeB)
    local ax, ay, az = Loader.get_node_pos(graph, nodeA)
    local bx, by, bz = Loader.get_node_pos(graph, nodeB)

    if not ax or not bx then
        return math.huge
    end

    return Utils.distance_3d(ax, ay, az, bx, by, bz)
end

-- Process one frame of A* search
-- Returns: SEARCH_IN_PROGRESS, SEARCH_FOUND, or SEARCH_FAILED
function AStar.process_frame(graph, budget_ms)
    if State.search_state ~= State.SEARCH_IN_PROGRESS then
        return State.search_state
    end

    if not open_heap then
        State.search_state = State.SEARCH_FAILED
        return State.search_state
    end

    budget_ms = budget_ms or Config.FRAME_BUDGET_MS
    local frame_start = core.time() * 1000
    local nodes_this_frame = 0

    while not open_heap:empty() do
        -- Check time budget
        local elapsed = core.time() * 1000 - frame_start
        if elapsed >= budget_ms then
            -- Budget exhausted, continue next frame
            State.stats.frames_elapsed = State.stats.frames_elapsed + 1
            State.stats.nodes_in_open = open_heap:count()
            return State.SEARCH_IN_PROGRESS
        end

        -- Pop node with lowest f_score
        local current = open_heap:pop()
        nodes_this_frame = nodes_this_frame + 1
        State.stats.nodes_processed = State.stats.nodes_processed + 1

        -- Skip if already processed
        if closed_set[current] then
            goto continue
        end
        closed_set[current] = true
        State.stats.nodes_in_closed = State.stats.nodes_in_closed + 1

        -- Goal check
        if current == goal_node then
            State.search_state = State.SEARCH_FOUND
            State.stats.time_elapsed_ms = (core.time() - start_time) * 1000
            Utils.file_log(string.format("Path found! Nodes: %d, Time: %.1fms",
                State.stats.nodes_processed, State.stats.time_elapsed_ms))
            return State.search_state
        end

        -- Process neighbors
        local edges = Loader.get_node_edges(graph, current)
        for _, e in ipairs(edges) do
            local neighbor = e.edge.targetNode

            if not closed_set[neighbor] then
                local tentative_g = (g_scores[current] or math.huge) + e.edge.cost

                if tentative_g < (g_scores[neighbor] or math.huge) then
                    -- Found better path to neighbor
                    came_from[neighbor] = current
                    edge_used[neighbor] = e.edge
                    g_scores[neighbor] = tentative_g

                    local h = AStar.heuristic(graph, neighbor, goal_node)
                    local f = tentative_g + h

                    open_heap:upsert(neighbor, f)
                end
            end
        end

        ::continue::
    end

    -- Open set empty, no path found
    State.search_state = State.SEARCH_FAILED
    State.stats.time_elapsed_ms = (core.time() - start_time) * 1000
    Utils.file_log("No path found")
    return State.search_state
end

-- Reconstruct path from came_from chain
function AStar.reconstruct_path(graph, endNode)
    local path = {}
    local polygon_path = {}
    local current = endNode

    while current do
        local x, y, z = Loader.get_node_pos(graph, current)
        if x then
            table.insert(path, 1, {x = x, y = y, z = z})
            table.insert(polygon_path, 1, current)
        end
        current = came_from[current]
    end

    -- Calculate total path length
    local total_dist = 0
    for i = 2, #path do
        local p1 = path[i-1]
        local p2 = path[i]
        total_dist = total_dist + Utils.distance_3d(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z)
    end

    State.path = path
    State.polygon_path = polygon_path
    State.path_length = total_dist

    Utils.file_log(string.format("Path reconstructed: %d waypoints, %.1f yards",
        #path, total_dist))

    return path
end

-- Get edge used to reach a node (for funnel algorithm)
function AStar.get_edge_used(nodeIdx)
    return edge_used and edge_used[nodeIdx] or nil
end

-- Cancel current search
function AStar.cancel()
    State.search_state = State.SEARCH_IDLE
    open_heap = nil
    closed_set = nil
    g_scores = nil
    came_from = nil
    edge_used = nil
    goal_node = nil
end

-- Check if search is in progress
function AStar.is_searching()
    return State.search_state == State.SEARCH_IN_PROGRESS
end

return AStar
