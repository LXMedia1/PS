local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local TextInput = {}
setmetatable(TextInput, { __index = BaseComponent })
TextInput.__index = TextInput

function TextInput:new(options)
    options = options or {}
    options.height = options.height or 24

    local base = BaseComponent:new(constants.COMPONENT_TYPE.TEXTINPUT, options)

    local textinput = setmetatable({
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
        is_focused = false,
        parent_menu = base.parent_menu,
        auto_save = base.auto_save,
        on_change = base.on_change,

        value = options.value or options.default or "",
        placeholder = options.placeholder or "",
        max_length = options.max_length or 256
    }, TextInput)

    return textinput
end

function TextInput:render()
    if not self.visible then return end

    local display_text = self.value
    if display_text == "" and not self.is_focused then
        display_text = self.placeholder
    end

    -- Draw label if provided
    local input_x = self.x
    local input_width = self.width
    if self.text and self.text ~= "" then
        Rendering.text(self.x, self.y + 4, self.text, constants.Colors.text)
        input_x = self.x + 80
        input_width = self.width - 80
    end

    -- Draw input field
    Rendering.text_input(input_x, self.y, input_width, self.height, display_text, self.is_focused, self.is_hovered)

    -- Draw cursor when focused
    if self.is_focused then
        local text_width = #self.value * 7
        local cursor_x = input_x + 5 + text_width
        Rendering.rect_filled(cursor_x, self.y + 4, 1, self.height - 8, constants.Colors.text)
    end
end

function TextInput:update()
    if not self:is_active() then return end

    local mx, my = Input.get_mouse_pos()
    self.is_hovered = helpers.point_in_rect(mx, my, self.x, self.y, self.width, self.height)

    if Input.is_left_clicked() then
        self.is_focused = self.is_hovered
    end

    -- Handle text input when focused
    if self.is_focused then
        -- Backspace
        if Input.is_key_pressed(constants.VK.BACK) then
            if #self.value > 0 then
                self.value = string.sub(self.value, 1, -2)
                if self.on_change then
                    self.on_change(self, self.value)
                end
            end
        end

        -- Escape to unfocus
        if Input.is_key_pressed(constants.VK.ESCAPE) then
            self.is_focused = false
        end

        -- Enter to unfocus and save
        if Input.is_key_pressed(constants.VK.RETURN) then
            self.is_focused = false
            self:save_value()
        end
    end
end

function TextInput:append(text)
    if #self.value + #text <= self.max_length then
        self.value = self.value .. text
        if self.on_change then
            self.on_change(self, self.value)
        end
    end
end

function TextInput:clear()
    self.value = ""
    if self.on_change then
        self.on_change(self, self.value)
    end
end

function TextInput:get_value()
    return self.value
end

function TextInput:set_value(value)
    self.value = tostring(value or "")
    if #self.value > self.max_length then
        self.value = string.sub(self.value, 1, self.max_length)
    end
end

return TextInput
