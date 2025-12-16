local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local ProgressBar = {}
setmetatable(ProgressBar, { __index = BaseComponent })
ProgressBar.__index = ProgressBar

function ProgressBar:new(options)
    options = options or {}
    options.height = options.height or 16

    local base = BaseComponent:new(constants.COMPONENT_TYPE.PROGRESSBAR, options)

    local progressbar = setmetatable({
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

        value = options.value or 0,
        max_value = options.max_value or 100,
        show_text = options.show_text ~= false,
        fill_color = options.fill_color or constants.Colors.progress_fill
    }, ProgressBar)

    return progressbar
end

function ProgressBar:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local percent = self:get_percentage()
    Rendering.progress_bar(abs_x, abs_y, self.width, self.height, percent, self.fill_color)

    if self.show_text then
        local text = string.format("%.0f%%", percent * 100)
        Rendering.text(
            abs_x + self.width / 2,
            abs_y + (self.height - constants.Settings.default_font_size) / 2,
            text,
            constants.Colors.text,
            nil,
            true
        )
    end
end

function ProgressBar:update()
end

function ProgressBar:get_percentage()
    if self.max_value == 0 then return 0 end
    return helpers.clamp(self.value / self.max_value, 0, 1)
end

function ProgressBar:get_value()
    return self.value
end

function ProgressBar:set_value(value)
    self.value = helpers.clamp(value, 0, self.max_value)
end

function ProgressBar:set_max(max)
    self.max_value = max
end

return ProgressBar
