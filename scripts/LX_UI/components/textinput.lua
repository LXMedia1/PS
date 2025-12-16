local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local TextInput = {}
setmetatable(TextInput, { __index = BaseComponent })
TextInput.__index = TextInput

-- Character width for cursor calculations
local CHAR_WIDTH = 5.5

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
        max_length = options.max_length or 256,

        -- Cursor position (0 = before first char, 1 = after first char, etc.)
        cursor_pos = 0,
        -- Selection
        select_all = false,
        -- Double-click detection
        last_click_time = 0,
        double_click_threshold = 300
    }, TextInput)

    textinput.cursor_pos = #textinput.value

    return textinput
end

function TextInput:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()

    local display_text = self.value
    if display_text == "" and not self.is_focused then
        display_text = self.placeholder
    end

    -- Draw label if provided
    local input_x = abs_x
    local input_width = self.width
    if self.text and self.text ~= "" then
        Rendering.text(abs_x, abs_y + (self.height - constants.Settings.default_font_size) / 2, self.text, constants.Colors.text)
        input_x = abs_x + 80
        input_width = self.width - 80
    end

    -- Store input_x for click detection
    self._input_x = input_x
    self._input_width = input_width

    -- Draw input field
    Rendering.text_input(input_x, abs_y, input_width, self.height, display_text, self.is_focused, self.is_hovered)

    -- Draw selection highlight when all selected
    if self.is_focused and self.select_all and #self.value > 0 then
        local padding = 5
        local font_size = constants.Settings.default_font_size
        local text_width = #self.value * CHAR_WIDTH
        local sel_y = abs_y + (self.height - font_size) / 2
        Rendering.rect_filled(input_x + padding, sel_y, text_width, font_size, constants.Colors.accent)
        -- Redraw text on top of selection with white color
        Rendering.text(input_x + padding, sel_y, self.value, constants.Colors.text_title)
    end

    -- Draw cursor when focused (and not selecting all)
    if self.is_focused and not self.select_all then
        local padding = 5
        local font_size = constants.Settings.default_font_size
        local cursor_x = input_x + padding + (self.cursor_pos * CHAR_WIDTH)
        local cursor_y = abs_y + (self.height - font_size) / 2
        Rendering.rect_filled(cursor_x, cursor_y, 1, font_size, constants.Colors.text)
    end
end

function TextInput:update()
    if not self:is_active() then return end

    local mx, my = Input.get_mouse_pos()

    -- Don't respond to new input if menu doesn't have focus
    -- But continue handling if already focused
    if not self:menu_has_focus() and not self.is_focused then
        self.is_hovered = false
        return
    end

    self.is_hovered = self:contains_point(mx, my)

    -- Handle click (only acquire focus if menu has focus)
    if Input.is_left_clicked() then
        local was_focused = self.is_focused
        if self:menu_has_focus() then
            self.is_focused = self.is_hovered
        elseif not self.is_hovered then
            self.is_focused = false
        end

        if self.is_hovered and self._input_x and self:menu_has_focus() then
            -- Check for double-click
            local current_time = (core.time and core.time() * 1000) or 0
            if was_focused and (current_time - self.last_click_time) < self.double_click_threshold then
                -- Double-click: select all
                self.select_all = true
                self.last_click_time = 0
            else
                -- Single click: position cursor
                self.select_all = false
                local padding = 5
                local click_x = mx - self._input_x - padding
                local char_pos = math.floor(click_x / CHAR_WIDTH + 0.5)
                self.cursor_pos = math.max(0, math.min(char_pos, #self.value))
                self.last_click_time = current_time
            end
        end
    end

    -- Handle text input when focused
    if self.is_focused then
        -- Capture keyboard to prevent game input
        Input.capture_keyboard()

        -- Get typed character
        local char = Input.get_typed_char()
        if char and #self.value < self.max_length then
            if self.select_all then
                -- Replace all text
                self.value = char
                self.cursor_pos = 1
                self.select_all = false
            else
                -- Insert at cursor position
                local before = string.sub(self.value, 1, self.cursor_pos)
                local after = string.sub(self.value, self.cursor_pos + 1)
                self.value = before .. char .. after
                self.cursor_pos = self.cursor_pos + 1
            end
            if self.on_change then
                self.on_change(self, self.value)
            end
        end

        -- Backspace
        if Input.is_key_just_pressed(constants.VK.BACK) then
            if self.select_all then
                -- Delete all
                self.value = ""
                self.cursor_pos = 0
                self.select_all = false
            elseif self.cursor_pos > 0 then
                -- Delete character before cursor
                local before = string.sub(self.value, 1, self.cursor_pos - 1)
                local after = string.sub(self.value, self.cursor_pos + 1)
                self.value = before .. after
                self.cursor_pos = self.cursor_pos - 1
            end
            if self.on_change then
                self.on_change(self, self.value)
            end
        end

        -- Delete key
        if Input.is_key_just_pressed(constants.VK.DELETE) then
            if self.select_all then
                -- Delete all
                self.value = ""
                self.cursor_pos = 0
                self.select_all = false
            elseif self.cursor_pos < #self.value then
                -- Delete character after cursor
                local before = string.sub(self.value, 1, self.cursor_pos)
                local after = string.sub(self.value, self.cursor_pos + 2)
                self.value = before .. after
            end
            if self.on_change then
                self.on_change(self, self.value)
            end
        end

        -- Left arrow
        if Input.is_key_just_pressed(constants.VK.LEFT) then
            self.select_all = false
            self.cursor_pos = math.max(0, self.cursor_pos - 1)
        end

        -- Right arrow
        if Input.is_key_just_pressed(constants.VK.RIGHT) then
            self.select_all = false
            self.cursor_pos = math.min(#self.value, self.cursor_pos + 1)
        end

        -- Home key
        if Input.is_key_just_pressed(constants.VK.HOME) then
            self.select_all = false
            self.cursor_pos = 0
        end

        -- End key
        if Input.is_key_just_pressed(constants.VK.END_KEY) then
            self.select_all = false
            self.cursor_pos = #self.value
        end

        -- Ctrl+A to select all
        if Input.is_ctrl_down() and Input.is_key_just_pressed(0x41) then
            self.select_all = true
        end

        -- Escape to unfocus
        if Input.is_key_just_pressed(constants.VK.ESCAPE) then
            self.is_focused = false
            self.select_all = false
        end

        -- Enter to unfocus and save
        if Input.is_key_just_pressed(constants.VK.RETURN) then
            self.is_focused = false
            self.select_all = false
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
    self.cursor_pos = #self.value
    self.select_all = false
end

return TextInput
