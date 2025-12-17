local Menu = {}
Menu.__index = Menu

local constants = require("utils/constants")
local helpers = require("utils/helpers")
local Input = require("core/input")
local Rendering = require("core/rendering")

local vec2 = constants.vec2
local color = constants.color

-- Global menu manager for focus/z-order tracking
-- This is shared across all menus
if not _G.LX_UI_MenuManager then
    _G.LX_UI_MenuManager = {
        menus = {},           -- All registered menus
        z_order = {},         -- Menu IDs in z-order (last = topmost)
        focused_menu = nil,   -- Currently focused menu ID
    }
end
local MenuManager = _G.LX_UI_MenuManager

-- Register a menu with the manager
local function register_menu(menu)
    MenuManager.menus[menu.save_key] = menu
    -- Add to z_order if not present
    local found = false
    for _, key in ipairs(MenuManager.z_order) do
        if key == menu.save_key then
            found = true
            break
        end
    end
    if not found then
        table.insert(MenuManager.z_order, menu.save_key)
    end
end

-- Bring a menu to the front (topmost)
local function bring_to_front(menu)
    -- Remove from current position
    for i, key in ipairs(MenuManager.z_order) do
        if key == menu.save_key then
            table.remove(MenuManager.z_order, i)
            break
        end
    end
    -- Add to end (topmost)
    table.insert(MenuManager.z_order, menu.save_key)
    MenuManager.focused_menu = menu.save_key
end

-- Count how many menus are open
local function count_open_menus()
    local count = 0
    for _, key in ipairs(MenuManager.z_order) do
        local m = MenuManager.menus[key]
        if m and m.is_open then
            count = count + 1
        end
    end
    return count
end

-- Check if a menu is the topmost menu under the mouse
local function is_topmost_at_mouse(menu)
    -- If only one menu is open, it's always topmost
    if count_open_menus() <= 1 then
        return true
    end

    local mx, my = Input.get_mouse_pos()

    -- Check menus from topmost (end) to bottommost (start)
    for i = #MenuManager.z_order, 1, -1 do
        local key = MenuManager.z_order[i]
        local m = MenuManager.menus[key]
        if m and m.is_open then
            local display_height = m:get_display_height()
            if helpers.point_in_rect(mx, my, m.x, m.y, m.width, display_height) then
                -- This is the topmost menu under the mouse
                return m.save_key == menu.save_key
            end
        end
    end

    -- No menu under mouse - treat as topmost
    return true
end

function Menu:new(title, width, height, save_key)
    local menu = setmetatable({
        -- Identity
        title = title or "Menu",
        save_key = save_key or "lx_ui_menu",

        -- Dimensions
        width = width or 300,
        height = height or 400,
        min_height = height or 400,
        auto_height = true,

        -- Position (centered by default)
        x = 100,
        y = 100,

        -- State
        is_open = true,
        is_collapsed = false,
        is_dragging = false,
        drag_offset_x = 0,
        drag_offset_y = 0,

        -- Double-click tracking
        last_click_time = 0,
        double_click_threshold = 300,

        -- Components
        components = {},
        component_order = {},

        -- Auto Y positioning
        next_y = constants.Settings.title_bar_height + constants.Settings.default_padding,

        -- Saved data cache
        saved_data = {},

        -- Core window (for input capture)
        core_window = nil
    }, Menu)

    -- Create core window for input handling
    menu.core_window = core.menu.window(save_key .. "_window")

    -- Try to load saved position and data
    menu:load_all()

    -- Register with global menu manager
    register_menu(menu)

    return menu
end

-- Show menu
function Menu:show()
    self.is_open = true
end

-- Hide menu
function Menu:hide()
    self.is_open = false
end

-- Toggle visibility
function Menu:toggle()
    self.is_open = not self.is_open
end

-- Collapse menu (show only title bar)
function Menu:collapse()
    self.is_collapsed = true
end

-- Expand menu (show all components)
function Menu:expand()
    self.is_collapsed = false
end

-- Toggle collapsed state
function Menu:toggle_collapse()
    self.is_collapsed = not self.is_collapsed
    self:save_all()
end

-- Get current display height (collapsed = title bar only)
function Menu:get_display_height()
    if self.is_collapsed then
        return constants.Settings.title_bar_height
    end
    return self.height
end

-- Get next Y position for auto-layout
function Menu:get_next_y(spacing)
    spacing = spacing or constants.Settings.default_spacing
    local y = self.next_y
    return y
end

-- Advance Y position after adding component
function Menu:advance_y(height, spacing)
    spacing = spacing or constants.Settings.default_spacing
    self.next_y = self.next_y + height + spacing
    self:update_height()
