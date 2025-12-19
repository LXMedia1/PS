-- Navigation World Manager
-- Manages SoA tiles, provides tile lookup, integrates with TileManager

local TileConverter = require("modules/tile_converter")
local LinkResolver = require("modules/link_resolver")

local NavWorld = {}
NavWorld.__index = NavWorld

-- Tile coordinate calculation constants
local TILE_SIZE = 533.33333
local HALF_WORLD = 32 * TILE_SIZE  -- = 17066.67

-- Convert world position to tile coordinates
local function world_to_tile(x, y)
    local tx = math.floor((HALF_WORLD - x) / TILE_SIZE)
    local ty = math.floor((HALF_WORLD - y) / TILE_SIZE)
    -- Clamp to valid range
    tx = math.max(0, math.min(63, tx))
    ty = math.max(0, math.min(63, ty))
    return tx, ty
end

function NavWorld.new()
    local self = setmetatable({}, NavWorld)

    -- SoA tiles indexed by tileId
    self.tilesById = {}

    -- Map from raw tiles (from TileManager) to SoA tiles
    -- rawKey (e.g. "1_29_40") -> tileId
    self.rawToSoa = {}

    -- Pending tiles to convert
    self.pendingConvert = {}

    -- Current map ID
    self.mapId = 0

    return self
end

-- Set current map ID
function NavWorld:set_map_id(mapId)
    if self.mapId ~= mapId then
        -- Clear tiles when map changes
        self.tilesById = {}
        self.rawToSoa = {}
        self.pendingConvert = {}
        self.mapId = mapId
    end
end

-- Get tile ID at world position
-- Returns: tileId or nil if not loaded
function NavWorld:get_tile_at(x, y)
    local tx, ty = world_to_tile(x, y)
    local tileId = TileConverter.tile_id(self.mapId, tx, ty)

    if self.tilesById[tileId] then
        return tileId
    end

    return nil
end

-- Get tile coordinates from world position
function NavWorld:get_tile_coords(x, y)
    return world_to_tile(x, y)
end

-- Add a raw tile from TileManager (converts to SoA)
-- rawKey: string like "1_29_40"
-- rawTile: tile from tile_parser
function NavWorld:add_raw_tile(rawKey, rawTile)
    -- Skip if already converted
    if self.rawToSoa[rawKey] then
        return self.rawToSoa[rawKey]
    end

    -- Extract map/tile coords from key
    local mapId, tx, ty = rawKey:match("(%d+)_(%d+)_(%d+)")
    mapId = tonumber(mapId)
    tx = tonumber(tx)
    ty = tonumber(ty)

    if not mapId or not tx or not ty then
        return nil
    end

    -- Convert to SoA format
    local soa = TileConverter.convert(rawTile, mapId)

    -- Store
    local tileId = soa.tileId
    self.tilesById[tileId] = soa
    self.rawToSoa[rawKey] = tileId

    -- Mark for edge resolution
    self.pendingConvert[tileId] = true

    return tileId
end

-- Sync with TileManager (call each frame)
-- Returns: number of new tiles added
function NavWorld:sync_with_tile_manager(tileManager, mapId)
    if not tileManager then return 0 end

    self:set_map_id(mapId)

    local added = 0
    local allRaw = tileManager:get_all_tiles(mapId)

    for key, rawTile in pairs(allRaw) do
        if rawTile and not self.rawToSoa[key] then
            local tileId = self:add_raw_tile(key, rawTile)
            if tileId then
                added = added + 1
            end
        end
    end

    -- Resolve cross-tile edges for pending tiles
    if added > 0 then
        self:resolve_pending_edges()
    end

    return added
end

-- Resolve cross-tile links for all tiles (when new tiles added)
function NavWorld:resolve_pending_edges()
    local Debug = require("modules/debug")
    local pendingCount = 0
    for _ in pairs(self.pendingConvert) do
        pendingCount = pendingCount + 1
    end

    if pendingCount == 0 then return 0 end

    Debug.log(string.format("[LinkResolve] Processing %d pending tiles, %d total tiles",
        pendingCount, self:get_tile_count()))

    -- Create neighbor lookup function
    local function get_neighbor(mapId, tileX, tileY)
        local tileId = TileConverter.tile_id(mapId, tileX, tileY)
        return self.tilesById[tileId]
    end

    -- Resolve ALL tiles (not just pending) since new tiles may connect to existing ones
    local totalResolved = 0
    local totalFailed = 0
    local totalNoNeighbor = 0

    for tileId, soa in pairs(self.tilesById) do
        if soa then
            local resolved, failed, noNeighbor = LinkResolver.resolve_tile(soa, get_neighbor)
            totalResolved = totalResolved + resolved
            totalFailed = totalFailed + failed
            totalNoNeighbor = totalNoNeighbor + noNeighbor
        end
    end

    Debug.log(string.format("[LinkResolve] Total: %d resolved, %d failed, %d no neighbor",
        totalResolved, totalFailed, totalNoNeighbor))

    -- Clear pending
    self.pendingConvert = {}

    return totalResolved
end

-- Get all loaded tiles
function NavWorld:get_all_tiles()
    return self.tilesById
end

-- Get count of loaded tiles
function NavWorld:get_tile_count()
    local count = 0
    for _ in pairs(self.tilesById) do
        count = count + 1
    end
    return count
end

-- Get stats
function NavWorld:get_stats()
    local totalPolys = 0
    local totalVerts = 0
    local totalResolved = 0
    local totalLinks = 0

    for _, soa in pairs(self.tilesById) do
        totalPolys = totalPolys + soa.polyCount
        totalVerts = totalVerts + soa.vertCount
        totalResolved = totalResolved + TileConverter.count_resolved_edges(soa)
        totalLinks = totalLinks + (soa.linkCount or 0)
    end

    return {
        tiles = self:get_tile_count(),
        polys = totalPolys,
        verts = totalVerts,
        resolvedEdges = totalResolved,
        totalLinks = totalLinks,
    }
end

-- Clear all tiles
function NavWorld:clear()
    self.tilesById = {}
    self.rawToSoa = {}
    self.pendingConvert = {}
end

-- Get all tiles at a specific tile position (handles multi-layer)
-- Used by edge resolver to find neighbor tiles
-- @param mapId Map ID
-- @param x Tile X coordinate
-- @param y Tile Y coordinate
-- @return array of SoA tiles at that position
function NavWorld:get_tiles_at(mapId, x, y)
    local result = {}
    for tileId, soa in pairs(self.tilesById) do
        if soa and soa.mapId == mapId and soa.tileX == x and soa.tileY == y then
            result[#result + 1] = soa
        end
    end
    return result
end

-- Get height at a position within a specific polygon (for edge resolution)
-- Uses polygon center Z as simple fallback (could enhance with detail mesh sampling)
-- @param soa SoA tile
-- @param poly Polygon index (1-based)
-- @param x World X coordinate
-- @param y World Y coordinate
-- @return Height value or nil
function NavWorld:get_height_at(soa, poly, x, y)
    if not soa or not poly or poly < 1 or poly > soa.polyCount then
        return nil
    end
    -- Return polygon center Z as simple height approximation
    -- For more accurate results, would sample detail mesh triangles
    return soa.pCz[poly]
end

return NavWorld
