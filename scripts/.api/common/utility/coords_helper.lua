
-- Syntax / IntelliSense helper for: common/utility/coords_helper
-- Usage:
-- ---@type coords_helper
-- local coords = require("common/utility/coords_helper")
-- coords: -- IntelliSense
-- Warning: Access with ":", not "."

--- Coords Helper
--- Converts 2D UI map coordinates (vec2) to 3D world positions (vec3).
--- If height_override is nil, uses the local player's Z + 25, then snaps to ground via core.get_height_for_position.
---@class coords_helper
---@field public to_3d fun(self: coords_helper, map_pos: vec2, height_override?: number): vec3

-- Notes:
-- • Bad inputs are handled inside the library (logs via core.log_error and returns fallback vec3).
-- • When the local player is not available and no height_override is provided, the lib falls back to Z=50 before snapping.
-- • The final returned vec3 is grounded using core.get_height_for_position.

--========================
-- Examples
--========================

-- Example: Convert map ping to world position (auto height)
-- ---@type coords_helper
-- local coords = require("common/utility/coords_helper")
-- local map_ping = { x = 0.62, y = 0.41 }  -- normalized map coords or UI coords per your engine
-- local world_pos = coords:to_3d(map_ping)
-- core.log("World pos -> x=" .. tostring(world_pos.x) .. " y=" .. tostring(world_pos.y) .. " z=" .. tostring(world_pos.z))

-- Example: Convert with explicit height (useful for flying mounts or aerial waypoints)
-- local desired_z = 120.0
-- local wp = coords:to_3d({ x = 0.35, y = 0.72 }, desired_z)
-- core.log("Waypoint -> x=" .. tostring(wp.x) .. " y=" .. tostring(wp.y) .. " z=" .. tostring(wp.z))

-- Tips:
-- • If your plugin is disabled, skip conversions to avoid noise:
--   if not menu.main_boolean:get_state() then return end
-- • Provide height_override when you know the desired altitude (e.g., patrol paths, glide routes).
-- • Always pass a well-formed vec2 (has .x and .y). The helper logs and returns a safe default if not.

---@type coords_helper
local tbl
return tbl