end

-- Update menu height to fit all components
function Menu:update_height()
    if self.auto_height then
        local needed_height = self.next_y + constants.Settings.default_padding
        self.height = math.max(self.min_height, needed_height)
    end
end

-- Generate unique ID
function Menu:generate_id(prefix)
    return helpers.generate_id(prefix)
end

-- Add component to menu
function Menu:add_component(component)
    component.parent_menu = self
    self.components[component.id] = component
    table.insert(self.component_order, component.id)

    -- Try to load saved value
    component:load_value()

    return component
end

-- Get component by ID
function Menu:get_component(id)
    return self.components[id]
end

-- Remove component
function Menu:remove_component(id)
    self.components[id] = nil
    for i, cid in ipairs(self.component_order) do
        if cid == id then
            table.remove(self.component_order, i)
            break
        end
    end
end

-- Clear all components
function Menu:clear_components()
    self.components = {}
    self.component_order = {}
    self.next_y = constants.Settings.title_bar_height + constants.Settings.default_padding
end

-- Save component value
function Menu:save_component(id, value)
    self.saved_data[id] = value
    self:save_all()
end

-- Load component value
function Menu:load_component(id)
    return self.saved_data[id]
end

-- Save all data to file
function Menu:save_all()
    local data = {
        x = self.x,
        y = self.y,
        is_collapsed = self.is_collapsed,
        components = self.saved_data
    }

    local json_str = self:encode_json(data)
    if json_str then
        -- Create file first if it doesn't exist
        if core.create_data_file then
            core.create_data_file(self.save_key)
        end
        core.write_data_file(self.save_key, json_str)
    end
end

-- Load all data from file
function Menu:load_all()
    local content = core.read_data_file(self.save_key)
    if content and content ~= "" then
        local data = self:decode_json(content)
        if data then
            if data.x then self.x = data.x end
            if data.y then self.y = data.y end
            if data.is_collapsed ~= nil then self.is_collapsed = data.is_collapsed end
            if data.components then self.saved_data = data.components end
        end
    end
end

-- Simple JSON encode (for saving)
function Menu:encode_json(tbl)
    local function encode_value(val)
        local t = type(val)
        if t == "string" then
            return '"' .. val:gsub('"', '\\"') .. '"'
        elseif t == "number" then
            return tostring(val)
        elseif t == "boolean" then
            return val and "true" or "false"
        elseif t == "table" then
            local parts = {}
            local is_array = #val > 0
            if is_array then
                for _, v in ipairs(val) do
                    table.insert(parts, encode_value(v))
                end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                for k, v in pairs(val) do
                    table.insert(parts, '"' .. tostring(k) .. '":' .. encode_value(v))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end
        return "null"
    end
    return encode_value(tbl)
end

-- Simple JSON decode (for loading)
function Menu:decode_json(str)
    if not str or str == "" then return nil end

    local success, result = pcall(function()
        local pos = 1

        local function skip_whitespace()
            while pos <= #str and str:sub(pos, pos):match("%s") do
                pos = pos + 1
            end
        end

        local function parse_value()
            skip_whitespace()
            local char = str:sub(pos, pos)

            if char == '"' then
                -- String
                pos = pos + 1
                local start = pos
                while pos <= #str and str:sub(pos, pos) ~= '"' do
                    if str:sub(pos, pos) == "\\" then pos = pos + 1 end
                    pos = pos + 1
                end
                local value = str:sub(start, pos - 1)
                pos = pos + 1
                return value
            elseif char == "{" then
                -- Object
                pos = pos + 1
                local obj = {}
                skip_whitespace()
                while str:sub(pos, pos) ~= "}" do
                    skip_whitespace()
                    if str:sub(pos, pos) == '"' then
                        pos = pos + 1
                        local key_start = pos
                        while str:sub(pos, pos) ~= '"' do pos = pos + 1 end
                        local key = str:sub(key_start, pos - 1)
                        pos = pos + 1
                        skip_whitespace()
                        pos = pos + 1 -- skip :
                        obj[key] = parse_value()
                        skip_whitespace()
                        if str:sub(pos, pos) == "," then pos = pos + 1 end
                    else
                        break
                    end
                end
                pos = pos + 1
                return obj
            elseif char == "[" then
                -- Array
                pos = pos + 1
                local arr = {}
                skip_whitespace()
                while str:sub(pos, pos) ~= "]" do
                    table.insert(arr, parse_value())
                    skip_whitespace()
                    if str:sub(pos, pos) == "," then pos = pos + 1 end
                end
                pos = pos + 1
                return arr
            elseif str:sub(pos, pos + 3) == "true" then
                pos = pos + 4
                return true
            elseif str:sub(pos, pos + 4) == "false" then
                pos = pos + 5
                return false
            elseif str:sub(pos, pos + 3) == "null" then
                pos = pos + 4
                return nil
            else
                -- Number
                local start = pos
                while pos <= #str and str:sub(pos, pos):match("[%d%.%-eE%+]") do
                    pos = pos + 1
                end
                return tonumber(str:sub(start, pos - 1))
            end
        end

        return parse_value()
    end)

    return success and result or nil
