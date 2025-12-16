local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local Listbox = {}
setmetatable(Listbox, { __index = BaseComponent })
Listbox.__index = Listbox

function Listbox:new(options)
    options = options or {}
    options.height = options.height or 100

    local base = BaseComponent:new(constants.COMPONENT_TYPE.LISTBOX, options)

    local listbox = setmetatable({
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
        parent_menu = base.parent_menu,
        auto_save = base.auto_save,
        on_change = base.on_change,

        items = options.items or {},
        selected_index = options.selected_index or options.default or 0,
        multi_select = options.multi_select or false,
        selected_indices = options.selected_indices or {},
        item_height = options.item_height or 22,
        scroll_offset = 0
    }, Listbox)

    return listbox
end

function Listbox:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local list_y = abs_y
    local list_height = self.height

    -- Draw label if provided
    if self.text and self.text ~= "" then
        Rendering.text(abs_x, abs_y, self.text, constants.Colors.text)
        list_y = abs_y + 20
        list_height = self.height - 20
    end

    -- Background
    Rendering.rect_filled(abs_x, list_y, self.width, list_height, constants.Colors.component_bg, 2)
    Rendering.rect(abs_x, list_y, self.width, list_height, constants.Colors.border, 1, 2)

    -- Calculate visible items
    local visible_count = math.floor(list_height / self.item_height)
    local start_index = self.scroll_offset + 1
    local end_index = math.min(start_index + visible_count - 1, #self.items)

    local mx, my = Input.get_mouse_pos()

    -- Draw items
    for i = start_index, end_index do
        local item_y = list_y + (i - start_index) * self.item_height
        local is_selected = self:is_item_selected(i)
        local is_hovered = helpers.point_in_rect(mx, my, abs_x, item_y, self.width, self.item_height)

        Rendering.dropdown_item(abs_x, item_y, self.width, self.item_height, self.items[i], is_selected, is_hovered)
    end

    -- Draw scrollbar if needed
    if #self.items > visible_count then
        local scrollbar_height = (visible_count / #self.items) * list_height
        local scrollbar_y = list_y + (self.scroll_offset / (#self.items - visible_count)) * (list_height - scrollbar_height)

        Rendering.rect_filled(abs_x + self.width - 8, scrollbar_y, 6, scrollbar_height, constants.Colors.accent, 3)
    end
end

function Listbox:update()
    if not self:is_active() then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local mx, my = Input.get_mouse_pos()

    local list_y = abs_y
    local list_height = self.height
    if self.text and self.text ~= "" then
        list_y = abs_y + 20
        list_height = self.height - 20
    end

    self.is_hovered = helpers.point_in_rect(mx, my, abs_x, list_y, self.width, list_height)

    -- Handle click
    if self.is_hovered and Input.is_left_clicked() then
        local visible_count = math.floor(list_height / self.item_height)
        local start_index = self.scroll_offset + 1

        for i = start_index, math.min(start_index + visible_count - 1, #self.items) do
            local item_y = list_y + (i - start_index) * self.item_height
            if helpers.point_in_rect(mx, my, abs_x, item_y, self.width - 10, self.item_height) then
                self:select_item(i)
                break
            end
        end
    end

    -- Handle scroll (simplified - would need mouse wheel support)
end

function Listbox:is_item_selected(index)
    if self.multi_select then
        for _, idx in ipairs(self.selected_indices) do
            if idx == index then return true end
        end
        return false
    else
        return index == self.selected_index
    end
end

function Listbox:select_item(index)
    if self.multi_select then
        -- Toggle selection
        local found = false
        for i, idx in ipairs(self.selected_indices) do
            if idx == index then
                table.remove(self.selected_indices, i)
                found = true
                break
            end
        end
        if not found then
            table.insert(self.selected_indices, index)
        end
    else
        self.selected_index = index
    end

    if self.on_change then
        self.on_change(self, self:get_value(), self:get_selected_text())
    end

    self:save_value()
end

function Listbox:get_selected_text()
    if self.multi_select then
        local texts = {}
        for _, idx in ipairs(self.selected_indices) do
            if self.items[idx] then
                table.insert(texts, self.items[idx])
            end
        end
        return texts
    else
        return self.items[self.selected_index] or ""
    end
end

function Listbox:scroll_up()
    self.scroll_offset = math.max(0, self.scroll_offset - 1)
end

function Listbox:scroll_down()
    local list_height = self.height
    if self.text and self.text ~= "" then
        list_height = self.height - 20
    end
    local visible_count = math.floor(list_height / self.item_height)
    self.scroll_offset = math.min(math.max(0, #self.items - visible_count), self.scroll_offset + 1)
end

function Listbox:add_item(item)
    table.insert(self.items, item)
end

function Listbox:remove_item(index)
    table.remove(self.items, index)
end

function Listbox:set_items(items)
    self.items = items
    self.scroll_offset = 0
    self.selected_index = 0
    self.selected_indices = {}
end

function Listbox:get_value()
    if self.multi_select then
        return self.selected_indices
    else
        return self.selected_index
    end
end

function Listbox:set_value(value)
    if self.multi_select then
        self.selected_indices = value or {}
    else
        self.selected_index = value or 0
    end
end

return Listbox
