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

        items = {},
        selected_index = options.selected_index or options.default or 0,
        multi_select = options.multi_select or false,
        selected_indices = options.selected_indices or {},
        item_height = options.item_height or 16,
        scroll_offset = 0
    }, Listbox)

    -- Copy items to avoid reference issues
    if options.items then
        for i, item in ipairs(options.items) do
            listbox.items[i] = item
        end
    end

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

    -- Store for update
    self._list_y = list_y
    self._list_height = list_height

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
        local is_hovered = helpers.point_in_rect(mx, my, abs_x, item_y, self.width - 12, self.item_height)

        Rendering.dropdown_item(abs_x, item_y, self.width - 12, self.item_height, self.items[i], is_selected, is_hovered)
    end

    -- Draw scrollbar area and buttons if needed
    if #self.items > visible_count then
        local scrollbar_x = abs_x + self.width - 10
        local btn_size = 12

        -- Scrollbar track
        Rendering.rect_filled(scrollbar_x, list_y, 10, list_height, constants.Colors.component_bg, 2)

        -- Up button
        local up_hovered = helpers.point_in_rect(mx, my, scrollbar_x, list_y, 10, btn_size)
        Rendering.rect_filled(scrollbar_x, list_y, 10, btn_size, up_hovered and constants.Colors.hover or constants.Colors.border, 2)
        Rendering.text(scrollbar_x + 3, list_y + 1, "^", constants.Colors.text, 10)

        -- Down button
        local down_hovered = helpers.point_in_rect(mx, my, scrollbar_x, list_y + list_height - btn_size, 10, btn_size)
        Rendering.rect_filled(scrollbar_x, list_y + list_height - btn_size, 10, btn_size, down_hovered and constants.Colors.hover or constants.Colors.border, 2)
        Rendering.text(scrollbar_x + 3, list_y + list_height - btn_size + 1, "v", constants.Colors.text, 10)

        -- Scrollbar thumb
        local track_height = list_height - btn_size * 2
        local thumb_height = math.max(20, (visible_count / #self.items) * track_height)
        local max_scroll = #self.items - visible_count
        local thumb_y = list_y + btn_size + (self.scroll_offset / max_scroll) * (track_height - thumb_height)

        self._thumb_y = thumb_y
        self._thumb_height = thumb_height
        self._scrollbar_x = scrollbar_x
        self._track_y = list_y + btn_size
        self._track_height = track_height

        Rendering.rect_filled(scrollbar_x + 1, thumb_y, 8, thumb_height, constants.Colors.accent, 3)
    end
end

function Listbox:update()
    if not self:is_active() then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local mx, my = Input.get_mouse_pos()

    local list_y = self._list_y or abs_y
    local list_height = self._list_height or self.height

    -- Don't respond to new input if menu doesn't have focus
    -- But continue handling if already dragging thumb
    if not self:menu_has_focus() and not self._dragging_thumb then
        self.is_hovered = false
        return
    end

    self.is_hovered = helpers.point_in_rect(mx, my, abs_x, list_y, self.width, list_height)

    local visible_count = math.floor(list_height / self.item_height)
    local max_scroll = math.max(0, #self.items - visible_count)
    local btn_size = 12

    -- Handle scrollbar interactions (only if menu has focus)
    if #self.items > visible_count then
        local scrollbar_x = abs_x + self.width - 10

        -- Up button click
        if Input.is_left_clicked() and helpers.point_in_rect(mx, my, scrollbar_x, list_y, 10, btn_size) then
            self.scroll_offset = math.max(0, self.scroll_offset - 1)
            return
        end

        -- Down button click
        if Input.is_left_clicked() and helpers.point_in_rect(mx, my, scrollbar_x, list_y + list_height - btn_size, 10, btn_size) then
            self.scroll_offset = math.min(max_scroll, self.scroll_offset + 1)
            return
        end

        -- Scrollbar thumb drag
        if Input.is_left_clicked() and self._thumb_y and helpers.point_in_rect(mx, my, scrollbar_x, self._thumb_y, 10, self._thumb_height) then
            self._dragging_thumb = true
            self._drag_start_y = my
            self._drag_start_offset = self.scroll_offset
        end

        if self._dragging_thumb then
            if Input.is_left_down() then
                local drag_delta = my - self._drag_start_y
                local scroll_per_pixel = max_scroll / (self._track_height - self._thumb_height)
                local new_offset = self._drag_start_offset + math.floor(drag_delta * scroll_per_pixel)
                self.scroll_offset = math.max(0, math.min(max_scroll, new_offset))
            else
                self._dragging_thumb = false
            end
            return
        end

        -- Click on track to jump
        if Input.is_left_clicked() and self._track_y and helpers.point_in_rect(mx, my, scrollbar_x, self._track_y, 10, self._track_height) then
            local click_ratio = (my - self._track_y) / self._track_height
            self.scroll_offset = math.floor(click_ratio * max_scroll)
            return
        end
    end

    -- Handle item click
    if Input.is_left_clicked() and helpers.point_in_rect(mx, my, abs_x, list_y, self.width - 12, list_height) then
        local start_index = self.scroll_offset + 1

        for i = start_index, math.min(start_index + visible_count - 1, #self.items) do
            local item_y = list_y + (i - start_index) * self.item_height
            if helpers.point_in_rect(mx, my, abs_x, item_y, self.width - 12, self.item_height) then
                self:select_item(i)
                break
            end
        end
    end

    -- Arrow keys when hovered
    if self.is_hovered then
        if Input.is_key_just_pressed(constants.VK.UP) then
            self.scroll_offset = math.max(0, self.scroll_offset - 1)
        end
        if Input.is_key_just_pressed(constants.VK.DOWN) then
            self.scroll_offset = math.min(max_scroll, self.scroll_offset + 1)
        end
    end
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
    -- Make a copy of items to avoid reference issues
    self.items = {}
    if items then
        for i, item in ipairs(items) do
            self.items[i] = item
        end
    end
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
