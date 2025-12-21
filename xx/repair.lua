-- NavMesh Repair Module v3
-- Multi-waypoint bridges, reversible blacklist, improved triangle selection
-- Hold K + click = connect to triangle, click without K = free waypoint

local color = require("common/color")
local vec3 = require("common/geometry/vector_3")
local vec2 = require("common/geometry/vector_2")

local Repair = {}

-- Configuration
local CONFIG = {
    enabled = false,
    mode = nil,  -- "bridge", "blacklist_tri", "blacklist_point"
}

-- State
local State = {
    -- Hover preview
    hover_triangle = nil,     -- {tileId, polyIdx, triangleIdx, vertices, center}

    -- Bridge recording (multi-waypoint)
    recording_bridge = false,
    current_bridge_waypoints = {},  -- Array of {tileId, polyIdx, triIdx, x, y, z, isTri}

    -- Staged bridges (waiting for save)
    staged_bridges = {},      -- Each has .waypoints array

    -- Saved data
    bridges = {},             -- Multi-waypoint bridges
    blacklist_tris = {},      -- [{tileId, polyIdx, triangleIdx}, ...]
    blacklist_points = {},    -- [{x, y, z, radius}, ...]

    -- Selection
    selected_point_idx = nil,

    -- Preview/highlight for deletion (click once to preview, again to delete)
    preview_bridge_idx = nil,
    preview_tri_idx = nil,
    preview_point_idx = nil,

    -- Undo system (single level)
    last_action = nil,  -- {type="add_bridge"|"add_blacklist_tri"|"add_blacklist_point", data=...}

    -- Drag state
    dragging = nil,
    drag_active = false,
}

-- Colors
local COLORS = {
    hover = color.new(0, 255, 100, 150),              -- Bright green hover
    recording_line = color.new(0, 255, 0, 255),       -- Green recording path
    recording_dot_tri = color.new(255, 255, 255, 255),-- White for triangle waypoints
    recording_dot_free = color.new(150, 150, 150, 200),-- Gray for free waypoints
    staged_bridge = color.new(255, 200, 0, 200),      -- Yellow staged
    staged_point = color.new(255, 200, 0, 255),
    saved_bridge = color.new(0, 255, 255, 255),       -- Cyan saved
    saved_point = color.new(0, 255, 255, 255),
    blacklist_tri = color.new(255, 0, 0, 100),        -- Red blocked tri
    blacklist_point = color.new(255, 0, 0, 80),
    blacklist_center = color.new(255, 0, 0, 255),
    selected_point = color.new(255, 255, 0, 255),
    hint_text = color.new(200, 200, 200, 255),
    preview_highlight = color.new(255, 0, 255, 200),  -- Magenta for preview
}

-- File paths (separate files)
local BRIDGE_FILE = "mmaps/lx_nav_bridges.json"
local BLACKLIST_TRIS_FILE = "mmaps/lx_nav_blacklist_tris.json"
local BLACKLIST_POINTS_FILE = "mmaps/lx_nav_blacklist_points.json"

-- Reference to PathState
local PathState = nil

-- R key virtual key code (for anchoring to triangles)
local VK_R = 0x52

-- =========================
-- Utility Functions
-- =========================

local function point_in_triangle_2d(px, py, v0, v1, v2)
    local d00 = (v1.x - v0.x) * (v1.x - v0.x) + (v1.y - v0.y) * (v1.y - v0.y)
    local d01 = (v1.x - v0.x) * (v2.x - v0.x) + (v1.y - v0.y) * (v2.y - v0.y)
    local d11 = (v2.x - v0.x) * (v2.x - v0.x) + (v2.y - v0.y) * (v2.y - v0.y)
    local d20 = (px - v0.x) * (v1.x - v0.x) + (py - v0.y) * (v1.y - v0.y)
    local d21 = (px - v0.x) * (v2.x - v0.x) + (py - v0.y) * (v2.y - v0.y)

    local denom = d00 * d11 - d01 * d01
    if math.abs(denom) < 0.0001 then return false end

    local u = (d11 * d20 - d01 * d21) / denom
    local v = (d00 * d21 - d01 * d20) / denom

    return u >= 0 and v >= 0 and (u + v) <= 1
end

local function get_detail_vertex(tile, polyIdx, vertIdx)
    local detail = tile.detailMeshes and tile.detailMeshes[polyIdx]
    local nv = tile.pVertCount and tile.pVertCount[polyIdx] or 0
    local base = (polyIdx - 1) * 6

    if vertIdx < nv then
        local vi = tile.pVerts and tile.pVerts[base + vertIdx + 1]
        if vi and tile.vx and tile.vx[vi] then
            return {x = tile.vx[vi], y = tile.vy[vi], z = tile.vz[vi]}
        end
    else
        if detail and tile.detailVerts then
            local detailIdx = detail.vertBase + (vertIdx - nv) + 1
            local dv = tile.detailVerts[detailIdx]
            if dv then
                return {x = dv.x, y = dv.y, z = dv.z}
            end
        end
    end
    return nil
end

