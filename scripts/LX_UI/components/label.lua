local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local constants = require("utils/constants")

local Label = {}
setmetatable(Label, { __index = BaseComponent })
Label.__index = Label

function Label:new(options)
    options = options or {}
    options.height = options.height or constants.Settings.default_font_size

    local base = BaseComponent:new(constants.COMPONENT_TYPE.LABEL, options)

    local label = setmetatable({
        type = base.type,
        id = base.id,
        name = base.name,
        x = base.x,
        y = base.y,
        width = base.width,
        height = base.height,
        text = base.text,
        text_color = options.text_color or constants.Colors.text,
        visible = base.visible,
        enabled = base.enabled,
        parent_menu = base.parent_menu,
        auto_save = false,

        font_size = options.font_size or constants.Settings.default_font_size,
        centered = options.centered or false
    }, Label)

    return label
end

function Label:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local text_x = abs_x
    if self.centered then
        text_x = abs_x + self.width / 2
    end

    Rendering.text(text_x, abs_y, self.text, self.text_color, self.font_size, self.centered)
end

function Label:update()
    -- Labels don't need updates
end

function Label:get_value()
    return self.text
end

function Label:set_value(value)
    self.text = tostring(value)
end

return Label
