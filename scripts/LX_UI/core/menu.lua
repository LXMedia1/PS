local Menu = {}
Menu.__index = Menu

local constants = require("utils/constants")
local helpers = require("utils/helpers")
local Input = require("core/input")
local Rendering = require("core/rendering")

function Menu:new(title, width, height, save_key)
    local menu = setmetatable({
        -- Identity
        title = title or "Menu",
        save_key = save_key or "lx_ui_menu",

        -- Dimensions
        width = width or 300,
        height = height or 400,

        -- Position (centered by default)
        x = 100,
        y = 100,

        -- State
        is_open = true,
        is_dragging = false,
        drag_offset_x = 0,
        drag_offset_y = 0,

        -- Components
        components = {},
        component_order = {},

        -- Auto Y positioning
        next_y = constants.Settings.title_bar_height + constants.Settings.default_padding,

        -- Saved data cache
        saved_data = {}
    }, Menu)

    -- Try to load saved position and data
    menu:load_all()

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
        components = self.saved_data
    }

    local json_str = self:encode_json(data)
    if json_str then
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

-- Update menu and all components
function Menu:update()
    if not self.is_open then return end

    Input.update()

    local mx, my = Input.get_mouse_pos()
    local title_height = constants.Settings.title_bar_height

    -- Handle window dragging
    if Input.is_left_clicked() then
        if helpers.point_in_rect(mx, my, self.x, self.y, self.width, title_height) then
            self.is_dragging = true
            self.drag_offset_x = mx - self.x
            self.drag_offset_y = my - self.y
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

    -- Update components in order
    for _, id in ipairs(self.component_order) do
        local component = self.components[id]
        if component and component:is_active() then
            component:update()
        end
    end
end

-- Render menu and all components
function Menu:render()
    if not self.is_open then return end

    -- Draw window
    Rendering.window(self.x, self.y, self.width, self.height)

    -- Draw title
    local title_height = constants.Settings.title_bar_height
    Rendering.text(
        self.x + self.width / 2,
        self.y + title_height / 2 - constants.Settings.default_font_size / 2,
        self.title,
        constants.Colors.text_title,
        constants.Settings.default_font_size,
        true
    )

    -- Render components in order
    for _, id in ipairs(self.component_order) do
        local component = self.components[id]
        if component and component.visible then
            component:render()
        end
    end
end

return Menu
