local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local Checkbox = {}
setmetatable(Checkbox, { __index = BaseComponent })
Checkbox.__index = Checkbox

function Checkbox:new(options)
    options = options or {}
    options.height = options.height or constants.Settings.component_height

    local base = BaseComponent:new(constants.COMPONENT_TYPE.CHECKBOX, options)

    local checkbox = setmetatable({
        type = base.type,
        id = base.id,
        name = base.name,
        x = base.x,
        y = base.y,
        width = base.width,
        height = base.height,
        text = base.text,
        text_color = base.text_color,
        visible = base.visible,
        enabled = base.enabled,
        is_hovered = false,
        parent_menu = base.parent_menu,
        auto_save = base.auto_save,
        on_change = base.on_change,

        checked = options.checked or options.default or false,
        box_size = options.box_size or 16
    }, Checkbox)

    return checkbox
end

function Checkbox:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local box_y = abs_y + (self.height - self.box_size) / 2

    -- Draw checkbox
    Rendering.checkbox(abs_x, box_y, self.box_size, self.checked, self.is_hovered)

    -- Draw label
    local text_x = abs_x + self.box_size + 8
    local text_y = abs_y + (self.height - constants.Settings.default_font_size) / 2
    local text_col = self.enabled and self.text_color or constants.Colors.text_disabled
    Rendering.text(text_x, text_y, self.text, text_col)
end

function Checkbox:update()
    if not self:is_active() then return end

    -- Don't respond to input if menu doesn't have focus
    if not self:menu_has_focus() then
        self.is_hovered = false
        return
    end

    local mx, my = Input.get_mouse_pos()
    self.is_hovered = self:contains_point(mx, my)

    if self.is_hovered and Input.is_left_clicked() then
        self:toggle()
    end
end

function Checkbox:toggle()
    self.checked = not self.checked

    if self.on_change then
        self.on_change(self, self.checked)
    end

    self:save_value()
end

function Checkbox:get_value()
    return self.checked
end

function Checkbox:set_value(value)
    self.checked = value == true
end

function Checkbox:is_checked()
    return self.checked
end

return Checkbox
