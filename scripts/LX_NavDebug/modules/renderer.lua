local Config = require("modules/config")
local Utils = require("modules/utils")

-- Common modules
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local vec3 = require("common/geometry/vector_3")

local Renderer = {}

-- Debug logging
local function log(msg)
    core.write_log_file("LX_NavDebug.log", "[Renderer] " .. tostring(msg) .. "\n")
end

-- Stats for this frame
Renderer.stats = {
    edges_rendered = 0,
    edges_culled = 0
}

-- Get color for an edge based on type and area
function Renderer.get_edge_color(edge)
    local base_color

    -- Border and portal edges get special colors
    if edge.edgeType == Config.EDGE_BORDER then
        base_color = Config.border_color
    elseif edge.edgeType == Config.EDGE_PORTAL then
        base_color = Config.portal_color
    else
        -- Internal edge - use area type color
        base_color = Config.colors[edge.areaType]
        if not base_color then
            base_color = Config.colors[Config.NAV_AREA_GROUND]
        end

        -- Dim internal edges
        base_color = Utils.dim_color(base_color, Config.internal_dim_factor)
    end

    return Utils.make_color(base_color)
end

-- Render a single tile
function Renderer.render_tile(tile, player_pos, player_facing)
    if not tile or not tile.edges then return end

    local rendered = 0
    local culled = 0

    for _, edge in ipairs(tile.edges) do
        -- Convert Recast coords to WoW coords: (X,Y,Z) -> (Z,X,Y)
        local wow_x1, wow_y1, wow_z1 = edge.z1, edge.x1, edge.y1
        local wow_x2, wow_y2, wow_z2 = edge.z2, edge.x2, edge.y2

        -- Distance culling (using WoW coords)
        local d1 = Utils.distance_2d(wow_x1, wow_y1, player_pos.x, player_pos.y)
        local d2 = Utils.distance_2d(wow_x2, wow_y2, player_pos.x, player_pos.y)
        if d1 > Config.render_distance and d2 > Config.render_distance then
            culled = culled + 1
        else
            -- Cone culling (check edge midpoint in WoW coords)
            local mid_x = (wow_x1 + wow_x2) / 2
            local mid_y = (wow_y1 + wow_y2) / 2
            if not Utils.is_in_front_cone(mid_x, mid_y, player_pos, player_facing, Config.cone_angle) then
                culled = culled + 1
            else
                -- Render the edge
                local start_pos = vec3.new(wow_x1, wow_y1, wow_z1)
                local end_pos = vec3.new(wow_x2, wow_y2, wow_z2)

                -- Get color based on edge type
                local edge_color
                if edge.edgeType == Config.EDGE_BORDER then
                    edge_color = color.white(255)
                elseif edge.edgeType == Config.EDGE_PORTAL then
                    edge_color = color.yellow(255)
                else
                    -- Internal edge - green for ground
                    edge_color = color.green(180)
                end

                core.graphics.line_3d(start_pos, end_pos, edge_color, Config.edge_thickness)

                rendered = rendered + 1
            end
        end
    end

    Renderer.stats.edges_rendered = Renderer.stats.edges_rendered + rendered
    Renderer.stats.edges_culled = Renderer.stats.edges_culled + culled
end

-- Render all loaded tiles
local render_log_count = 0
function Renderer.render_tiles(tiles, player_pos, player_facing)
    -- Reset stats
    Renderer.stats.edges_rendered = 0
    Renderer.stats.edges_culled = 0

    render_log_count = render_log_count + 1
    if render_log_count == 1 or render_log_count % 300 == 0 then
        log(string.format("render_tiles called: tiles=%d pos=(%.1f,%.1f,%.1f) facing=%.2f",
            #tiles, player_pos.x, player_pos.y, player_pos.z, player_facing))
        if #tiles > 0 and tiles[1].edges then
            log(string.format("First tile has %d edges", #tiles[1].edges))
            if #tiles[1].edges > 0 then
                local e = tiles[1].edges[1]
                -- Show both raw and converted coords
            log(string.format("First edge RAW: (%.1f,%.1f,%.1f) type=%d area=%d",
                    e.x1, e.y1, e.z1, e.edgeType, e.areaType))
            log(string.format("First edge WOW: (%.1f,%.1f,%.1f) (z,x,y conversion)",
                    e.z1, e.x1, e.y1))
            end
        end
    end

    for _, tile in ipairs(tiles) do
        Renderer.render_tile(tile, player_pos, player_facing)
    end

    if render_log_count == 1 or render_log_count % 300 == 0 then
        log(string.format("After render: rendered=%d culled=%d",
            Renderer.stats.edges_rendered, Renderer.stats.edges_culled))
    end
end

-- Render debug info overlay
function Renderer.render_debug_overlay(tiles)
    local screen_size = core.graphics.get_screen_size()

    local x = 10
    local y = screen_size.y - 150

    local text_color = color.new(255, 255, 255, 255)
    local bg_color = color.new(0, 0, 0, 150)

    -- Background panel
    local panel_width = 200
    local panel_height = 100
    core.graphics.rect_2d_filled(vec2.new(x - 5, y - 5), panel_width, panel_height, bg_color, 4)

    -- Title
    core.graphics.text_2d("LX_NavDebug", vec2.new(x, y), 14, text_color, false)
    y = y + 18

    -- Stats
    local tiles_loaded = #tiles
    local cache_tiles, cache_edges = 0, 0

    -- Try to get cache stats from loader
    local Loader = require("modules/loader")
    if Loader and Loader.get_cache_stats then
        cache_tiles, cache_edges = Loader.get_cache_stats()
    end

    core.graphics.text_2d(
        string.format("Tiles: %d (cached: %d)", tiles_loaded, cache_tiles),
        vec2.new(x, y), 12, text_color, false
    )
    y = y + 16

    core.graphics.text_2d(
        string.format("Edges rendered: %d", Renderer.stats.edges_rendered),
        vec2.new(x, y), 12, text_color, false
    )
    y = y + 16

    core.graphics.text_2d(
        string.format("Edges culled: %d", Renderer.stats.edges_culled),
        vec2.new(x, y), 12, text_color, false
    )
    y = y + 16

    core.graphics.text_2d(
        string.format("Render dist: %d yds", Config.render_distance),
        vec2.new(x, y), 12, text_color, false
    )
end

return Renderer
