local BaseComponent = {}
BaseComponent.__index = BaseComponent

local constants = require("utils/constants")
local helpers = require("utils/helpers")
local Input = require("core/input")

function BaseComponent:new(component_type, options)
    options = options or {}

    local component = setmetatable({
        -- Identity
        type = component_type,
        id = options.id or helpers.generate_id(component_type),
        name = options.name or "",

        -- Position and size
        x = options.x or 0,
        y = options.y or 0,
        width = options.width or 100,
        height = options.height or constants.Settings.component_height,

        -- Text
        text = options.text or "",
        text_color = options.text_color or constants.Colors.text,

        -- State
        visible = options.visible ~= false,
        enabled = options.enabled ~= false,
        is_hovered = false,
        is_focused = false,
        is_pressed = false,

        -- Callbacks
        on_click = options.on_click,
        on_change = options.on_change,
        on_hover = options.on_hover,

        -- Auto-save
        auto_save = options.auto_save ~= false,
        save_key = options.save_key,

        -- Parent reference
        parent_menu = options.parent_menu,

        -- Custom data
        data = options.data or {}
    }, BaseComponent)

    return component
end

-- Check if component is active (visible and enabled)
function BaseComponent:is_active()
    return self.visible and self.enabled
end

-- Check if the parent menu has focus (for input handling)
function BaseComponent:menu_has_focus()
    -- _menu_has_focus is set by the parent menu during update
    return self._menu_has_focus ~= false
end

-- Set position
function BaseComponent:set_position(x, y)
    self.x = x
    self.y = y
end

-- Set size
function BaseComponent:set_size(width, height)
    self.width = width
    self.height = height
end

-- Set text
function BaseComponent:set_text(text)
    self.text = text
end

-- Set visibility
function BaseComponent:set_visible(visible)
    self.visible = visible
end

-- Set enabled state
function BaseComponent:set_enabled(enabled)
    self.enabled = enabled
end

-- Get absolute X position (includes parent menu offset)
function BaseComponent:get_abs_x()
    local menu_x = self.parent_menu and self.parent_menu.x or 0
    return self.x + menu_x
end

-- Get absolute Y position (includes parent menu offset)
function BaseComponent:get_abs_y()
    local menu_y = self.parent_menu and self.parent_menu.y or 0
    return self.y + menu_y
end

-- Get bounds as table
function BaseComponent:get_bounds()
    return {
        x = self:get_abs_x(),
        y = self:get_abs_y(),
        width = self.width,
        height = self.height
    }
end

-- Check if point is inside component (uses absolute position)
function BaseComponent:contains_point(px, py)
    return helpers.point_in_rect(px, py, self:get_abs_x(), self:get_abs_y(), self.width, self.height)
end

-- Update hover state based on mouse position
function BaseComponent:update_hover()
    if not self:is_active() then
        self.is_hovered = false
        return false
    end

    -- Don't register hover if parent menu doesn't have focus
    if not self:menu_has_focus() then
        self.is_hovered = false
        return false
    end

    local mx, my = Input.get_mouse_pos()
    local was_hovered = self.is_hovered
    self.is_hovered = self:contains_point(mx, my)

    if self.is_hovered and not was_hovered and self.on_hover then
        self.on_hover(self)
    end

    return self.is_hovered
end

-- Handle click
function BaseComponent:handle_click()
    if self.on_click then
        self.on_click(self)
    end
end

-- Abstract methods (to be overridden)
function BaseComponent:update()
    -- Override in subclass
end

function BaseComponent:render()
    -- Override in subclass
end

-- Render overlay elements (dropdowns, tooltips, etc.) - called after all components render
function BaseComponent:render_overlay()
    -- Override in subclass for components with overlays
end

-- Check if component has an active overlay that should capture input
function BaseComponent:has_overlay()
    return false
end

function BaseComponent:get_value()
    -- Override in subclass
    return nil
end

function BaseComponent:set_value(value)
    -- Override in subclass
end

-- Save value (for auto-save)
function BaseComponent:save_value()
    if self.auto_save and self.parent_menu then
        self.parent_menu:save_component(self.id, self:get_value())
    end
end

-- Load value (for auto-save)
function BaseComponent:load_value(default)
    if self.auto_save and self.parent_menu then
        local value = self.parent_menu:load_component(self.id)
        if value ~= nil then
            self:set_value(value)
            return true
        end
    end
    if default ~= nil then
        self:set_value(default)
    end
    return false
end

return BaseComponent
