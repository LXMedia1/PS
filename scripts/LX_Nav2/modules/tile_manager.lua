-- LX_Nav2 Tile Manager Module
-- Coroutine-based tile loading scheduler with frame budget control
-- Loads tiles incrementally without freezing the game

local Budget = require("modules/budget")
local TileParser = require("modules/tile_parser")
local Debug = require("modules/debug")

local TileManager = {}
TileManager.__index = TileManager

-- Tile size constants
local TILE_SIZE = 533.33333
local HALF_WORLD = 32 * TILE_SIZE  -- = 17066.66656

--- Create a new TileManager instance
-- @param opts Options table with:
--   frame_budget_ms: Max milliseconds per frame for loading (default 3.0)
--   check_every: How often to check budget in loops (default 128)
--   max_cached: Maximum tiles to cache (default 25)
-- @return TileManager instance
function TileManager.new(opts)
    opts = opts or {}
    local self = setmetatable({
        -- Tile cache: key -> tile data | false (failed)
        cached = {},
        -- In-flight tasks: key -> task
        in_flight = {},
        -- Queue of pending tasks
        queue = {},
        -- Configuration
        frame_budget_ms = opts.frame_budget_ms or 3.0,
        check_every = opts.check_every or 128,
        max_cached = opts.max_cached or 25,
        -- Budget object for time tracking
        budget = Budget.new(opts.check_every or 128),
        -- Stats
        tiles_loaded = 0,
        tiles_failed = 0,
        current_stage = nil,
        current_progress = 0,
        current_total = 0,
        -- Callbacks
        on_tile_loaded = nil,  -- function(tile_key, tile) called when tile finishes loading
    }, TileManager)

    return self
end

--- Generate cache key for a tile
local function get_tile_key(map_id, x, y)
    return string.format("%d_%d_%d", map_id, x, y)
end

--- Get filename for a tile
local function get_tile_filename(map_id, tile_x, tile_y)
    return string.format("mmaps/%04d_%02d_%02d.mmtile", map_id, tile_x, tile_y)
end

--- Convert world position to tile coordinates
-- @param x WoW X coordinate
-- @param y WoW Y coordinate
-- @return tile_x, tile_y
function TileManager.world_to_tile(x, y)
    local tile_x = math.floor((HALF_WORLD - x) / TILE_SIZE)
    local tile_y = math.floor((HALF_WORLD - y) / TILE_SIZE)
    -- Clamp to valid range (0-63)
    tile_x = math.max(0, math.min(63, tile_x))
    tile_y = math.max(0, math.min(63, tile_y))
    return tile_x, tile_y
end

