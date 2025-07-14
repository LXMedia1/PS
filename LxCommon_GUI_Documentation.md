# Work in Progress

# LxCommon GUI System Documentation

## Overview

The LxCommon GUI system is a powerful, modular framework for creating interactive user interfaces in Lua-based game plugins. It provides a complete windowing system with direct rendering capabilities, input handling, and a rich set of UI components.

## Architecture

### Core Components

The system is built with a modular architecture:

```
Lx_Common/
├── main.lua              # Main entry point and global exports
├── gui/
│   ├── elements/
│   │   └── menu.lua      # Menu class with all UI components
│   ├── functions/
│   │   ├── input.lua     # Mouse and keyboard input handling
│   │   └── rendering.lua # Direct rendering functions
│   └── utils/
│       ├── constants.lua # Global constants and state
│       └── helpers.lua   # Utility functions
```

### Key Features

- **Direct Rendering**: Uses `core.graphics` functions for drawing without traditional windows
- **Input Blocking**: Prevents click-through to the game world when interacting with GUIs
- **Selection Bar**: Top navigation bar for switching between multiple GUIs
- **Modular Design**: Clean separation of concerns with reusable components
- **Persistent Settings**: Automatic saving/loading of component states

### Input Blocking Behavior

The GUI system provides **partial input blocking**:

**What IS blocked:**
- **Movement**: Character movement is disabled when GUI elements are focused
- **Mouse clicks**: Mouse interactions are blocked within GUI areas through invisible blocking windows
- **Mouse hover**: GUI areas prevent mouse events from reaching the game world

**What is NOT blocked:**
- Keyboard hotkeys and shortcuts
- Spell casting and ability usage
- Other game actions that don't involve movement or mouse clicks

**Note:** The system uses `LxCommon.isInputBlocked()` to provide status information, but developers should implement their own input blocking logic for non-mouse/non-movement inputs when needed.

## Getting Started

### Basic Usage

```lua
-- Create a new GUI
local my_gui = LxCommon.Gui.register("My GUI", 400, 300)

-- Set up the render callback
my_gui:set_render_callback(function()
    -- Add your UI components here
end)
```

### Global Access

The system exports several global functions:

```lua
-- Main registration function
LxCommon.Gui.register(name, width, height)

-- Legacy support
LxCommon.registerGui(name, width, height)

-- Check if input is blocked
LxCommon.isInputBlocked()

-- Direct access to Menu class
LxCommon.Menu
```

**Note:** `LxCommon.isInputBlocked()` returns `true` when the GUI system is blocking input (mouse over GUI areas, text input focused, or keybind listening). Use this in your own logic to prevent processing game actions when the GUI is active.
```

## Menu Components

### Labels

Advanced text rendering with multiple effects and features.

```lua
my_gui:AddLabel(text, x, y, options)
```

**Basic Usage:**
```lua
my_gui:AddLabel("Hello World", 10, 10)
```

**Advanced Options:**
```lua
my_gui:AddLabel("Animated Text", 10, 10, {
    color = color.new(255, 255, 0, 255),
    font_size = 16,
    animation = "pulse",         -- "none", "pulse", "fade", "rainbow", "glow"
    animation_speed = 2.0,
    background = true,
    bg_color = color.new(20, 20, 30, 180),
    clickable = true,
    click_callback = function() print("Label clicked!") end,
    shadow = true,
    align = "center"            -- "left", "center", "right"
})
```

**Dynamic Labels:**
```lua
local health_label = my_gui:AddLabel("Health: 100", 10, 10, {
    dynamic = true,
    update_callback = function()
        return "Health: " .. tostring(player.health)
    end
})
```

### Buttons

Interactive buttons with customizable appearance and callbacks.

```lua
my_gui:AddButton(text, x, y, width, height, callback, bg_color, text_color, border_color)
```

**Example:**
```lua
my_gui:AddButton("Click Me", 10, 50, 100, 30, function()
    print("Button clicked!")
end, color.new(60, 90, 140, 200), color.white(255))
```

### Checkboxes

Boolean toggles with persistent state.

```lua
my_gui:AddCheckbox(text, x, y, default_state, callback, options)
```

**Example:**
```lua
local checkbox = my_gui:AddCheckbox("Enable Feature", 10, 90, true, function(state)
    print("Checkbox state:", state)
end)

