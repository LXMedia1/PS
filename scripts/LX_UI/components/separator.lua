local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local constants = require("utils/constants")

local Separator = {}
setmetatable(Separator, { __index = BaseComponent })
Separator.__index = Separator

function Separator:new(options)
    options = options or {}
    options.height = options.height or 10

    local base = BaseComponent:new(constants.COMPONENT_TYPE.SEPARATOR, options)

    local separator = setmetatable({
        type = base.type,
        id = base.id,
        x = base.x,
        y = base.y,
        width = base.width,
        height = base.height,
        visible = base.visible,
        enabled = true,
        parent_menu = base.parent_menu,
        auto_save = false
    }, Separator)

    return separator
end

function Separator:render()
    if not self.visible then return end
    Rendering.separator(self.x, self.y + self.height / 2, self.width)
end

function Separator:update()
end

function Separator:get_value()
    return nil
end

function Separator:set_value(value)
end

return Separator
