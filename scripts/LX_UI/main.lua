local LX_UI = {}

-- Load core modules
local constants = require("utils/constants")
local helpers = require("utils/helpers")
local Input = require("core/input")
local Rendering = require("core/rendering")
local BaseComponent = require("core/base")
local Menu = require("core/menu")

-- Load components
local Label = require("components/label")
local Separator = require("components/separator")
local Header = require("components/header")
local Checkbox = require("components/checkbox")
local Slider = require("components/slider")
local Button = require("components/button")
local ProgressBar = require("components/progressbar")
local TextInput = require("components/textinput")
local Combobox = require("components/combobox")
local Keybind = require("components/keybind")
local ColorPicker = require("components/colorpicker")
local TreeNode = require("components/treenode")
local Listbox = require("components/listbox")

-- Export core
LX_UI.constants = constants
LX_UI.helpers = helpers
LX_UI.Input = Input
LX_UI.Rendering = Rendering
LX_UI.BaseComponent = BaseComponent
LX_UI.Menu = Menu

-- Export components
LX_UI.Label = Label
LX_UI.Separator = Separator
LX_UI.Header = Header
LX_UI.Checkbox = Checkbox
LX_UI.Slider = Slider
LX_UI.Button = Button
LX_UI.ProgressBar = ProgressBar
LX_UI.TextInput = TextInput
LX_UI.Combobox = Combobox
LX_UI.Keybind = Keybind
LX_UI.ColorPicker = ColorPicker
LX_UI.TreeNode = TreeNode
LX_UI.Listbox = Listbox

-- Export colors and settings for easy access
LX_UI.Colors = constants.Colors
LX_UI.Settings = constants.Settings

-- Helper to extend Menu with add_* methods
local MenuMeta = getmetatable(Menu) or {}
MenuMeta.__index = Menu

-- Add component methods to Menu
function Menu:add_label(text, x, y, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)

    local component = Label:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_separator(x, y, options)
    options = options or {}
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)

    local component = Separator:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_header(text, x, y, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)

    local component = Header:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_checkbox(text, x, y, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.default = default
    options.on_change = callback

    local component = Checkbox:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_slider(text, x, y, min, max, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.min = min
    options.max = max
    options.default = default
    options.on_change = callback

    local component = Slider:new(options)
    self:add_component(component)
    self:advance_y(component.height + 15)
    return component
end

function Menu:add_button(text, x, y, width, height, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = width or (self.width - constants.Settings.default_padding * 2)
    options.height = height or 25
    options.on_click = callback

    local component = Button:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_progressbar(text, x, y, value, max_value, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.value = value or 0
    options.max_value = max_value or 100

    local component = ProgressBar:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_textinput(text, x, y, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.default = default
    options.on_change = callback

    local component = TextInput:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_combobox(text, x, y, items, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.items = items
    options.default = default
    options.on_change = callback

    local component = Combobox:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_keybind(text, x, y, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.default = default
    options.on_change = callback

    local component = Keybind:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_colorpicker(text, x, y, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.default = default
    options.on_change = callback

    local component = ColorPicker:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_treenode(text, x, y, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.default = default
    options.on_change = callback

    local component = TreeNode:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

function Menu:add_listbox(text, x, y, items, default, callback, options)
    options = options or {}
    options.text = text
    options.x = (x or 0) + constants.Settings.default_padding
    options.y = (y or self:get_next_y())
    options.width = options.width or (self.width - constants.Settings.default_padding * 2)
    options.height = options.height or 100
    options.items = items
    options.default = default
    options.on_change = callback

    local component = Listbox:new(options)
    self:add_component(component)
    self:advance_y(component.height)
    return component
end

-- Version info
LX_UI.VERSION = "1.0.0"

-- Export to global namespace (so other plugins can access via _G.LX_UI)
_G.LX_UI = LX_UI

return LX_UI