-- Get current state
local is_checked = my_gui:GetCheckboxValue(checkbox)
```

### Sliders

#### Integer Sliders
```lua
my_gui:AddSliderInt(text, x, y, min_value, max_value, default_value, callback, options)
```

**Example:**
```lua
local damage_slider = my_gui:AddSliderInt("Damage", 10, 130, 1, 100, 50, function(value)
    print("Damage set to:", value)
end)

-- Get current value
local current_damage = my_gui:GetSliderIntValue(damage_slider)
```

#### Float Sliders
```lua
my_gui:AddSliderFloat(text, x, y, min_value, max_value, default_value, callback, options)
```

**Example:**
```lua
local speed_slider = my_gui:AddSliderFloat("Speed", 10, 170, 0.1, 2.0, 1.0, function(value)
    print("Speed set to:", value)
end)
```

### Comboboxes

Dropdown selection lists.

```lua
my_gui:AddCombobox(text, x, y, items, default_index, callback, options)
```

**Example:**
```lua
local class_combo = my_gui:AddCombobox("Class", 10, 210, 
    {"Warrior", "Mage", "Archer"}, 1, function(index)
        print("Selected class:", index)
    end)
```

### Keybinds

Interactive key assignment with listening mode.

```lua
my_gui:AddKeybind(text, x, y, default_key, callback, options)
```

**Example:**
```lua
local hotkey = my_gui:AddKeybind("Hotkey", 10, 250, 0x70, function(key_code) -- F1
    print("Hotkey set to:", key_code)
end)

-- Get current key
local current_key = my_gui:GetKeybindCurrentKey(hotkey)
```

**Features:**
- Click to enter listening mode (blue highlight)
- Press any key to assign
- Clear button (X) to remove keybind
- Automatic key name display (F1, Space, etc.)
- Input blocking while listening
- 5-second timeout protection

### Color Pickers

Interactive color selection.

```lua
my_gui:AddColorPicker(text, x, y, default_color, callback, options)
```

**Example:**
```lua
local color_picker = my_gui:AddColorPicker("Text Color", 10, 290, color.white(255), function(new_color)
    print("Color changed to:", new_color.r, new_color.g, new_color.b)
end)
```

### Text Inputs

Advanced text input fields with full keyboard support.

```lua
my_gui:AddTextInput(text, x, y, default_text, callback, options)
```

**Example:**
```lua
local name_input = my_gui:AddTextInput("Player Name", 10, 330, "Enter name...", function(text)
    print("Name changed to:", text)
end, {
    placeholder = "Type your name here",
    width = 200,
    save_input = true
})
```

**Features:**
- Automatic input blocking when focused
- Double-click to select all text
- Full keyboard support (arrows, home/end, delete, backspace)
- Key repeat functionality
- Visual text selection
- Placeholder text support
- Persistent input across sessions

### Headers

Styled section headers.

```lua
my_gui:AddHeader(text, x, y, options)
```

**Example:**
```lua
my_gui:AddHeader("Settings", 10, 10, {
    text_color = color.yellow(255)
})
```

### Tree Nodes

Collapsible sections with nested content.

```lua
my_gui:AddTreeNode(text, x, y, render_callback, options)
```

**Example:**
```lua
my_gui:AddTreeNode("Advanced Options", 10, 50, function()
    -- Render content when expanded
    my_gui:AddLabel("Nested content", 30, 80)
end)
```

### Key Checkboxes

Checkboxes with associated keybinds.

```lua
my_gui:AddKeyCheckbox(text, x, y, default_key, default_state, callback, options)
```

**Example:**
```lua
local toggle_feature = my_gui:AddKeyCheckbox("Auto Attack", 10, 120, 0x41, true, function(state) -- 'A' key
    print("Auto Attack:", state)
end)
```



## Advanced Features

### Animation System

Labels support various animation effects:

- **pulse**: Smooth size pulsing
- **fade**: Opacity fading in/out
- **rainbow**: Color cycling through spectrum
- **glow**: Intensity glow effect

### Input Blocking

The system automatically blocks game input when:
- Mouse is over GUI areas
- Text inputs are focused
- Keybinds are in listening mode

### Collision Detection

All interactive elements include precise mouse collision detection with hover effects.

### State Management

Components automatically save/load their states using unique IDs, providing persistence across sessions.

### Selection Bar

The top navigation bar allows users to:
- Toggle individual GUIs on/off
- Switch between multiple open GUIs
- Enable/disable the entire GUI system

## Helper Functions

### Component Value Retrieval

```lua
-- Get current values from components
my_gui:GetCheckboxValue(checkbox_info)
my_gui:GetSliderIntValue(slider_info)
my_gui:GetSliderFloatValue(slider_info)
my_gui:GetComboboxValue(combo_info)
my_gui:GetKeybindValue(keybind_info)
my_gui:GetColorPickerValue(colorpicker_info)
my_gui:GetTextInputValue(textinput_info)
my_gui:GetKeyCheckboxValue(keycheckbox_info)
```

### Keybind Management

```lua
-- Get current key code
local key = my_gui:GetKeybindCurrentKey(keybind_info)

