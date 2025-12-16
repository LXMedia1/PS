local Rendering = {}

local constants = require("utils/constants")

local vec2 = constants.vec2
local color = constants.color

-- Draw filled rectangle
function Rendering.rect_filled(x, y, w, h, col, radius)
    radius = radius or 0
    core.graphics.rect_2d_filled(
        vec2.new(x, y),
        w,
        h,
        col,
        radius
    )
end

-- Draw rectangle outline
function Rendering.rect(x, y, w, h, col, thickness, radius)
    thickness = thickness or 1
    radius = radius or 0
    core.graphics.rect_2d(
        vec2.new(x, y),
        w,
        h,
        col,
        thickness,
        radius
    )
end

-- Draw text
function Rendering.text(x, y, text_str, col, size, centered)
    size = size or constants.Settings.default_font_size
    centered = centered or false
    core.graphics.text_2d(
        text_str,
        vec2.new(x, y),
        size,
        col,
        centered
    )
end

-- Draw line
function Rendering.line(x1, y1, x2, y2, col, thickness)
    thickness = thickness or 1
    core.graphics.line_2d(
        vec2.new(x1, y1),
        vec2.new(x2, y2),
        col,
        thickness
    )
end

-- Draw window background with border
function Rendering.window(x, y, w, h, title_height)
    title_height = title_height or constants.Settings.title_bar_height

    -- Window background
    Rendering.rect_filled(x, y, w, h, constants.Colors.window_bg, 4)

    -- Title bar
    Rendering.rect_filled(x, y, w, title_height, constants.Colors.title_bar, 4)

    -- Border
    Rendering.rect(x, y, w, h, constants.Colors.border, 1, 4)
end

-- Draw button
function Rendering.button(x, y, w, h, text_str, is_hovered, is_pressed, style)
    style = style or "default"
    local bg_col, text_col, border_col

    if style == "primary" then
        -- Accent colored button
        bg_col = constants.Colors.accent
        text_col = constants.Colors.text_title
        border_col = constants.Colors.accent
        if is_pressed then
            bg_col = constants.Colors.accent_pressed
        elseif is_hovered then
            bg_col = constants.Colors.accent_hover
        end
    else
        -- Default gray button
        bg_col = constants.Colors.component_bg
        text_col = constants.Colors.text
        border_col = constants.Colors.border
        if is_pressed then
            bg_col = constants.Colors.pressed
        elseif is_hovered then
            bg_col = constants.Colors.hover
        end
    end

    Rendering.rect_filled(x, y, w, h, bg_col, 3)
    Rendering.rect(x, y, w, h, border_col, 1, 3)

    -- Center text
    local text_x = x + w / 2
    local text_y = y + h / 2 - constants.Settings.default_font_size / 2
    Rendering.text(text_x, text_y, text_str, text_col, nil, true)
end

-- Draw checkbox
function Rendering.checkbox(x, y, size, checked, is_hovered)
    size = size or 16

    local bg_col = constants.Colors.checkbox_bg
    if is_hovered then
        bg_col = constants.Colors.hover
    end

    Rendering.rect_filled(x, y, size, size, bg_col, 2)
    Rendering.rect(x, y, size, size, constants.Colors.border, 1, 2)

    if checked then
        local padding = 3
        Rendering.rect_filled(
            x + padding, y + padding,
            size - padding * 2, size - padding * 2,
            constants.Colors.checkbox_check, 1
        )
    end
end

-- Draw slider
function Rendering.slider(x, y, w, h, percent, is_hovered, is_dragging)
    -- Track background
    Rendering.rect_filled(x, y, w, h, constants.Colors.slider_track, 3)

    -- Fill
    local fill_width = w * percent
    if fill_width > 0 then
        Rendering.rect_filled(x, y, fill_width, h, constants.Colors.slider_fill, 3)
    end

    -- Handle
    local handle_w = constants.Settings.slider_handle_width
    local handle_x = x + fill_width - handle_w / 2
    handle_x = math.max(x, math.min(handle_x, x + w - handle_w))

    local handle_col = constants.Colors.slider_handle
    if is_dragging then
        handle_col = constants.Colors.accent
    elseif is_hovered then
        handle_col = constants.Colors.accent_hover
    end

    Rendering.rect_filled(handle_x, y - 2, handle_w, h + 4, handle_col, 2)

    -- Border
    Rendering.rect(x, y, w, h, constants.Colors.border, 1, 3)
end

-- Draw progress bar
function Rendering.progress_bar(x, y, w, h, percent, col)
    col = col or constants.Colors.progress_fill

    -- Background
    Rendering.rect_filled(x, y, w, h, constants.Colors.progress_bg, 2)

    -- Fill
    local fill_width = w * percent
    if fill_width > 0 then
        Rendering.rect_filled(x, y, fill_width, h, col, 2)
    end

    -- Border
    Rendering.rect(x, y, w, h, constants.Colors.border, 1, 2)
end

-- Draw separator line
function Rendering.separator(x, y, w)
    Rendering.line(x, y, x + w, y, constants.Colors.separator, 1)
end

-- Draw text input field
function Rendering.text_input(x, y, w, h, text_str, is_focused, is_hovered)
    local bg_col = constants.Colors.component_bg
    local border_col = constants.Colors.border

    if is_focused then
        border_col = constants.Colors.border_focus
    elseif is_hovered then
        border_col = constants.Colors.border_hover
    end

    Rendering.rect_filled(x, y, w, h, bg_col, 2)
    Rendering.rect(x, y, w, h, border_col, 1, 2)

    -- Text with padding
    local padding = 5
    Rendering.text(x + padding, y + (h - constants.Settings.default_font_size) / 2,
        text_str, constants.Colors.text)
end

-- Draw combobox
function Rendering.combobox(x, y, w, h, text_str, is_open, is_hovered)
    local bg_col = constants.Colors.component_bg
    if is_hovered then
        bg_col = constants.Colors.hover
    end

    Rendering.rect_filled(x, y, w, h, bg_col, 2)
    Rendering.rect(x, y, w, h, constants.Colors.border, 1, 2)

    -- Text
    local padding = 5
    Rendering.text(x + padding, y + (h - constants.Settings.default_font_size) / 2,
        text_str, constants.Colors.text)

    -- Arrow indicator
    local arrow = is_open and "^" or "v"
    Rendering.text(x + w - 15, y + (h - constants.Settings.default_font_size) / 2,
        arrow, constants.Colors.text_dim)
end

-- Draw dropdown item
function Rendering.dropdown_item(x, y, w, h, text_str, is_selected, is_hovered)
    local bg_col = constants.Colors.component_bg
    if is_selected then
        bg_col = constants.Colors.selected
    elseif is_hovered then
        bg_col = constants.Colors.hover
    end

    Rendering.rect_filled(x, y, w, h, bg_col)

    local padding = 5
    Rendering.text(x + padding, y + (h - constants.Settings.default_font_size) / 2,
        text_str, constants.Colors.text)
end

return Rendering
