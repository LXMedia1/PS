local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local Slider = {}
setmetatable(Slider, { __index = BaseComponent })
Slider.__index = Slider

function Slider:new(options)
    options = options or {}
    options.height = options.height or constants.Settings.component_height

    local base = BaseComponent:new(constants.COMPONENT_TYPE.SLIDER, options)

    local slider = setmetatable({
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
        is_dragging = false,
        parent_menu = base.parent_menu,
        auto_save = base.auto_save,
        on_change = base.on_change,

        min_value = options.min or options.min_value or 0,
        max_value = options.max or options.max_value or 100,
        value = options.value or options.default or 50,
        slider_type = options.slider_type or "int",
        decimals = options.decimals or 2,

        track_height = options.track_height or 8,
        show_value = options.show_value ~= false
    }, Slider)

    slider.value = helpers.clamp(slider.value, slider.min_value, slider.max_value)

    return slider
end

function Slider:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local label_height = constants.Settings.default_font_size
    local track_y = abs_y + label_height + 4
    local track_width = self.width

    -- Draw label
    local text_col = self.enabled and self.text_color or constants.Colors.text_disabled
    Rendering.text(abs_x, abs_y, self.text, text_col)

    -- Draw value
    if self.show_value then
        local value_str = self:get_display_value()
        Rendering.text(abs_x + self.width - 40, abs_y, value_str, constants.Colors.text_dim)
    end

    -- Draw slider track
    local percent = self:get_percentage()
    Rendering.slider(abs_x, track_y, track_width, self.track_height, percent, self.is_hovered, self.is_dragging)
end

function Slider:update()
    if not self:is_active() then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local mx, my = Input.get_mouse_pos()
    local label_height = constants.Settings.default_font_size
    local track_y = abs_y + label_height + 4

    self.is_hovered = helpers.point_in_rect(mx, my, abs_x, track_y, self.width, self.track_height + 4)

    -- Start dragging
    if self.is_hovered and Input.is_left_clicked() then
        self.is_dragging = true
    end

    -- Stop dragging
    if Input.is_left_released() then
        if self.is_dragging then
            self:save_value()
        end
        self.is_dragging = false
    end

    -- Update value while dragging
    if self.is_dragging then
        local percent = (mx - abs_x) / self.width
        percent = helpers.clamp(percent, 0, 1)
        self:set_percentage(percent)
    end
end

function Slider:get_percentage()
    local range = self.max_value - self.min_value
    if range == 0 then return 0 end
    return (self.value - self.min_value) / range
end

function Slider:set_percentage(percent)
    local old_value = self.value
    local range = self.max_value - self.min_value
    self.value = self.min_value + range * percent
    self.value = helpers.clamp(self.value, self.min_value, self.max_value)

    if self.slider_type == "int" then
        self.value = math.floor(self.value + 0.5)
    end

    if self.value ~= old_value and self.on_change then
        self.on_change(self, self.value)
    end
end

function Slider:get_display_value()
    if self.slider_type == "int" then
        return tostring(math.floor(self.value))
    else
        return string.format("%." .. self.decimals .. "f", self.value)
    end
end

function Slider:get_value()
    return self.value
end

function Slider:set_value(value)
    self.value = helpers.clamp(value, self.min_value, self.max_value)
    if self.slider_type == "int" then
        self.value = math.floor(self.value + 0.5)
    end
end

function Slider:set_range(min, max)
    self.min_value = min
    self.max_value = max
    self.value = helpers.clamp(self.value, min, max)
end

return Slider