-- Check if listening
local is_listening = my_gui:IsKeybindListening(keybind_info)

-- Set key programmatically
my_gui:SetKeybindKey(keybind_info, 0x70) -- Set to F1
```

### GUI Control

```lua
-- Toggle GUI visibility
my_gui:toggle()

-- Generate unique component IDs
local unique_id = my_gui:generate_id("prefix")
```

## Best Practices

### 1. Component Organization

```lua
-- Group related components
local settings_y = 10
my_gui:AddHeader("Combat Settings", 10, settings_y)
my_gui:AddCheckbox("Auto Attack", 10, settings_y + 30, true, callback)
my_gui:AddSliderInt("Damage", 10, settings_y + 60, 1, 100, 50, callback)
```

### 2. Callback Functions

```lua
-- Use proper callback patterns
local function on_setting_changed(value)
    -- Update game state
    game.settings.auto_attack = value
    
    -- Save to file if needed
    save_settings()
end

my_gui:AddCheckbox("Auto Attack", 10, 50, true, on_setting_changed)
```

### 3. Error Handling

```lua
-- Always check component validity
local checkbox = my_gui:AddCheckbox("Feature", 10, 50, true, callback)
if checkbox then
    local state = my_gui:GetCheckboxValue(checkbox)
    if state ~= nil then
        -- Use state safely
    end
end
```

### 4. Performance Considerations

```lua
-- Use dynamic labels sparingly
local fps_label = my_gui:AddLabel("FPS: 60", 10, 10, {
    dynamic = true,
    update_callback = function()
        return "FPS: " .. tostring(math.floor(1 / frame_time))
    end
})
```

## Troubleshooting

### Common Issues

1. **Components not showing**: Check if GUI is open and enabled in selection bar
2. **Click-through issues**: Ensure mouse collision detection is working
3. **State not persisting**: Verify unique component IDs are being generated
4. **Input blocking**: Check if any text inputs are focused or keybinds listening

### Debug Mode

Enable debug mode in constants.lua:
```lua
Settings.debug_mode = true
```

## Integration Examples

### Complete GUI Example

```lua
-- Create the GUI
local combat_gui = LxCommon.Gui.register("Combat System", 400, 500)

-- Set up the render callback
combat_gui:set_render_callback(function()
    -- Header
    combat_gui:AddHeader("Combat Configuration", 10, 10)
    
    -- Enable toggle
    local enable_combat = combat_gui:AddCheckbox("Enable Combat", 10, 40, true, function(state)
        game.combat.enabled = state
    end)
    
    -- Settings
    local damage_slider = combat_gui:AddSliderInt("Base Damage", 10, 80, 1, 100, 25, function(value)
        game.combat.base_damage = value
    end)
    
    local target_combo = combat_gui:AddCombobox("Target Priority", 10, 120, 
        {"Closest", "Lowest HP", "Highest Threat"}, 1, function(index)
            game.combat.target_priority = index
        end)
    
    -- Keybinds
    local attack_key = combat_gui:AddKeybind("Attack Key", 10, 160, 0x20, function(key) -- Space
        game.combat.attack_key = key
    end)
    
    -- Status display
    local status_text = "Status: " .. (game.combat.enabled and "Active" or "Disabled")
    combat_gui:AddLabel(status_text, 10, 200, {
        color = game.combat.enabled and color.green(255) or color.red(255),
        animation = game.combat.enabled and "pulse" or "none"
    })
end)
```

This documentation provides a comprehensive guide to using the LxCommon GUI system effectively. The system offers powerful features while maintaining ease of use and flexibility for various plugin development needs. 