local function dist2D(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function is_r_held()
    return core.input.is_key_pressed(VK_R)
end

-- =========================
-- Core Functions
-- =========================

function Repair.init(pathState)
    PathState = pathState
    Repair.load_data()
end

function Repair.set_enabled(enabled)
    CONFIG.enabled = enabled
    if not enabled then
        State.hover_triangle = nil
        State.recording_bridge = false
        State.current_bridge_waypoints = {}
        CONFIG.mode = nil
    end
end

function Repair.is_enabled()
    return CONFIG.enabled
end

function Repair.set_mode(mode)
    -- Clear recording state when switching modes
    if CONFIG.mode == "bridge" and mode ~= "bridge" then
        State.recording_bridge = false
        State.current_bridge_waypoints = {}
    end
    CONFIG.mode = mode
    State.hover_triangle = nil
end

function Repair.get_mode()
    return CONFIG.mode
end

-- =========================
-- Triangle Selection (Simplified)
-- =========================

-- Find triangle at cursor position, prioritized by player Z
function Repair.get_triangle_at(cursor_pos)
    if not PathState or not PathState.world then return nil end

    local tiles = PathState.world:get_all_tiles()
    if not tiles then return nil end

    local player = core.object_manager.get_local_player()
    local player_pos = player and player:get_position() or cursor_pos
    local player_z = player_pos.z

    local candidates = {}
    local SEARCH_RADIUS = 8.0  -- Search within 8 yards of cursor

    for tileId, tile in pairs(tiles) do
        if tile.detailMeshes and tile.detailTris then
            for polyIdx = 1, (tile.polyCount or 0) do
                local detail = tile.detailMeshes[polyIdx]
                if detail and detail.triCount and detail.triCount > 0 then
                    for t = 0, detail.triCount - 1 do
                        local triIdx = (detail.triBase + t) * 4
                        local v0i = tile.detailTris[triIdx + 1]
                        local v1i = tile.detailTris[triIdx + 2]
                        local v2i = tile.detailTris[triIdx + 3]

                        if v0i and v1i and v2i then
                            local v0 = get_detail_vertex(tile, polyIdx, v0i)
                            local v1 = get_detail_vertex(tile, polyIdx, v1i)
                            local v2 = get_detail_vertex(tile, polyIdx, v2i)

                            if v0 and v1 and v2 then
                                local centerX = (v0.x + v1.x + v2.x) / 3
                                local centerY = (v0.y + v1.y + v2.y) / 3
                                local avgZ = (v0.z + v1.z + v2.z) / 3

                                -- Check if cursor is near triangle center
                                local cursor_dist = dist2D(cursor_pos.x, cursor_pos.y, centerX, centerY)
                                local in_triangle = point_in_triangle_2d(cursor_pos.x, cursor_pos.y, v0, v1, v2)

                                if in_triangle or cursor_dist < SEARCH_RADIUS then
                                    local z_diff = math.abs(player_z - avgZ)
                                    table.insert(candidates, {
                                        tileId = tileId,
                                        polyIdx = polyIdx,
                                        triangleIdx = t,
                                        tile = tile,
                                        vertices = {v0, v1, v2},
                                        center = {x = centerX, y = centerY, z = avgZ},
                                        avgZ = avgZ,
                                        z_diff = z_diff,
                                        cursor_dist = cursor_dist,
                                        in_triangle = in_triangle
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    -- Sort: prioritize in-triangle hits, then by Z proximity to player
    table.sort(candidates, function(a, b)
        -- In-triangle hits first
        if a.in_triangle and not b.in_triangle then return true end
        if b.in_triangle and not a.in_triangle then return false end
        -- Then by Z difference
        return a.z_diff < b.z_diff
    end)

    return candidates[1]
end

-- Get triangle data for rendering
local function get_triangle_data(tileId, polyIdx, triangleIdx)
    if not PathState or not PathState.world then return nil end

    local tile = PathState.world.tilesById and PathState.world.tilesById[tileId]
    if not tile or not tile.detailMeshes or not tile.detailTris then return nil end

    local detail = tile.detailMeshes[polyIdx]
    if not detail or triangleIdx >= detail.triCount then return nil end

    local triIdx = (detail.triBase + triangleIdx) * 4
    local v0i = tile.detailTris[triIdx + 1]
    local v1i = tile.detailTris[triIdx + 2]
    local v2i = tile.detailTris[triIdx + 3]

    if not v0i or not v1i or not v2i then return nil end

    local v0 = get_detail_vertex(tile, polyIdx, v0i)
    local v1 = get_detail_vertex(tile, polyIdx, v1i)
    local v2 = get_detail_vertex(tile, polyIdx, v2i)

    if v0 and v1 and v2 then
        return {vertices = {v0, v1, v2}}
    end
    return nil
end

-- Update hover preview
function Repair.update_hover(world_pos)
    if not CONFIG.enabled or not CONFIG.mode then
        State.hover_triangle = nil
        return
    end

    -- Only show hover when R is held in bridge mode, or always in other modes
    if CONFIG.mode == "bridge" then
        if is_r_held() then
            State.hover_triangle = Repair.get_triangle_at(world_pos)
        else
            State.hover_triangle = nil
        end
    else
        State.hover_triangle = Repair.get_triangle_at(world_pos)
    end
end

-- =========================
-- Click Handling
-- =========================

function Repair.handle_click(world_pos)
    if not CONFIG.enabled or not world_pos then return end
    local mode = CONFIG.mode

    if mode == "bridge" then
        Repair.handle_bridge_click(world_pos)
    elseif mode == "blacklist_tri" then
        Repair.handle_blacklist_tri_click(world_pos)
    elseif mode == "blacklist_point" then
        Repair.handle_blacklist_point_click(world_pos)
    end
end

function Repair.handle_bridge_click(world_pos)
    local r_held = is_r_held()

    if r_held then
        -- R held: must connect to triangle (anchor point)
        local tri = Repair.get_triangle_at(world_pos)
        if not tri then return end  -- No triangle found, ignore click

        -- Use click position (not triangle center) but store triangle data for pathfinding
        local waypoint = {
            tileId = tri.tileId,
            polyIdx = tri.polyIdx,
            triIdx = tri.triangleIdx,
            x = world_pos.x,
            y = world_pos.y,
            z = world_pos.z,
            isTri = true,
            vertices = tri.vertices
        }

        -- Check if we should finish the bridge
        if #State.current_bridge_waypoints >= 1 then
            -- We have at least one waypoint, this could be the end
            local first = State.current_bridge_waypoints[1]
            if first.isTri then
                -- First waypoint is on triangle, this R+click completes the bridge
                table.insert(State.current_bridge_waypoints, waypoint)
                Repair.finish_current_bridge()
                return
            end
        end

        -- Start or continue bridge
        table.insert(State.current_bridge_waypoints, waypoint)
        State.recording_bridge = true

    else
        -- No R: add free waypoint (only if we already started with a triangle)
        if #State.current_bridge_waypoints == 0 then
            -- Can't start bridge with free waypoint
            return
        end

        local first = State.current_bridge_waypoints[1]
        if not first.isTri then
            -- First waypoint must be on triangle
            return
        end

        -- Add free waypoint
        local waypoint = {
            tileId = nil,
            polyIdx = nil,
            triIdx = nil,
            x = world_pos.x,
            y = world_pos.y,
            z = world_pos.z,
            isTri = false,
            vertices = nil
        }
        table.insert(State.current_bridge_waypoints, waypoint)
    end
end

function Repair.finish_current_bridge()
    if #State.current_bridge_waypoints < 2 then
        State.current_bridge_waypoints = {}
        State.recording_bridge = false
        return
    end

    -- Validate: first and last must be on triangles
    local first = State.current_bridge_waypoints[1]
    local last = State.current_bridge_waypoints[#State.current_bridge_waypoints]

    if not first.isTri or not last.isTri then
        -- Invalid bridge, clear
        State.current_bridge_waypoints = {}
        State.recording_bridge = false
        return
    end

    -- Create bridge from waypoints
    local bridge = {
        id = core.time(),  -- Simple unique ID using core.time()
        waypoints = {}
    }

    for _, wp in ipairs(State.current_bridge_waypoints) do
        table.insert(bridge.waypoints, {
            tileId = wp.tileId,
            polyIdx = wp.polyIdx,
            triIdx = wp.triIdx,
            x = wp.x,
            y = wp.y,
            z = wp.z,
            isTri = wp.isTri
        })
    end

    -- Add to staged
    table.insert(State.staged_bridges, bridge)

    -- Clear recording state
    State.current_bridge_waypoints = {}
    State.recording_bridge = false
end

function Repair.handle_blacklist_tri_click(world_pos)
    local tri = Repair.get_triangle_at(world_pos)
    if not tri then return end

    if not Repair.is_triangle_blacklisted(tri.tileId, tri.polyIdx, tri.triangleIdx) then
        local bl = {
            tileId = tri.tileId,
            polyIdx = tri.polyIdx,
            triangleIdx = tri.triangleIdx
        }
        table.insert(State.blacklist_tris, bl)

        -- Track for undo
        State.last_action = {
            type = "add_blacklist_tri",
            data = bl,
            index = #State.blacklist_tris
        }

        Repair.save_blacklist_tris()
    end

    -- Deactivate mode after one click (single-shot)
    CONFIG.mode = nil
    State.hover_triangle = nil
end

function Repair.handle_blacklist_point_click(world_pos)
    -- Create new point (drag detection is handled in main.lua)
    local point = {
        x = world_pos.x,
        y = world_pos.y,
        z = world_pos.z,
        radius = 5
    }
    table.insert(State.blacklist_points, point)
    State.selected_point_idx = #State.blacklist_points

    -- Track for undo
    State.last_action = {
        type = "add_blacklist_point",
        data = point,
        index = #State.blacklist_points
    }

    Repair.save_blacklist_points()

    -- Single-shot: deactivate mode but keep point selected for radius editing
    CONFIG.mode = nil
end

-- =========================
-- Bridge Recording State
-- =========================

function Repair.is_recording()
    return State.recording_bridge
end

function Repair.get_recording_waypoints()
    return State.current_bridge_waypoints
end

function Repair.cancel_recording()
    State.current_bridge_waypoints = {}
    State.recording_bridge = false
end

-- =========================
-- Staged Bridge Management
-- =========================

function Repair.get_staged_bridges()
    return State.staged_bridges
end

function Repair.get_staged_count()
    return #State.staged_bridges
end

function Repair.save_staged_bridges()
    if #State.staged_bridges == 0 then return end

    for _, bridge in ipairs(State.staged_bridges) do
        table.insert(State.bridges, bridge)

        -- Track last action for undo
        State.last_action = {
            type = "add_bridge",
            data = bridge,
            index = #State.bridges
        }
    end

    State.staged_bridges = {}
    Repair.save_bridges()
end

function Repair.clear_staged_bridges()
    State.staged_bridges = {}
end

function Repair.remove_staged_bridge(idx)
    if idx and idx > 0 and idx <= #State.staged_bridges then
        table.remove(State.staged_bridges, idx)
    end
end

-- =========================
-- Undo System
-- =========================

function Repair.undo_last_action()
    if not State.last_action then return false end

    local action = State.last_action
    State.last_action = nil

    if action.type == "add_bridge" then
        -- Remove last bridge
        if action.index and action.index <= #State.bridges then
            table.remove(State.bridges, action.index)
            Repair.save_bridges()
            return true
        end
    elseif action.type == "add_blacklist_tri" then
        if action.index and action.index <= #State.blacklist_tris then
            table.remove(State.blacklist_tris, action.index)
            Repair.save_blacklist_tris()
            return true
        end
    elseif action.type == "add_blacklist_point" then
        if action.index and action.index <= #State.blacklist_points then
            table.remove(State.blacklist_points, action.index)
            Repair.save_blacklist_points()
            return true
        end
    end

    return false
end

function Repair.has_undo_action()
    return State.last_action ~= nil
end

function Repair.get_last_action_type()
    return State.last_action and State.last_action.type or nil
end

-- =========================
-- Removal Functions
-- =========================

function Repair.remove_bridge(idx)
    if idx and idx > 0 and idx <= #State.bridges then
        table.remove(State.bridges, idx)
        Repair.save_bridges()
    end
end

function Repair.remove_blacklist_tri(idx)
    if idx and idx > 0 and idx <= #State.blacklist_tris then
        table.remove(State.blacklist_tris, idx)
        Repair.save_blacklist_tris()
    end
end

function Repair.remove_blacklist_point(idx)
    if idx and idx > 0 and idx <= #State.blacklist_points then
        table.remove(State.blacklist_points, idx)
        if State.selected_point_idx == idx then
            State.selected_point_idx = nil
        end
        Repair.save_blacklist_points()
    end
end

function Repair.clear_all_bridges()
    State.bridges = {}
    Repair.save_bridges()
end

function Repair.clear_all_blacklist_tris()
    State.blacklist_tris = {}
    Repair.save_blacklist_tris()
end

function Repair.clear_all_blacklist_points()
    State.blacklist_points = {}
    Repair.save_blacklist_points()
end

-- Update point radius
function Repair.set_point_radius(idx, radius)
    if idx and idx > 0 and idx <= #State.blacklist_points then
        State.blacklist_points[idx].radius = radius
        Repair.save_blacklist_points()
    end
end

function Repair.get_selected_point_idx()
    return State.selected_point_idx
end

function Repair.set_selected_point_idx(idx)
    State.selected_point_idx = idx
end

-- =========================
-- Drag Functions (for blacklist points)
-- =========================

function Repair.get_blacklist_point_at(world_pos)
    for i, point in ipairs(State.blacklist_points) do
        local dist = dist2D(world_pos.x, world_pos.y, point.x, point.y)
        if dist < (point.radius or 5) + 2 then
            return point, i
        end
    end
    return nil, nil
end

function Repair.start_drag(point)
    State.dragging = point
    State.drag_active = true
end

function Repair.is_dragging()
    return State.drag_active
end

function Repair.update_drag_position(world_pos)
    if State.dragging then
        State.dragging.x = world_pos.x
        State.dragging.y = world_pos.y
        State.dragging.z = world_pos.z
    end
end

function Repair.end_drag()
    if State.dragging then
        Repair.save_blacklist_points()
    end
    State.dragging = nil
    State.drag_active = false
end

-- =========================
-- Pathfinding Integration
-- =========================

function Repair.is_triangle_blacklisted(tileId, polyIdx, triangleIdx)
    for _, bl in ipairs(State.blacklist_tris) do
        if bl.tileId == tileId and bl.polyIdx == polyIdx and bl.triangleIdx == triangleIdx then
            return true
        end
    end
    return false
end

function Repair.is_polygon_partially_blacklisted(tileId, polyIdx)
    for _, bl in ipairs(State.blacklist_tris) do
        if bl.tileId == tileId and bl.polyIdx == polyIdx then
            return true
        end
    end
    return false
end

function Repair.is_position_blacklisted(x, y, z)
    for _, point in ipairs(State.blacklist_points) do
        local dist = dist2D(x, y, point.x, point.y)
        if dist < point.radius then
            if point.z then
                local z_diff = math.abs(z - point.z)
                if z_diff < 10 then
                    return true
                end
            else
                return true
            end
        end
    end
    return false
end

-- Get bridge neighbors for A* (multi-waypoint)
-- Returns: array of {tileId, polyIdx, x, y, z, entryX, entryY, entryZ, bridgeWaypoints}
function Repair.get_bridge_neighbors(tileId, polyIdx)
    local neighbors = {}

    -- Check both saved and staged bridges for pathfinding
    local all_bridges = {}
    for _, b in ipairs(State.bridges) do
        all_bridges[#all_bridges + 1] = b
    end
    for _, b in ipairs(State.staged_bridges) do
        all_bridges[#all_bridges + 1] = b
    end

    -- Debug: Log check once per unique tile/poly combo
    if not State._debug_logged then State._debug_logged = {} end
    local debugKey = tostring(tileId) .. "_" .. tostring(polyIdx)
    if not State._debug_logged[debugKey] and #all_bridges > 0 then
        State._debug_logged[debugKey] = true
        core.log(string.format("[Bridge] Checking tile=%s poly=%d against %d bridges", tostring(tileId), polyIdx, #all_bridges))
        for i, b in ipairs(all_bridges) do
            local wps = b.waypoints
            if wps and #wps >= 2 then
                core.log(string.format("  Bridge %d: first=(tile=%s,poly=%s) last=(tile=%s,poly=%s)",
                    i, tostring(wps[1].tileId), tostring(wps[1].polyIdx),
                    tostring(wps[#wps].tileId), tostring(wps[#wps].polyIdx)))
            end
        end
    end

    for _, bridge in ipairs(all_bridges) do
        local wps = bridge.waypoints
        if not wps or #wps < 2 then goto continue end

        local first = wps[1]
        local last = wps[#wps]

        -- Check if this polygon matches either end of the bridge
        if first.tileId == tileId and first.polyIdx == polyIdx then
            -- Forward direction
            table.insert(neighbors, {
                tileId = last.tileId,
                polyIdx = last.polyIdx,
                x = last.x,
                y = last.y,
                z = last.z,
                entryX = first.x,
                entryY = first.y,
                entryZ = first.z,
                bridgeWaypoints = wps  -- All waypoints for path building
            })
        elseif last.tileId == tileId and last.polyIdx == polyIdx then
            -- Reverse direction
            local reversed = {}
            for i = #wps, 1, -1 do
                table.insert(reversed, wps[i])
            end
            table.insert(neighbors, {
                tileId = first.tileId,
                polyIdx = first.polyIdx,
                x = first.x,
                y = first.y,
                z = first.z,
                entryX = last.x,
                entryY = last.y,
                entryZ = last.z,
                bridgeWaypoints = reversed
            })
        end

        ::continue::
    end

    return neighbors
end

-- =========================
-- Rendering
-- =========================

local function draw_triangle_vertices(verts, clr)
    if not verts or #verts < 3 then return end
    local p0 = vec3.new(verts[1].x, verts[1].y, verts[1].z)
    local p1 = vec3.new(verts[2].x, verts[2].y, verts[2].z)
    local p2 = vec3.new(verts[3].x, verts[3].y, verts[3].z)
    core.graphics.triangle_3d_filled(p0, p1, p2, clr)
end

local function draw_point_marker(x, y, z, clr, radius)
    local screen = core.graphics.w2s(vec3.new(x, y, z))
    if screen and screen.x > 0 and screen.y > 0 then
        core.graphics.circle_2d_filled(screen, radius or 6, clr)
    end
end

local function draw_line_3d(x1, y1, z1, x2, y2, z2, clr, thickness)
    local p1 = vec3.new(x1, y1, z1)
    local p2 = vec3.new(x2, y2, z2)
    core.graphics.line_3d(p1, p2, clr, thickness or 2)
end

function Repair.render()
    if not CONFIG.enabled then return end

    local mode = CONFIG.mode

    -- 1. Draw hover preview (triangle under cursor)
    if State.hover_triangle and mode then
        draw_triangle_vertices(State.hover_triangle.vertices, COLORS.hover)

        -- Show Z info
        local screen = core.graphics.w2s(vec3.new(
            State.hover_triangle.center.x,
            State.hover_triangle.center.y,
            State.hover_triangle.center.z
        ))
        if screen and screen.x > 0 then
            core.graphics.text_2d(
                string.format("Z: %.1f", State.hover_triangle.avgZ),
                vec2.new(screen.x + 15, screen.y - 8), 11, COLORS.hint_text, false
            )
        end
    end

    -- 2. Draw hint text for bridge mode
    if mode == "bridge" then
        local hint_y = 80
        local wps = State.current_bridge_waypoints

        if #wps == 0 then
            -- Not started yet
            if is_r_held() then
                core.graphics.text_2d("R HELD - Click triangle to set START anchor",
                    vec2.new(10, hint_y), 14, color.new(0, 255, 100, 255), false)
            else
                core.graphics.text_2d("Hold R + Click on triangle to START bridge",
                    vec2.new(10, hint_y), 14, COLORS.hint_text, false)
            end
        else
            -- Recording in progress
            if is_r_held() then
                core.graphics.text_2d("R HELD - Click triangle to set END anchor",
                    vec2.new(10, hint_y), 14, color.new(0, 255, 100, 255), false)
            else
                core.graphics.text_2d("Click = add waypoint | Hold R + Click = END anchor",
                    vec2.new(10, hint_y), 14, COLORS.hint_text, false)
            end
            core.graphics.text_2d(
                string.format("Recording: %d waypoint(s)", #wps),
                vec2.new(10, hint_y + 18), 14, color.new(0, 255, 0, 255), false)
        end
    end

    -- 3. Draw current recording (green lines + markers)
    if #State.current_bridge_waypoints > 0 then
        local wps = State.current_bridge_waypoints

        -- Draw lines between waypoints
        for i = 1, #wps - 1 do
            draw_line_3d(wps[i].x, wps[i].y, wps[i].z,
                        wps[i+1].x, wps[i+1].y, wps[i+1].z,
                        COLORS.recording_line, 3)
        end

        -- Draw markers
        for i, wp in ipairs(wps) do
            local marker_color = wp.isTri and COLORS.recording_dot_tri or COLORS.recording_dot_free
            local marker_size = wp.isTri and 8 or 5
            draw_point_marker(wp.x, wp.y, wp.z, marker_color, marker_size)

            -- Highlight triangle if on one
            if wp.isTri and wp.vertices then
                draw_triangle_vertices(wp.vertices, color.new(0, 255, 100, 80))
            end
        end

        -- Draw line to cursor
        local last = wps[#wps]
        local cursor = core.graphics.get_cursor_world_position()
        if cursor then
            draw_line_3d(last.x, last.y, last.z, cursor.x, cursor.y, cursor.z,
                        color.new(0, 255, 0, 100), 2)
        end
    end

    -- 4. Draw staged bridges (yellow)
    for _, bridge in ipairs(State.staged_bridges) do
        local wps = bridge.waypoints
        if wps and #wps >= 2 then
            for i = 1, #wps - 1 do
                draw_line_3d(wps[i].x, wps[i].y, wps[i].z,
                            wps[i+1].x, wps[i+1].y, wps[i+1].z,
                            COLORS.staged_bridge, 3)
            end
            for _, wp in ipairs(wps) do
                local size = wp.isTri and 6 or 4
                draw_point_marker(wp.x, wp.y, wp.z, COLORS.staged_point, size)
            end
        end
    end

    -- 5. Draw saved bridges (cyan, or magenta if previewed)
    for idx, bridge in ipairs(State.bridges) do
        local wps = bridge.waypoints
        if wps and #wps >= 2 then
            local is_preview = (idx == State.preview_bridge_idx)
            local line_color = is_preview and COLORS.preview_highlight or COLORS.saved_bridge
            local point_color = is_preview and COLORS.preview_highlight or COLORS.saved_point
            local thickness = is_preview and 5 or 3

            for i = 1, #wps - 1 do
                draw_line_3d(wps[i].x, wps[i].y, wps[i].z,
                            wps[i+1].x, wps[i+1].y, wps[i+1].z,
                            line_color, thickness)
            end
            for _, wp in ipairs(wps) do
                local size = is_preview and 10 or (wp.isTri and 5 or 3)
                draw_point_marker(wp.x, wp.y, wp.z, point_color, size)
            end
        end
    end

    -- 6. Draw blacklisted triangles (red, or magenta if previewed)
    for idx, bl in ipairs(State.blacklist_tris) do
        local tri = get_triangle_data(bl.tileId, bl.polyIdx, bl.triangleIdx)
        if tri then
            local is_preview = (idx == State.preview_tri_idx)
            local tri_color = is_preview and COLORS.preview_highlight or COLORS.blacklist_tri
            draw_triangle_vertices(tri.vertices, tri_color)
        end
    end

    -- 7. Draw blacklist points (red circles, or magenta if previewed)
    for i, point in ipairs(State.blacklist_points) do
        local is_preview = (i == State.preview_point_idx)
        local center = vec3.new(point.x, point.y, point.z)
        local screen = core.graphics.w2s(center)
        if screen and screen.x > 0 and screen.y > 0 then
            local segments = 24
            local radius = point.radius
            for s = 0, segments - 1 do
                local a1 = (s / segments) * math.pi * 2
                local a2 = ((s + 1) / segments) * math.pi * 2
                local pt1 = vec3.new(point.x + math.cos(a1) * radius, point.y + math.sin(a1) * radius, point.z)
                local pt2 = vec3.new(point.x + math.cos(a2) * radius, point.y + math.sin(a2) * radius, point.z)
                local lineColor = is_preview and COLORS.preview_highlight or
                                  (i == State.selected_point_idx and COLORS.selected_point or COLORS.blacklist_center)
                local thickness = is_preview and 4 or 2
                core.graphics.line_3d(pt1, pt2, lineColor, thickness)
            end

            local centerColor = is_preview and COLORS.preview_highlight or
                               (i == State.selected_point_idx and COLORS.selected_point or COLORS.blacklist_center)
            local centerSize = is_preview and 8 or 5
            core.graphics.circle_2d_filled(screen, centerSize, centerColor)

            core.graphics.text_2d(string.format("R: %d", point.radius),
                vec2.new(screen.x + 10, screen.y - 10), 12, centerColor, false)
        end
    end
end

-- =========================
-- Persistence (Separate Files)
-- =========================

function Repair.save_bridges()
    local json = "[]"

    if #State.bridges > 0 then
        local parts = {}
        for _, b in ipairs(State.bridges) do
            local wp_parts = {}
            for _, wp in ipairs(b.waypoints or {}) do
                local ti = wp.tileId and tostring(wp.tileId) or "null"
                local pi = wp.polyIdx and tostring(wp.polyIdx) or "null"
                local tri = wp.triIdx and tostring(wp.triIdx) or "null"
                wp_parts[#wp_parts+1] = string.format(
                    '{"tile":%s,"poly":%s,"tri":%s,"x":%.2f,"y":%.2f,"z":%.2f,"isTri":%s}',
                    ti, pi, tri, wp.x, wp.y, wp.z, wp.isTri and "true" or "false"
                )
            end
            parts[#parts+1] = string.format('{"waypoints":[%s]}', table.concat(wp_parts, ","))
        end
        json = "[" .. table.concat(parts, ",") .. "]"
    end

    -- Add version marker so we know this is a fresh save
    local content = "V3:" .. json
    core.create_data_file(BRIDGE_FILE)
    core.write_data_file(BRIDGE_FILE, content)
end

function Repair.load_bridges()
    local content = core.read_data_file(BRIDGE_FILE)
    State.bridges = {}

    if not content or content == "" then
        return
    end

    -- Find the LAST V3 marker (in case write appends)
    local last_v3_pos = nil
    local search_start = 1
    while true do
        local pos = content:find("V3:", search_start, true)
        if pos then
            last_v3_pos = pos
            search_start = pos + 1
        else
            break
        end
    end

    -- Extract content after the last V3 marker
    if last_v3_pos then
        content = content:sub(last_v3_pos + 3)  -- Skip "V3:"
    end

    -- Check for empty
    if content == "[]" then
        return
    end

    -- Parse multi-waypoint bridges
    -- Format: [{"waypoints":[{...},{...}]}, ...]
    for waypoints_json in content:gmatch('"waypoints":%s*(%[[^%]]*%])') do
        local bridge = {waypoints = {}}

        for wp_json in waypoints_json:gmatch('{[^}]+}') do
            local tile = wp_json:match('"tile":(%d+)') or wp_json:match('"tile":(null)')
            local poly = wp_json:match('"poly":(%d+)') or wp_json:match('"poly":(null)')
            local tri = wp_json:match('"tri":(%d+)') or wp_json:match('"tri":(null)')
            local x = wp_json:match('"x":([%d%.%-]+)')
            local y = wp_json:match('"y":([%d%.%-]+)')
            local z = wp_json:match('"z":([%d%.%-]+)')
            local isTri = wp_json:match('"isTri":true')

            if x and y and z then
                table.insert(bridge.waypoints, {
                    tileId = tile ~= "null" and tonumber(tile) or nil,
                    polyIdx = poly ~= "null" and tonumber(poly) or nil,
                    triIdx = tri ~= "null" and tonumber(tri) or nil,
                    x = tonumber(x),
                    y = tonumber(y),
                    z = tonumber(z),
                    isTri = isTri and true or false
                })
            end
        end

        if #bridge.waypoints >= 2 then
            table.insert(State.bridges, bridge)
        end
    end

    -- Fallback: try old format for backwards compatibility (no V3 marker)
    if #State.bridges == 0 and not last_v3_pos then
        for from_tile, from_poly, from_tri, from_x, from_y, from_z, to_tile, to_poly, to_tri, to_x, to_y, to_z in
            content:gmatch('"from":%s*{%s*"tile":(%d+),%s*"poly":(%d+),%s*"tri":(%d+),%s*"x":([%d%.%-]+),%s*"y":([%d%.%-]+),%s*"z":([%d%.%-]+)%s*},%s*"to":%s*{%s*"tile":(%d+),%s*"poly":(%d+),%s*"tri":(%d+),%s*"x":([%d%.%-]+),%s*"y":([%d%.%-]+),%s*"z":([%d%.%-]+)') do

            table.insert(State.bridges, {
                waypoints = {
                    {
                        tileId = tonumber(from_tile),
                        polyIdx = tonumber(from_poly),
                        triIdx = tonumber(from_tri),
                        x = tonumber(from_x),
                        y = tonumber(from_y),
                        z = tonumber(from_z),
                        isTri = true
                    },
                    {
                        tileId = tonumber(to_tile),
                        polyIdx = tonumber(to_poly),
                        triIdx = tonumber(to_tri),
                        x = tonumber(to_x),
                        y = tonumber(to_y),
                        z = tonumber(to_z),
                        isTri = true
                    }
                }
            })
        end
    end
end

function Repair.save_blacklist_tris()
    local json = "[]"

    if #State.blacklist_tris > 0 then
        local parts = {}
        for _, bl in ipairs(State.blacklist_tris) do
            parts[#parts+1] = string.format(
                '{"tile":%d,"poly":%d,"tri":%d}',
                bl.tileId, bl.polyIdx, bl.triangleIdx
            )
        end
        json = "[" .. table.concat(parts, ",") .. "]"
    end

    -- Add version marker so we know this is a fresh save
    local content = "V3:" .. json
    core.create_data_file(BLACKLIST_TRIS_FILE)
    core.write_data_file(BLACKLIST_TRIS_FILE, content)
end

function Repair.load_blacklist_tris()
    local content = core.read_data_file(BLACKLIST_TRIS_FILE)
    State.blacklist_tris = {}

    if not content or content == "" then
        -- Try old combined file for migration
        local old_content = core.read_data_file("mmaps/lx_nav_blacklist.json")
        if old_content and old_content ~= "" then
            for tile, poly, tri in old_content:gmatch('"tile":(%d+),%s*"poly":(%d+),%s*"tri":(%d+)') do
                table.insert(State.blacklist_tris, {
                    tileId = tonumber(tile),
                    polyIdx = tonumber(poly),
                    triangleIdx = tonumber(tri)
                })
            end
            if #State.blacklist_tris > 0 then
                Repair.save_blacklist_tris()  -- Migrate to new file
            end
        end
        return
    end

    -- Find the LAST V3 marker (in case write appends)
    local last_v3_pos = nil
    local search_start = 1
    while true do
        local pos = content:find("V3:", search_start, true)
        if pos then
            last_v3_pos = pos
            search_start = pos + 1
        else
            break
        end
    end

    -- Extract content after the last V3 marker
    if last_v3_pos then
        content = content:sub(last_v3_pos + 3)  -- Skip "V3:"
    end

    -- Check for empty
    if content == "[]" then
        return
    end

    for tile, poly, tri in content:gmatch('"tile":(%d+),%s*"poly":(%d+),%s*"tri":(%d+)') do
        table.insert(State.blacklist_tris, {
            tileId = tonumber(tile),
            polyIdx = tonumber(poly),
            triangleIdx = tonumber(tri)
        })
    end
end

function Repair.save_blacklist_points()
    local json = "[]"

    if #State.blacklist_points > 0 then
        local parts = {}
        for _, pt in ipairs(State.blacklist_points) do
            parts[#parts+1] = string.format(
                '{"x":%.2f,"y":%.2f,"z":%.2f,"radius":%d}',
                pt.x, pt.y, pt.z, pt.radius
            )
        end
        json = "[" .. table.concat(parts, ",") .. "]"
    end

    -- Add version marker so we know this is a fresh save
    local content = "V3:" .. json
    core.create_data_file(BLACKLIST_POINTS_FILE)
    core.write_data_file(BLACKLIST_POINTS_FILE, content)
end

function Repair.load_blacklist_points()
    local content = core.read_data_file(BLACKLIST_POINTS_FILE)
    State.blacklist_points = {}

    if not content or content == "" then
        -- Try old combined file for migration
        local old_content = core.read_data_file("mmaps/lx_nav_blacklist.json")
        if old_content and old_content ~= "" then
            for x, y, z, radius in old_content:gmatch('"x":([%d%.%-]+),%s*"y":([%d%.%-]+),%s*"z":([%d%.%-]+),%s*"radius":(%d+)') do
                table.insert(State.blacklist_points, {
                    x = tonumber(x),
                    y = tonumber(y),
                    z = tonumber(z),
                    radius = tonumber(radius)
                })
            end
            if #State.blacklist_points > 0 then
                Repair.save_blacklist_points()  -- Migrate to new file
            end
        end
        return
    end

    -- Find the LAST V3 marker (in case write appends)
    local last_v3_pos = nil
    local search_start = 1
    while true do
        local pos = content:find("V3:", search_start, true)
        if pos then
            last_v3_pos = pos
            search_start = pos + 1
        else
            break
        end
    end

    -- Extract content after the last V3 marker
    if last_v3_pos then
        content = content:sub(last_v3_pos + 3)  -- Skip "V3:"
    end

    -- Check for empty
    if content == "[]" then
        return
    end

    for x, y, z, radius in content:gmatch('"x":([%d%.%-]+),%s*"y":([%d%.%-]+),%s*"z":([%d%.%-]+),%s*"radius":(%d+)') do
        table.insert(State.blacklist_points, {
            x = tonumber(x),
            y = tonumber(y),
            z = tonumber(z),
            radius = tonumber(radius)
        })
    end
end

function Repair.load_data()
    Repair.load_bridges()
    Repair.load_blacklist_tris()
    Repair.load_blacklist_points()
end

-- =========================
-- Getters for Menu
-- =========================

function Repair.get_bridges()
    return State.bridges
end

function Repair.get_blacklist_tris()
    return State.blacklist_tris
end

function Repair.get_blacklist_points()
    return State.blacklist_points
end

-- Legacy compatibility
function Repair.is_bridge_pending()
    return State.recording_bridge and #State.current_bridge_waypoints > 0
end

function Repair.cancel_pending_bridge()
    State.current_bridge_waypoints = {}
    State.recording_bridge = false
end

-- =========================
-- Preview/Highlight for deletion
-- =========================

function Repair.get_preview_bridge_idx()
    return State.preview_bridge_idx
end

function Repair.set_preview_bridge_idx(idx)
    State.preview_bridge_idx = idx
    -- Clear other previews
    State.preview_tri_idx = nil
    State.preview_point_idx = nil
end

function Repair.get_preview_tri_idx()
    return State.preview_tri_idx
end

function Repair.set_preview_tri_idx(idx)
    State.preview_tri_idx = idx
    -- Clear other previews
    State.preview_bridge_idx = nil
    State.preview_point_idx = nil
end

function Repair.get_preview_point_idx()
    return State.preview_point_idx
end

function Repair.set_preview_point_idx(idx)
    State.preview_point_idx = idx
    -- Clear other previews
    State.preview_bridge_idx = nil
    State.preview_tri_idx = nil
end

function Repair.clear_all_previews()
    State.preview_bridge_idx = nil
    State.preview_tri_idx = nil
    State.preview_point_idx = nil
end

return Repair
