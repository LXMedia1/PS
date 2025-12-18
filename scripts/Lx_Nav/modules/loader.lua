--[[
    Lx_Nav PSNG Loader
    Author: Lexxer

    Loads and parses .psng navigation graph files.
]]

local Config = require("modules/config")
local Utils = require("modules/utils")

local Loader = {}

-- Loaded graph data
local loaded_graph = nil
local loaded_map_id = nil

-- Parse PSNG header (64 bytes)
local function parse_header(data)
    local header = {}

    local magic = Utils.read_uint32(data, 0)
    if magic ~= Config.PSNG_MAGIC then
        Utils.log_error("Invalid PSNG magic: " .. string.format("0x%08X", magic))
        return nil
    end

    header.version = Utils.read_uint16(data, 4)
    header.mapId = Utils.read_uint16(data, 6)
    header.nodeCount = Utils.read_uint32(data, 8)
    header.edgeCount = Utils.read_uint32(data, 12)
    header.offMeshCount = Utils.read_uint32(data, 16)
    header.mapExitCount = Utils.read_uint16(data, 20)
    header.tileCount = Utils.read_uint16(data, 22)
    header.minX = Utils.read_int32(data, 24) / Config.XY_SCALE
    header.minY = Utils.read_int32(data, 28) / Config.XY_SCALE
    header.maxX = Utils.read_int32(data, 32) / Config.XY_SCALE
    header.maxY = Utils.read_int32(data, 36) / Config.XY_SCALE
    header.gridCellsX = Utils.read_uint16(data, 40)
    header.gridCellsY = Utils.read_uint16(data, 42)
    header.cellSize = Utils.read_uint16(data, 44)

    return header
end

-- Parse spatial grid
local function parse_spatial_grid(data, offset, header)
    local grid = {}
    local cellCount = header.gridCellsX * header.gridCellsY

    for i = 0, cellCount - 1 do
        local cellOffset = offset + i * 4
        local packed = Utils.read_uint32(data, cellOffset)
        -- nodeIndex:uint24, nodeCount:uint8
        local nodeIndex = packed % 0x1000000  -- Lower 24 bits
        local nodeCount = math.floor(packed / 0x1000000)  -- Upper 8 bits
        grid[i] = {nodeIndex = nodeIndex, nodeCount = nodeCount}
    end

    return grid
end

-- Parse nodes
local function parse_nodes(data, offset, count)
    local nodes = {}

    for i = 0, count - 1 do
        local nodeOffset = offset + i * Config.NODE_SIZE
        local node = {
            x = Utils.read_int32(data, nodeOffset) / Config.XY_SCALE,
            y = Utils.read_int32(data, nodeOffset + 4) / Config.XY_SCALE,
            z = Utils.read_int16(data, nodeOffset + 8) / Config.Z_SCALE,
            edgeStart = Utils.read_uint32(data, nodeOffset + 10),
            edgeCount = Utils.read_uint8(data, nodeOffset + 14),
            areaType = Utils.read_uint8(data, nodeOffset + 15),
        }
        nodes[i] = node
    end

    return nodes
end

-- Parse edges
local function parse_edges(data, offset, count)
    local edges = {}

    for i = 0, count - 1 do
        local edgeOffset = offset + i * Config.EDGE_SIZE
        local edge = {
            targetNode = Utils.read_uint32(data, edgeOffset),
            cost = Utils.read_uint16(data, edgeOffset + 4) / Config.COST_SCALE,
            leftX = Utils.read_int16(data, edgeOffset + 6) / Config.PORTAL_SCALE,
            leftY = Utils.read_int16(data, edgeOffset + 8) / Config.PORTAL_SCALE,
            leftZ = Utils.read_int16(data, edgeOffset + 10) / Config.PORTAL_SCALE,
            rightX = Utils.read_int16(data, edgeOffset + 12) / Config.PORTAL_SCALE,
            rightY = Utils.read_int16(data, edgeOffset + 14) / Config.PORTAL_SCALE,
            rightZ = Utils.read_int16(data, edgeOffset + 16) / Config.PORTAL_SCALE,
            flags = Utils.read_uint16(data, edgeOffset + 18),
        }
        edges[i] = edge
    end

    return edges
