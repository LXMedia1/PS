-- LX Debug Plugin Header
local plugin = {}

plugin["name"] = "lx_debug"
plugin["author"] = "Lexxes"
plugin["version"] = "1.0"
plugin["description"] = "Debug and testing environment for new functions and features"

plugin["load"] = true
plugin["dependencies"] = {"lx_common"}

-- Basic validation to ensure we can load
if core and core.object_manager then
    local local_player = core.object_manager.get_local_player()
    if not local_player then
        plugin["load"] = false
        return plugin
    end
end

return plugin 