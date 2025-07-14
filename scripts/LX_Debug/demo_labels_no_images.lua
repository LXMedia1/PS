-- ==================== AWESOME LABELS DEMO (NO IMAGES VERSION) ====================

-- Import the LxCommon system
local gui = LxCommon.Gui.register("Label Demo", 500, 450)

-- Color definitions for demo
local red = require("common/color").new(255, 100, 100, 255)
local green = require("common/color").new(100, 255, 100, 255)
local blue = require("common/color").new(100, 150, 255, 255)
local yellow = require("common/color").new(255, 255, 100, 255)
local purple = require("common/color").new(200, 100, 255, 255)
local cyan = require("common/color").new(100, 255, 255, 255)
local white = require("common/color").white(255)

-- Demo counter for dynamic content
local demo_counter = 0
local demo_timer = 0

-- ==================== BASIC LABELS ====================
gui:AddLabel("AWESOME LABELS SHOWCASE", 250, 10, {
    font_size = 16,
    color = yellow,
    align = "center",
    background = true,
    bg_color = require("common/color").new(50, 50, 80, 200),
    animation = "glow",
    animation_speed = 1.5
})

-- ==================== ANIMATION SHOWCASE ====================
gui:AddLabel("Animation Effects:", 20, 50, {color = cyan, font_size = 14})

gui:AddLabel("Pulse Effect", 30, 75, {
    color = red,
    animation = "pulse",
    animation_speed = 2.5
})

gui:AddLabel("Fade Effect", 140, 75, {
    color = green,
    animation = "fade", 
    animation_speed = 2.0
})

gui:AddLabel("Rainbow Magic!", 250, 75, {
    color = purple,
    animation = "rainbow",
    animation_speed = 2.5
})

gui:AddLabel("Glowing Text", 380, 75, {
    color = yellow,
    animation = "glow",
    animation_speed = 2.5
})

-- ==================== INTERACTIVE LABELS ====================
gui:AddLabel("Interactive Labels:", 20, 110, {color = cyan, font_size = 14})

local click_count = 0
local click_label = gui:AddLabel("Click Me! (0)", 30, 135, {
    color = yellow,
    background = true,
    bg_color = require("common/color").new(80, 80, 0, 150),
    clickable = true,
    hover_color = require("common/color").new(255, 255, 255, 255)
})

-- Set the click callback after the label is created
click_label.click_callback = function()
    click_count = click_count + 1
    -- Update the label text directly
    click_label.text = "Click Me! (" .. click_count .. ")"
    core.log("Label clicked! Count: " .. click_count)
end

local hover_label = gui:AddLabel("Hover Over Me!", 200, 135, {
    color = blue,
    clickable = true,
    hover_color = require("common/color").new(255, 200, 100, 255),
    animation = "pulse",
    animation_speed = 3.0
})

-- Set the click callback after the label is created
hover_label.click_callback = function()
    core.log("Hover label clicked!")
    hover_label.text = "Clicked! Hover again!"
end

-- ==================== VISUAL EFFECTS ====================
gui:AddLabel("Visual Effects:", 20, 170, {color = cyan, font_size = 14})

gui:AddLabel("With Shadow", 30, 195, {
    color = white,
    shadow = true,
    shadow_color = require("common/color").new(0, 0, 0, 180),
    shadow_offset = {x = 3, y = 3},
    font_size = 13
})

gui:AddLabel("Background Box", 140, 195, {
    color = green,
    background = true,
    bg_color = require("common/color").new(0, 80, 0, 180),
    bg_padding = 8
})

gui:AddLabel("Big Font!", 280, 195, {
    color = red,
    font_size = 18,
    outline = true,
    animation = "glow"
})

-- ==================== ALIGNMENT SHOWCASE ====================
gui:AddLabel("Text Alignment:", 20, 230, {color = cyan, font_size = 14})

gui:AddLabel("Left Aligned", 50, 255, {
    color = white,
    align = "left",
    background = true,
    bg_color = require("common/color").new(40, 40, 40, 150)
})

gui:AddLabel("Center Aligned", 200, 255, {
    color = white,
    align = "center", 
    background = true,
    bg_color = require("common/color").new(40, 40, 40, 150)
})

gui:AddLabel("Right Aligned", 380, 255, {
    color = white,
    align = "right",
    background = true,
    bg_color = require("common/color").new(40, 40, 40, 150)
})

-- ==================== DYNAMIC CONTENT ====================
gui:AddLabel("Dynamic Content:", 20, 290, {color = cyan, font_size = 14})

local dynamic_label = gui:AddLabel("Time: 00:00:00", 30, 315, {
    color = green,
    background = true,
    bg_color = require("common/color").new(0, 40, 0, 150),
    dynamic = true,
    update_callback = function()
        demo_timer = demo_timer + (1/60) -- Assume 60 FPS
        local hours = math.floor(demo_timer / 3600)
        local minutes = math.floor((demo_timer % 3600) / 60)
        local seconds = math.floor(demo_timer % 60)
        return string.format("Time: %02d:%02d:%02d", hours, minutes, seconds)
    end
})

local counter_label = gui:AddLabel("Counter: 0", 200, 315, {
    color = yellow,
    animation = "pulse",
    animation_speed = 1.0,
    dynamic = true,
    update_callback = function()
        demo_counter = demo_counter + 1
        return string.format("Counter: %d", demo_counter)
    end
})

local fps_label = gui:AddLabel("FPS: 60", 320, 315, {
    color = cyan,
    outline = true,
    dynamic = true,
    update_callback = function()
        -- Simple FPS approximation
        return string.format("FPS: %d", math.random(58, 62))
    end
})

-- ==================== SPECIAL SHOWCASE ====================
gui:AddLabel("Special Effects:", 20, 350, {color = cyan, font_size = 14})

gui:AddLabel("EPIC TEXT", 250, 375, {
    color = require("common/color").new(255, 150, 0, 255),
    font_size = 16,
    align = "center",
    animation = "rainbow",
    animation_speed = 2.0,
    shadow = true,
    shadow_color = require("common/color").new(100, 0, 0, 200),
    shadow_offset = {x = 2, y = 2},
    background = true,
    bg_color = require("common/color").new(80, 20, 0, 180)
})

core.log("Label Demo GUI loaded successfully - Showcasing awesome label features!") 