end

-- Parse off-mesh connections
local function parse_offmesh(data, offset, count)
    local offmesh = {}

    for i = 0, count - 1 do
        local omOffset = offset + i * Config.OFFMESH_SIZE
        local om = {
            startX = Utils.read_int32(data, omOffset) / Config.XY_SCALE,
            startY = Utils.read_int32(data, omOffset + 4) / Config.XY_SCALE,
            startZ = Utils.read_int16(data, omOffset + 8) / Config.Z_SCALE,
            endX = Utils.read_int32(data, omOffset + 10) / Config.XY_SCALE,
            endY = Utils.read_int32(data, omOffset + 14) / Config.XY_SCALE,
            endZ = Utils.read_int16(data, omOffset + 18) / Config.Z_SCALE,
            radius = Utils.read_uint16(data, omOffset + 20) / Config.PORTAL_SCALE,
            cost = Utils.read_uint16(data, omOffset + 22) / Config.COST_SCALE,
            flags = Utils.read_uint8(data, omOffset + 24),
            areaType = Utils.read_uint8(data, omOffset + 25),
            startNode = Utils.read_uint16(data, omOffset + 26),
        }
        offmesh[i] = om
    end

    return offmesh
end

-- Parse map exits
local function parse_map_exits(data, offset, count)
    local exits = {}

    for i = 0, count - 1 do
        local exitOffset = offset + i * Config.MAP_EXIT_SIZE
        local exit = {
            sourceX = Utils.read_int32(data, exitOffset) / Config.XY_SCALE,
            sourceY = Utils.read_int32(data, exitOffset + 4) / Config.XY_SCALE,
            sourceZ = Utils.read_int16(data, exitOffset + 8) / Config.Z_SCALE,
            destMapId = Utils.read_uint16(data, exitOffset + 10),
            destX = Utils.read_int32(data, exitOffset + 12) / Config.XY_SCALE,
            destY = Utils.read_int32(data, exitOffset + 16) / Config.XY_SCALE,
            destZ = Utils.read_int16(data, exitOffset + 20) / Config.Z_SCALE,
            travelTime = Utils.read_uint16(data, exitOffset + 22),
            sourceNode = Utils.read_uint16(data, exitOffset + 24),
            exitType = Utils.read_uint8(data, exitOffset + 26),
            faction = Utils.read_uint8(data, exitOffset + 27),
            waitTime = Utils.read_uint32(data, exitOffset + 28),
        }
        exits[i] = exit
    end

    return exits
end

