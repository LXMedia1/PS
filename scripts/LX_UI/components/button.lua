local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local Button = {}
setmetatable(Button, { __index = BaseComponent })
Button.__index = Button

function Button:new(options)
    options = options or {}
    options.height = options.height or 25
    options.width = options.width or 100

    local base = BaseComponent:new(constants.COMPONENT_TYPE.BUTTON, options)

    local button = setmetatable({
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
        is_pressed = false,
        parent_menu = base.parent_menu,
        auto_save = false,
        on_click = base.on_click,
        style = options.style or "default"  -- "default" or "primary"
    }, Button)

    return button
end

function Button:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    Rendering.button(abs_x, abs_y, self.width, self.height, self.text, self.is_hovered, self.is_pressed, self.style)
end

function Button:update()
    if not self:is_active() then return end

    -- Don't respond to input if menu doesn't have focus
    if not self:menu_has_focus() then
        self.is_hovered = false
        self.is_pressed = false
        return
    end

    local mx, my = Input.get_mouse_pos()
    self.is_hovered = self:contains_point(mx, my)

    -- Track press state
    if self.is_hovered and Input.is_left_down() then
        self.is_pressed = true
    else
        self.is_pressed = false
    end

    -- Click detection
    if self.is_hovered and Input.is_left_clicked() then
        self:click()
    end
end

function Button:click()
    if self.on_click then
        self.on_click(self)
    end
end

function Button:get_value()
    return nil
end

function Button:set_value(value)
end

return Button
