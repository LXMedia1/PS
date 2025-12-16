local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local Keybind = {}
setmetatable(Keybind, { __index = BaseComponent })
Keybind.__index = Keybind

function Keybind:new(options)
    options = options or {}
    options.height = options.height or 24

    local base = BaseComponent:new(constants.COMPONENT_TYPE.KEYBIND, options)

    local keybind = setmetatable({
        type = base.type,
        id = base.id,
        name = base.name,
        x = base.x,
        y = base.y,
        width = base.width,
        height = base.height,
        text = base.text,
        visible = base.visible,
        enabled = base.enabled,
        is_hovered = false,
        is_capturing = false,
        parent_menu = base.parent_menu,
        auto_save = base.auto_save,
        on_change = base.on_change,

        key = options.key or options.default or 0,
        is_toggle = options.is_toggle or false,
        toggle_state = false
    }, Keybind)

    return keybind
end

function Keybind:render()
    if not self.visible then return end

    local btn_x = self.x
    local btn_width = 80

    -- Draw label
    if self.text and self.text ~= "" then
        Rendering.text(self.x, self.y + 4, self.text, constants.Colors.text)
        btn_x = self.x + self.width - btn_width
    end

    -- Draw keybind button
    local display_text = self.is_capturing and "..." or self:get_key_name()
    local bg_col = constants.Colors.component_bg
    if self.is_capturing then
        bg_col = constants.Colors.accent
    elseif self.is_hovered then
        bg_col = constants.Colors.hover
    end

    Rendering.rect_filled(btn_x, self.y, btn_width, self.height, bg_col, 2)
    Rendering.rect(btn_x, self.y, btn_width, self.height, constants.Colors.border, 1, 2)
    Rendering.text(btn_x + btn_width / 2, self.y + 4, display_text, constants.Colors.text, nil, true)
end

function Keybind:update()
    if not self:is_active() then return end

    local mx, my = Input.get_mouse_pos()

    local btn_x = self.x
    local btn_width = 80
    if self.text and self.text ~= "" then
        btn_x = self.x + self.width - btn_width
    end

    self.is_hovered = helpers.point_in_rect(mx, my, btn_x, self.y, btn_width, self.height)

    if Input.is_left_clicked() then
        if self.is_hovered then
            self.is_capturing = true
        elseif self.is_capturing then
            self.is_capturing = false
        end
    end

    -- Capture key
    if self.is_capturing then
        -- Escape to cancel
        if Input.is_key_pressed(constants.VK.ESCAPE) then
            self.is_capturing = false
            return
        end

        -- Check for key press
        local key = Input.get_pressed_key()
        if key then
            self.key = key
            self.is_capturing = false

            if self.on_change then
                self.on_change(self, self.key)
            end

            self:save_value()
        end
    end
end

function Keybind:get_key_name()
    if self.key == 0 then
        return "None"
    end
    return helpers.get_key_name(self.key)
end

function Keybind:is_pressed()
    if self.key == 0 then return false end
    return Input.is_key_pressed(self.key)
end

function Keybind:check()
    if self.is_toggle then
        if self:is_pressed() then
            self.toggle_state = not self.toggle_state
        end
        return self.toggle_state
    else
        return self:is_pressed()
    end
end

function Keybind:get_value()
    return self.key
end

function Keybind:set_value(value)
    self.key = value or 0
end

return Keybind