-- Load a PSNG file for a map
function Loader.load_map(mapId)
    -- Return cached if already loaded
    if loaded_map_id == mapId and loaded_graph then
        return loaded_graph
    end

    local path = Utils.get_psng_path(mapId)
    Utils.file_log("Loading PSNG: " .. path)

    -- Read file
    local data = core.read_data_file(path)
    if not data or #data == 0 then
        Utils.log_error("Failed to read PSNG file: " .. path)
        return nil
    end

    Utils.file_log("File size: " .. #data .. " bytes")

    -- Parse header
    local header = parse_header(data)
    if not header then
        return nil
    end

    Utils.file_log(string.format("Header: version=%d, nodes=%d, edges=%d, tileCount=%d",
        header.version, header.nodeCount, header.edgeCount, header.tileCount))

    -- Calculate offsets
    local tileIndexOffset = Config.HEADER_SIZE
    local gridOffset = tileIndexOffset + Config.TILE_INDEX_SIZE
    local gridSize = header.gridCellsX * header.gridCellsY * 4
    local nodesOffset = gridOffset + gridSize
    local edgesOffset = nodesOffset + header.nodeCount * Config.NODE_SIZE
    local offmeshOffset = edgesOffset + header.edgeCount * Config.EDGE_SIZE
    local mapExitsOffset = offmeshOffset + header.offMeshCount * Config.OFFMESH_SIZE

    -- Parse data
    local grid = parse_spatial_grid(data, gridOffset, header)
    local nodes = parse_nodes(data, nodesOffset, header.nodeCount)
    local edges = parse_edges(data, edgesOffset, header.edgeCount)
    local offmesh = parse_offmesh(data, offmeshOffset, header.offMeshCount)
    local mapExits = parse_map_exits(data, mapExitsOffset, header.mapExitCount)

    -- Build graph structure
    local graph = {
        header = header,
        grid = grid,
        nodes = nodes,
        edges = edges,
        offmesh = offmesh,
        mapExits = mapExits,
    }

    -- Cache
    loaded_graph = graph
    loaded_map_id = mapId

    Utils.file_log("PSNG loaded successfully")
    return graph
end

-- Find nearest node to a position using spatial grid (O(1))
function Loader.find_nearest_node(graph, x, y)
    if not graph then return nil end

    local header = graph.header
    local grid = graph.grid
    local nodes = graph.nodes

    -- Calculate grid cell
    local cellX = math.floor((x - header.minX) / header.cellSize)
    local cellY = math.floor((y - header.minY) / header.cellSize)

    -- Clamp to grid bounds
    cellX = math.max(0, math.min(cellX, header.gridCellsX - 1))
    cellY = math.max(0, math.min(cellY, header.gridCellsY - 1))

    local cellIdx = cellY * header.gridCellsX + cellX
    local cell = grid[cellIdx]

    if not cell or cell.nodeCount == 0 then
        -- No nodes in this cell, search nearby cells
        return Loader.find_nearest_node_bruteforce(graph, x, y)
    end

    -- Find closest node in cell
    local bestNode = nil
    local bestDist = math.huge

    for i = 0, cell.nodeCount - 1 do
        local nodeIdx = cell.nodeIndex + i
        local node = nodes[nodeIdx]
        if node then
            local dist = Utils.distance_2d(x, y, node.x, node.y)
            if dist < bestDist then
                bestDist = dist
                bestNode = nodeIdx
            end
        end
    end

    return bestNode, bestDist
end

-- Brute force nearest node search (fallback)
function Loader.find_nearest_node_bruteforce(graph, x, y)
    if not graph then return nil end

    local nodes = graph.nodes
    local bestNode = nil
    local bestDist = math.huge

    for i = 0, graph.header.nodeCount - 1 do
        local node = nodes[i]
        if node then
            local dist = Utils.distance_2d(x, y, node.x, node.y)
            if dist < bestDist then
                bestDist = dist
                bestNode = i
            end
        end
    end

    return bestNode, bestDist
end

-- Get edges for a node
function Loader.get_node_edges(graph, nodeIdx)
    if not graph then return {} end

    local node = graph.nodes[nodeIdx]
    if not node then return {} end

    local result = {}
    for i = 0, node.edgeCount - 1 do
        local edgeIdx = node.edgeStart + i
        local edge = graph.edges[edgeIdx]
        if edge then
            result[#result + 1] = {
                index = edgeIdx,
                edge = edge
            }
        end
    end

    return result
end

-- Get node position
function Loader.get_node_pos(graph, nodeIdx)
    if not graph then return nil end
    local node = graph.nodes[nodeIdx]
    if not node then return nil end
    return node.x, node.y, node.z
end

-- Check if graph is loaded
function Loader.is_loaded()
    return loaded_graph ~= nil
end

-- Get current loaded map ID
function Loader.get_loaded_map_id()
    return loaded_map_id
end

-- Unload current graph
function Loader.unload()
    loaded_graph = nil
    loaded_map_id = nil
end

return Loader
