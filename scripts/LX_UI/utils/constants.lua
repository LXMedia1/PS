local constants = {}

-- External imports
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")

constants.color = color
constants.vec2 = vec2

-- Virtual Key Codes
constants.VK = {
    LBUTTON = 0x01,
    RBUTTON = 0x02,
    MBUTTON = 0x04,
    BACK = 0x08,
    TAB = 0x09,
    RETURN = 0x0D,
    SHIFT = 0x10,
    CONTROL = 0x11,
    ALT = 0x12,
    ESCAPE = 0x1B,
    SPACE = 0x20,
    END_KEY = 0x23,
    HOME = 0x24,
    LEFT = 0x25,
    UP = 0x26,
    RIGHT = 0x27,
    DOWN = 0x28,
    DELETE = 0x2E
}

-- Settings
constants.Settings = {
    debug_mode = false,
    auto_save_enabled = true,
    default_font_size = 12,
    default_spacing = 5,
    default_padding = 10,
    title_bar_height = 25,
    component_height = 20,
    slider_handle_width = 10
}

-- Text Alignment
constants.TEXT_ALIGN = {
    LEFT = 0,
    CENTER = 1,
    RIGHT = 2
}

-- Colors (Clean Dark Theme)
constants.Colors = {
    -- Backgrounds
    window_bg = color.new(25, 25, 25, 245),
    title_bar = color.new(35, 35, 35, 255),
    component_bg = color.new(45, 45, 45, 255),

    -- Borders
    border = color.new(60, 60, 60, 255),
    border_hover = color.new(80, 80, 80, 255),
    border_focus = color.new(0, 150, 255, 255),

    -- Text
    text = color.new(220, 220, 220, 255),
    text_dim = color.new(150, 150, 150, 255),
    text_disabled = color.new(100, 100, 100, 255),
    text_title = color.new(255, 255, 255, 255),

    -- Accent
    accent = color.new(0, 150, 255, 255),
    accent_hover = color.new(30, 170, 255, 255),
    accent_pressed = color.new(0, 120, 220, 255),

    -- States
    hover = color.new(55, 55, 55, 255),
    pressed = color.new(65, 65, 65, 255),
    selected = color.new(0, 100, 180, 255),

    -- Semantic
    success = color.new(50, 200, 100, 255),
    warning = color.new(255, 180, 50, 255),
    error = color.new(255, 80, 80, 255),

    -- Checkbox/Toggle
    checkbox_bg = color.new(45, 45, 45, 255),
    checkbox_check = color.new(0, 150, 255, 255),

    -- Slider
    slider_track = color.new(45, 45, 45, 255),
    slider_fill = color.new(0, 150, 255, 255),
    slider_handle = color.new(220, 220, 220, 255),

    -- Separator
    separator = color.new(60, 60, 60, 255),

    -- Progress
    progress_bg = color.new(45, 45, 45, 255),
    progress_fill = color.new(0, 150, 255, 255)
}

-- Component Types
constants.COMPONENT_TYPE = {
    CHECKBOX = "checkbox",
    SLIDER = "slider",
    BUTTON = "button",
    LABEL = "label",
    TEXTINPUT = "textinput",
    COMBOBOX = "combobox",
    KEYBIND = "keybind",
    COLORPICKER = "colorpicker",
    HEADER = "header",
    TREENODE = "treenode",
    LISTBOX = "listbox",
    PROGRESSBAR = "progressbar",
    SEPARATOR = "separator"
}

return constants