end

-- Check if mouse is over menu
function Menu:is_mouse_over()
    local mx, my = Input.get_mouse_pos()
    return helpers.point_in_rect(mx, my, self.x, self.y, self.width, self:get_display_height())
end

-- Block game input when over menu (only if this is the topmost menu)
function Menu:block_input()
    local mx, my = Input.get_mouse_pos()
    local display_height = self:get_display_height()
    local is_over = helpers.point_in_rect(mx, my, self.x, self.y, self.width, display_height)

    -- Only capture input if this menu is topmost at the mouse position
    -- or if we're actively dragging this menu
    local should_capture = self.is_dragging or (is_over and is_topmost_at_mouse(self))

    if should_capture then
        if core.graphics.capture_next_mouse_input then
            core.graphics.capture_next_mouse_input()
        end
    end

    return is_over, should_capture
end

-- Update menu and all components
function Menu:update()
    if not self.is_open then return end

    Input.update()

    local mx, my = Input.get_mouse_pos()
    local title_height = constants.Settings.title_bar_height

    -- Block game input when mouse is over menu (only if topmost)
    local is_over, has_focus = self:block_input()

    -- Check if this menu is the topmost one under the mouse
    local is_topmost = is_topmost_at_mouse(self)

    -- Handle double-click on title bar to collapse/expand (only if focused)
    local over_title = helpers.point_in_rect(mx, my, self.x, self.y, self.width, title_height)
    if over_title and is_topmost and Input.is_left_clicked() then
        -- Bring to front when clicked
        bring_to_front(self)

        local current_time = (core.time and core.time() * 1000) or 0
        if current_time - self.last_click_time < self.double_click_threshold then
            self:toggle_collapse()
            self.last_click_time = 0
        else
            self.last_click_time = current_time
        end
    end

    -- Bring menu to front if clicked anywhere on it
    if is_over and is_topmost and Input.is_left_clicked() then
        bring_to_front(self)
    end

    -- Handle window dragging (only if this menu is topmost/focused)
    if Input.is_left_clicked() then
        if over_title and is_topmost then
            self.is_dragging = true
            self.drag_offset_x = mx - self.x
            self.drag_offset_y = my - self.y
            bring_to_front(self)
        end
    end

    if Input.is_left_released() then
        if self.is_dragging then
            self.is_dragging = false
            self:save_all()
        end
    end

    if self.is_dragging then
        self.x = mx - self.drag_offset_x
        self.y = my - self.drag_offset_y
    end

    -- Update components only when not collapsed
    if not self.is_collapsed then
        for _, id in ipairs(self.component_order) do
            local component = self.components[id]
            if component then
                -- Component has focus if:
                -- 1. This menu is the topmost menu, OR
                -- 2. Mouse is not over this menu (so it's not blocking another menu)
                component._menu_has_focus = is_topmost
                if component:is_active() then
                    component:update()
                end
            end
        end
    end
end

-- Render menu and all components
function Menu:render()
    if not self.is_open then return end

    local display_height = self:get_display_height()

    -- Draw window
    Rendering.window(self.x, self.y, self.width, display_height)

    -- Draw title
    local title_height = constants.Settings.title_bar_height
    local collapse_indicator = self.is_collapsed and " [+]" or ""
    Rendering.text(
        self.x + self.width / 2,
        self.y + title_height / 2 - constants.Settings.default_font_size / 2,
        self.title .. collapse_indicator,
        constants.Colors.text_title,
        constants.Settings.default_font_size,
        true
    )

    -- Render components only when not collapsed
    if not self.is_collapsed then
        -- Pass 1: Render all normal components
        for _, id in ipairs(self.component_order) do
            local component = self.components[id]
            if component and component.visible then
                component:render()
            end
        end

        -- Pass 2: Render overlays (dropdowns, tooltips) on top
        for _, id in ipairs(self.component_order) do
            local component = self.components[id]
            if component and component.visible and component.render_overlay then
                component:render_overlay()
            end
        end
    end
end

return Menu
