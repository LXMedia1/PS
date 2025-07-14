-- Lx Common API Plugin Header
local plugin = {}

plugin["name"] = "lx_common"
plugin["author"] = "Lexxes"
plugin["version"] = "1.0"
plugin["description"] = "Common API library with utility functions used across all projects"

plugin["load"] = true

-- Basic validation to ensure we can load
if core and core.object_manager then
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        plugin["load"] = false
        return plugin
    end
end

return plugin