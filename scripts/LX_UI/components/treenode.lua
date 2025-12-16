local BaseComponent = require("core/base")
local Rendering = require("core/rendering")
local Input = require("core/input")
local constants = require("utils/constants")
local helpers = require("utils/helpers")

local TreeNode = {}
setmetatable(TreeNode, { __index = BaseComponent })
TreeNode.__index = TreeNode

function TreeNode:new(options)
    options = options or {}
    options.height = options.height or 22

    local base = BaseComponent:new(constants.COMPONENT_TYPE.TREENODE, options)

    local treenode = setmetatable({
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

        is_expanded = options.is_expanded or options.default or false,
        children = {},
        indent = options.indent or 0,
        indent_size = options.indent_size or 20
    }, TreeNode)

    return treenode
end

function TreeNode:render()
    if not self.visible then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local mx, my = Input.get_mouse_pos()
    local actual_x = abs_x + (self.indent * self.indent_size)
    self.is_hovered = helpers.point_in_rect(mx, my, actual_x, abs_y, self.width - (self.indent * self.indent_size), self.height)

    local bg_col = self.is_hovered and constants.Colors.hover or nil
    if bg_col then
        Rendering.rect_filled(actual_x, abs_y, self.width - (self.indent * self.indent_size), self.height, bg_col, 2)
    end

    -- Draw expand/collapse indicator
    local has_children = #self.children > 0
    if has_children then
        local indicator = self.is_expanded and "v" or ">"
        Rendering.text(actual_x + 4, abs_y + 4, indicator, constants.Colors.text_dim)
    end

    -- Draw text
    local text_x = actual_x + (has_children and 20 or 8)
    Rendering.text(text_x, abs_y + 4, self.text, constants.Colors.text)

    -- Render children if expanded
    if self.is_expanded then
        local child_y = abs_y + self.height
        for _, child in ipairs(self.children) do
            child.y = child_y - (self.parent_menu and self.parent_menu.y or 0)
            child:render()
            child_y = child_y + child:get_total_height()
        end
    end
end

function TreeNode:update()
    if not self:is_active() then return end

    local abs_x = self:get_abs_x()
    local abs_y = self:get_abs_y()
    local mx, my = Input.get_mouse_pos()
    local actual_x = abs_x + (self.indent * self.indent_size)

    -- Don't respond to new input if menu doesn't have focus
    if not self:menu_has_focus() then
        self.is_hovered = false
        return
    end

    self.is_hovered = helpers.point_in_rect(mx, my, actual_x, abs_y, self.width - (self.indent * self.indent_size), self.height)

    if self.is_hovered and Input.is_left_clicked() then
        self:toggle()
    end

    -- Update children if expanded
    if self.is_expanded then
        for _, child in ipairs(self.children) do
            child:update()
        end
    end
end

function TreeNode:toggle()
    self.is_expanded = not self.is_expanded

    if self.on_change then
        self.on_change(self, self.is_expanded)
    end

    self:save_value()
end

function TreeNode:expand()
    self.is_expanded = true
end

function TreeNode:collapse()
    self.is_expanded = false
end

function TreeNode:add_child(child)
    child.indent = self.indent + 1
    child.x = self.x
    child.width = self.width
    child.parent_menu = self.parent_menu
    table.insert(self.children, child)
    return child
end

function TreeNode:remove_child(index)
    table.remove(self.children, index)
end

function TreeNode:get_total_height()
    local total = self.height
    if self.is_expanded then
        for _, child in ipairs(self.children) do
            total = total + child:get_total_height()
        end
    end
    return total
end

function TreeNode:get_value()
    return self.is_expanded
end

function TreeNode:set_value(value)
    self.is_expanded = value == true
end

return TreeNode
