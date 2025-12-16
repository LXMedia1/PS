local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local constants = require("utils/constants")

local Header = {}
setmetatable(Header, { __index = BaseComponent })
Header.__index = Header

function Header:new(options)
    options = options or {}
    options.height = options.height or 24

    local base = BaseComponent:new(constants.COMPONENT_TYPE.HEADER, options)

    local header = setmetatable({
        type = base.type,
        id = base.id,
        x = base.x,
        y = base.y,
        width = base.width,
        height = base.height,
        text = base.text,
        visible = base.visible,
        enabled = true,
        parent_menu = base.parent_menu,
        auto_save = false,

        font_size = options.font_size or 14,
        text_color = options.text_color or constants.Colors.text_title,
        show_line = options.show_line ~= false
    }, Header)

    return header
end

function Header:render()
    if not self.visible then return end

    Rendering.text(self.x, self.y, self.text, self.text_color, self.font_size, false)

    if self.show_line then
        local line_y = self.y + self.font_size + 4
        Rendering.separator(self.x, line_y, self.width)
    end
end

function Header:update()
end

function Header:get_value()
    return self.text
end

function Header:set_value(value)
    self.text = tostring(value)
end

return Header