--- Queue a tile for loading
-- @param map_id Map ID
-- @param x Tile X coordinate
-- @param y Tile Y coordinate
-- @param priority Priority (lower = higher priority, 0 = center tile)
function TileManager:queue_tile(map_id, x, y, priority)
    local key = get_tile_key(map_id, x, y)

    -- Skip if already cached or loading
    if self.cached[key] ~= nil then
        return
    end
    if self.in_flight[key] then
        return
    end

    -- Create task
    local task = {
        key = key,
        map_id = map_id,
        x = x,
        y = y,
        priority = priority or 0,
        co = nil,
        started = false,
    }

    -- Create coroutine for this tile
    local self_ref = self
    task.co = coroutine.create(function(budget)
        local filename = get_tile_filename(map_id, x, y)
        local data = core.read_data_file(filename)

        if not data or #data == 0 then
            return false, "File not found or empty: " .. filename
        end

        -- Yield after file read
        coroutine.yield("file_read", key, #data)

        -- Parse incrementally (yields when budget exhausted)
        local tile, err = TileParser.parse_incremental(data, budget)

        -- Allow GC to reclaim the string
        data = nil

        if not tile then
            return false, err or "Parse failed"
        end

        -- Store file coordinates
        tile.fileTileX = x
        tile.fileTileY = y
        tile.mapId = map_id

        return tile, nil
    end)

    -- Add to tracking
    self.in_flight[key] = task
    table.insert(self.queue, task)
end

--- Queue tiles around a world position (3x3 grid)
function TileManager:queue_nearby(map_id, world_x, world_y)
    local center_x, center_y = self.world_to_tile(world_x, world_y)

    for dx = -1, 1 do
        for dy = -1, 1 do
            local tx, ty = center_x + dx, center_y + dy
            local prio = math.abs(dx) + math.abs(dy)
            self:queue_tile(map_id, tx, ty, prio)
        end
    end
end

--- Get a cached tile
function TileManager:get_tile(map_id, x, y)
    local key = get_tile_key(map_id, x, y)
    return self.cached[key]
end

--- Check if a tile is loaded
function TileManager:is_loaded(map_id, x, y)
    local key = get_tile_key(map_id, x, y)
    return self.cached[key] ~= nil
end

--- Check if a tile is currently loading
function TileManager:is_loading(map_id, x, y)
    local key = get_tile_key(map_id, x, y)
    return self.in_flight[key] ~= nil
end

--- Get all cached tiles for a map
function TileManager:get_all_tiles(map_id)
    local tiles = {}
    for key, tile in pairs(self.cached) do
        if tile and tile.mapId == map_id then
            tiles[key] = tile
        end
    end
    return tiles
end

--- Pick the highest priority task from the queue
local function pick_best_task(queue)
    if #queue == 0 then
        return nil, nil
    end

    local best_i = 1
    local best_prio = queue[1].priority

    for i = 2, #queue do
        if queue[i].priority < best_prio then
            best_i = i
            best_prio = queue[i].priority
        end
    end

    return table.remove(queue, best_i), best_i
end

--- Evict oldest tiles if cache is too large
function TileManager:evict_old_tiles()
    local count = 0
    local oldest_key = nil
    for key, tile in pairs(self.cached) do
        if tile then
            count = count + 1
            if count > self.max_cached then
                oldest_key = key
            end
        end
    end

    if oldest_key then
        self.cached[oldest_key] = nil
    end
end

--- Process tile loading for this frame
function TileManager:process_frame(frame_budget_ms)
    self.budget:set_deadline_from_ms(frame_budget_ms or self.frame_budget_ms)

    local new_starts_this_frame = 0
    local MAX_NEW_STARTS_PER_FRAME = 1

    while self.budget:time_left() and #self.queue > 0 do
        local task = pick_best_task(self.queue)
        if not task then
            break
        end

        if not task.started then
            if new_starts_this_frame >= MAX_NEW_STARTS_PER_FRAME then
                table.insert(self.queue, task)
                break
            end
            new_starts_this_frame = new_starts_this_frame + 1
            task.started = true
        end

        local ok, result, extra = coroutine.resume(task.co, self.budget)

        if not ok then
            Debug.log(string.format("[TileManager] Coroutine error for %s: %s",
                task.key, tostring(result)))
            self.cached[task.key] = false
            self.in_flight[task.key] = nil
            self.tiles_failed = self.tiles_failed + 1
        elseif coroutine.status(task.co) == "dead" then
            if result == false or result == nil then
                Debug.log(string.format("[TileManager] Tile load failed: %s - %s",
                    task.key, tostring(extra)))
                self.cached[task.key] = false
                self.tiles_failed = self.tiles_failed + 1
            else
                result.mapId = task.map_id
                result.tileX = task.x
                result.tileY = task.y
                Debug.log(string.format("[TileManager] Tile loaded: %s (%d polys)",
                    task.key, #result.polygons))
                self.cached[task.key] = result
                self.tiles_loaded = self.tiles_loaded + 1
                self:evict_old_tiles()
                
                -- Call callback if set
                if self.on_tile_loaded then
                    self.on_tile_loaded(task.key, result)
                end
            end
            self.in_flight[task.key] = nil
        else
            if result == "budget" then
                self.current_stage = extra
            end
            table.insert(self.queue, task)
        end
    end
end

--- Get loading statistics
function TileManager:get_stats()
    return {
        cached = self:count_cached(),
        queued = #self.queue,
        in_flight = self:count_in_flight(),
        loaded_total = self.tiles_loaded,
        failed_total = self.tiles_failed,
        current_stage = self.current_stage,
    }
end

--- Count cached tiles
function TileManager:count_cached()
    local count = 0
    for _, tile in pairs(self.cached) do
        if tile then
            count = count + 1
        end
    end
    return count
end

--- Count in-flight tasks
function TileManager:count_in_flight()
    local count = 0
    for _ in pairs(self.in_flight) do
        count = count + 1
    end
    return count
end

--- Clear cache and queue
function TileManager:clear()
    self.cached = {}
    self.in_flight = {}
    self.queue = {}
    self.tiles_loaded = 0
    self.tiles_failed = 0
end

--- Set callback for tile loaded events
function TileManager:set_on_tile_loaded(callback)
    self.on_tile_loaded = callback
end

return TileManager