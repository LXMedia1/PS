local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local Combobox = {}
setmetatable(Combobox, { __index = BaseComponent })
Combobox.__index = Combobox

function Combobox:new(options)
    options = options or {}
    options.height = options.height or 24

    local base = BaseComponent:new(constants.COMPONENT_TYPE.COMBOBOX, options)

    local combobox = setmetatable({
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

        items = options.items or {},
        selected_index = options.selected_index or options.default or 1,
        max_visible = options.max_visible or 5,
        item_height = options.item_height or 22
    }, Combobox)

    return combobox
end

function Combobox:render()
    if not self.visible then return end

    local combo_x = self.x
    local combo_width = self.width

    -- Draw label if provided
    if self.text and self.text ~= "" then
        Rendering.text(self.x, self.y + 4, self.text, constants.Colors.text)
        combo_x = self.x + 80
        combo_width = self.width - 80
    end

    -- Draw combobox
    local selected_text = self:get_selected_text()
    Rendering.combobox(combo_x, self.y, combo_width, self.height, selected_text, self.is_open, self.is_hovered)

    -- Draw dropdown if open
    if self.is_open then
        local dropdown_y = self.y + self.height
        local visible_count = math.min(#self.items, self.max_visible)
        local dropdown_height = visible_count * self.item_height

        -- Dropdown background
        Rendering.rect_filled(combo_x, dropdown_y, combo_width, dropdown_height, constants.Colors.component_bg)
        Rendering.rect(combo_x, dropdown_y, combo_width, dropdown_height, constants.Colors.border, 1)

        -- Draw items
        for i = 1, visible_count do
            local item_y = dropdown_y + (i - 1) * self.item_height
            local mx, my = Input.get_mouse_pos()
            local item_hovered = helpers.point_in_rect(mx, my, combo_x, item_y, combo_width, self.item_height)
            local item_selected = i == self.selected_index

            Rendering.dropdown_item(combo_x, item_y, combo_width, self.item_height, self.items[i], item_selected, item_hovered)
        end
    end
end

function Combobox:update()
    if not self:is_active() then return end

    local mx, my = Input.get_mouse_pos()

    local combo_x = self.x
    local combo_width = self.width
    if self.text and self.text ~= "" then
        combo_x = self.x + 80
        combo_width = self.width - 80
    end

    self.is_hovered = helpers.point_in_rect(mx, my, combo_x, self.y, combo_width, self.height)

    if Input.is_left_clicked() then
        if self.is_hovered then
            self.is_open = not self.is_open
        elseif self.is_open then
            -- Check if clicked on dropdown item
            local dropdown_y = self.y + self.height
            local visible_count = math.min(#self.items, self.max_visible)

            for i = 1, visible_count do
                local item_y = dropdown_y + (i - 1) * self.item_height
                if helpers.point_in_rect(mx, my, combo_x, item_y, combo_width, self.item_height) then
                    self:set_selected(i)
                    self.is_open = false
                    return
                end
            end

            self.is_open = false
        end
    end
end

function Combobox:get_selected_text()
    if self.selected_index > 0 and self.selected_index <= #self.items then
        return self.items[self.selected_index]
    end
    return ""
end

function Combobox:set_selected(index)
    if index >= 1 and index <= #self.items then
        local old_index = self.selected_index
        self.selected_index = index

        if old_index ~= index and self.on_change then
            self.on_change(self, index, self.items[index])
        end

        self:save_value()
    end
end

function Combobox:add_item(item)
    table.insert(self.items, item)
end

function Combobox:remove_item(index)
    table.remove(self.items, index)
    if self.selected_index > #self.items then
        self.selected_index = math.max(1, #self.items)
    end
end

function Combobox:set_items(items)
    self.items = items
    self.selected_index = math.min(self.selected_index, #items)
end

function Combobox:get_value()
    return self.selected_index
end

function Combobox:set_value(value)
    self.selected_index = helpers.clamp(value, 1, math.max(1, #self.items))
end

return Combobox
