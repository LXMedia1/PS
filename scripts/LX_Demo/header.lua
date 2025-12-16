local plugin = {}

plugin["name"] = "LX_Demo"
plugin["version"] = "1.0.0"
plugin["author"] = "Lexxer"
plugin["description"] = "Demo showcasing all LX_UI components"
plugin["load"] = false
plugin["is_library"] = false
plugin["is_required_dependency"] = false
plugin["dependencies"] = {"LX_UI"}

local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

return plugin
