local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local ColorPicker = {}
setmetatable(ColorPicker, { __index = BaseComponent })
ColorPicker.__index = ColorPicker

function ColorPicker:new(options)
    options = options or {}
    options.height = options.height or 24

    local base = BaseComponent:new(constants.COMPONENT_TYPE.COLORPICKER, options)

    local colorpicker = setmetatable({
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
        is_open = false,
        parent_menu = base.parent_menu,
        auto_save = base.auto_save,
        on_change = base.on_change,

        r = options.r or 255,
        g = options.g or 255,
        b = options.b or 255,
        a = options.a or 255,

        preview_size = options.preview_size or 24
    }, ColorPicker)

    -- Load default color if provided
    if options.default then
        colorpicker.r = options.default.r or options.default[1] or 255
        colorpicker.g = options.default.g or options.default[2] or 255
        colorpicker.b = options.default.b or options.default[3] or 255
        colorpicker.a = options.default.a or options.default[4] or 255
    end

    return colorpicker
end

function ColorPicker:render()
    if not self.visible then return end

    local preview_x = self.x + self.width - self.preview_size

    -- Draw label
    if self.text and self.text ~= "" then
        Rendering.text(self.x, self.y + 4, self.text, constants.Colors.text)
    end

    -- Draw color preview
    local preview_color = constants.color.new(self.r, self.g, self.b, self.a)
    Rendering.rect_filled(preview_x, self.y, self.preview_size, self.preview_size, preview_color, 2)
    Rendering.rect(preview_x, self.y, self.preview_size, self.preview_size, constants.Colors.border, 1, 2)

    -- Draw expanded picker if open
    if self.is_open then
        local picker_y = self.y + self.height + 4
        local picker_width = 180
        local picker_height = 120

        -- Background
        Rendering.rect_filled(preview_x - picker_width + self.preview_size, picker_y, picker_width, picker_height, constants.Colors.component_bg, 4)
        Rendering.rect(preview_x - picker_width + self.preview_size, picker_y, picker_width, picker_height, constants.Colors.border, 1, 4)

        local slider_x = preview_x - picker_width + self.preview_size + 10
        local slider_width = picker_width - 20

        -- R slider
        self:render_color_slider(slider_x, picker_y + 10, slider_width, 16, "R", self.r, constants.color.new(255, 0, 0, 255))

        -- G slider
        self:render_color_slider(slider_x, picker_y + 35, slider_width, 16, "G", self.g, constants.color.new(0, 255, 0, 255))

        -- B slider
        self:render_color_slider(slider_x, picker_y + 60, slider_width, 16, "B", self.b, constants.color.new(0, 0, 255, 255))

        -- A slider
        self:render_color_slider(slider_x, picker_y + 85, slider_width, 16, "A", self.a, constants.color.new(255, 255, 255, 255))
    end
end

function ColorPicker:render_color_slider(x, y, w, h, label, value, col)
    Rendering.text(x, y, label, constants.Colors.text_dim)

    local slider_x = x + 20
    local slider_w = w - 50

    Rendering.rect_filled(slider_x, y, slider_w, h, constants.Colors.slider_track, 2)
    local fill_w = (value / 255) * slider_w
    Rendering.rect_filled(slider_x, y, fill_w, h, col, 2)
    Rendering.rect(slider_x, y, slider_w, h, constants.Colors.border, 1, 2)

    Rendering.text(slider_x + slider_w + 5, y, tostring(math.floor(value)), constants.Colors.text_dim)
end

function ColorPicker:update()
    if not self:is_active() then return end

    local mx, my = Input.get_mouse_pos()
    local preview_x = self.x + self.width - self.preview_size

    self.is_hovered = helpers.point_in_rect(mx, my, preview_x, self.y, self.preview_size, self.preview_size)

    if Input.is_left_clicked() then
        if self.is_hovered then
            self.is_open = not self.is_open
        elseif self.is_open then
            -- Check if clicking on sliders
            local picker_y = self.y + self.height + 4
            local picker_width = 180
            local slider_x = preview_x - picker_width + self.preview_size + 30
            local slider_w = picker_width - 50

            local changed = false

            -- R slider
            if helpers.point_in_rect(mx, my, slider_x, picker_y + 10, slider_w, 16) then
                self.r = math.floor(((mx - slider_x) / slider_w) * 255)
                self.r = helpers.clamp(self.r, 0, 255)
                changed = true
            end

            -- G slider
            if helpers.point_in_rect(mx, my, slider_x, picker_y + 35, slider_w, 16) then
                self.g = math.floor(((mx - slider_x) / slider_w) * 255)
                self.g = helpers.clamp(self.g, 0, 255)
                changed = true
            end

            -- B slider
            if helpers.point_in_rect(mx, my, slider_x, picker_y + 60, slider_w, 16) then
                self.b = math.floor(((mx - slider_x) / slider_w) * 255)
                self.b = helpers.clamp(self.b, 0, 255)
                changed = true
            end

            -- A slider
            if helpers.point_in_rect(mx, my, slider_x, picker_y + 85, slider_w, 16) then
                self.a = math.floor(((mx - slider_x) / slider_w) * 255)
                self.a = helpers.clamp(self.a, 0, 255)
                changed = true
            end

            if changed then
                if self.on_change then
                    self.on_change(self, self:get_color())
                end
                self:save_value()
            end

            -- Close if clicked outside
            local picker_height = 120
            if not helpers.point_in_rect(mx, my, preview_x - picker_width + self.preview_size, picker_y, picker_width, picker_height) then
                self.is_open = false
            end
        end
    end
end

function ColorPicker:get_color()
    return constants.color.new(self.r, self.g, self.b, self.a)
end

function ColorPicker:set_color(r, g, b, a)
    self.r = helpers.clamp(r or 255, 0, 255)
    self.g = helpers.clamp(g or 255, 0, 255)
    self.b = helpers.clamp(b or 255, 0, 255)
    self.a = helpers.clamp(a or 255, 0, 255)
end

function ColorPicker:get_value()
    return {r = self.r, g = self.g, b = self.b, a = self.a}
end

function ColorPicker:set_value(value)
    if type(value) == "table" then
        self.r = value.r or value[1] or 255
        self.g = value.g or value[2] or 255
        self.b = value.b or value[3] or 255
        self.a = value.a or value[4] or 255
    end
end

return ColorPicker
