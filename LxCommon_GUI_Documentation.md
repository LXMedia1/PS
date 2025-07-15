# LxCommon GUI System - Comprehensive Documentation

⚠️ **IMPORTANT WARNING - EARLY DEVELOPMENT** ⚠️

I will keep LxCommon open source for others to learn/use things from, but for your projects I suggest making a copy of the current stage. This is an early project and LxCommon will be changed a lot - I don't want to keep backward compatibility at this stage. Use the code at your will, credits would be appreciated but use it as you like. Don't rely on the public repository as it changes frequently. I will remove this warning when I enter a stable phase.

---

## Overview

The LxCommon GUI system is an advanced, modular framework for creating interactive user interfaces in Lua-based game plugins. It provides a complete windowing system with direct rendering capabilities, comprehensive input handling, automatic persistence, and a rich set of UI components with professional visual effects.

## Architecture

### Core Components

The system is built with a clean modular architecture for maintainability and extensibility:

```
Lx_Common/
├── main.lua                    # Main entry point and global exports
├── header.lua                  # Plugin metadata and requirements
├── gui/
│   ├── elements/
│   │   └── menu.lua           # Menu class with all UI components and save/load system
│   ├── functions/
│   │   ├── input.lua          # Mouse and keyboard input handling
│   │   └── rendering.lua      # Advanced rendering with visual effects
│   └── utils/
│       ├── constants.lua      # Global constants, state, and configuration
│       └── helpers.lua        # Utility functions for collision detection and input blocking
```

### Key Features

- **Modular Design**: Clean separation of concerns with reusable components
- **Direct Rendering**: Uses `core.graphics` functions for professional UI rendering
- **Advanced Input Handling**: Comprehensive mouse and keyboard support with proper blocking
- **Auto-Save Persistence**: File-based storage with configurable per-component saving
- **Selection Bar**: Professional hanging tabs for multi-GUI navigation
- **Visual Effects**: Animations, hover effects, shadows, outlines, and glow effects
- **Professional Styling**: Modern dark theme with responsive visual feedback

### Input Blocking Behavior

The GUI system provides intelligent **selective input blocking**:

**What IS blocked:**
- **Movement**: Character movement is disabled when text inputs are focused or keybinds are listening
- **Mouse clicks**: Mouse interactions are blocked within GUI areas through invisible blocking windows
- **Mouse hover**: GUI areas prevent mouse events from reaching the game world
- **Text Input**: Full keyboard capture when text fields are focused
- **Keybind Listening**: Complete input capture during key assignment

**What is NOT blocked:**
- Keyboard hotkeys and shortcuts (when not in text input mode)
- Spell casting and ability usage (when not actively editing)
- Other game actions that don't conflict with GUI interaction

**Smart Detection**: Use `LxCommon.isInputBlocked()` to check if the GUI system is currently blocking input and adjust your plugin behavior accordingly.

## Getting Started

### Basic Usage

```lua
-- Create a new GUI with auto-save persistence
local my_gui = LxCommon.Menu:new("My GUI", 400, 300)

-- Alternative with custom plugin key for save files
local my_gui = LxCommon.Menu:new("My GUI", 400, 300, "my_unique_plugin_key")

-- Set up the render callback for custom content
my_gui:set_render_callback(function()
    -- Add your custom rendering logic here
end)
```

### Global Access

The system exports several global functions for easy access:

```lua
-- Main registration function (recommended)
local gui = LxCommon.Menu:new("My GUI", 400, 300)

-- Alternative registration
local gui = LxCommon.Gui.register("My GUI", 400, 300)

-- Legacy support
local gui = LxCommon.registerGui("My GUI", 400, 300)

-- Check if input is blocked by GUI system
if LxCommon.isInputBlocked() then
    -- GUI is active, don't process game actions
    return
end

-- Direct access to Menu class
local Menu = LxCommon.Menu
```

## Auto-Save Persistence System

### Overview
LxCommon includes a sophisticated auto-save system that automatically persists component values across sessions using individual `.dat` files per GUI.

### Component-specific Auto-save Defaults
- **Keybinds**: Always auto-save (cannot be disabled) - saves both key and visibility settings
- **Checkboxes**: Auto-save enabled by default (opt-out with `auto_save = false`)
- **Color Pickers**: Auto-save enabled by default (opt-out with `auto_save = false`)  
- **Text Inputs**: Auto-save disabled by default (opt-in with `auto_save = true`)

### File Storage Details
- **File Format**: Simple key=value format with type conversion
- **File Location**: `lxcommon_[unique_plugin_key].dat` in the data directory
- **API Used**: `core.create_data_file()`, `core.write_data_file()`, `core.read_data_file()`
- **Save Timing**: Immediate saving when values change
- **Type Safety**: Proper conversion for boolean, number, and string types

### Save System Methods
```lua
-- Manual save/load control
gui:SaveComponentValue("component_type", "component_id", value)
local value = gui:LoadComponentValue("component_type", "component_id", default_value)

-- Global controls
gui:SetAutoSave(false)  -- Disable auto-save for this GUI
gui:ClearSavedData()    -- Clear all saved data for this GUI
```

## Menu Components

### Labels - Enhanced Text Rendering

Advanced text rendering with multiple visual effects and interactive features.

```lua
gui:AddLabel(text, x, y, options)
```

**Basic Usage:**
```lua
gui:AddLabel("Hello World", 10, 10)
```

**Advanced Features:**
```lua
gui:AddLabel("Animated Text", 10, 10, {
    -- Visual styling
    color = color.yellow(255),
    font_size = 16,
    outline = true,                    -- Black text outline (default: true)
    outline_color = color.black(255),
    
    -- Background options
    background = true,
    bg_color = color.new(20, 20, 30, 180),
    bg_padding = 5,
    
    -- Animation effects
    animation = "rainbow",             -- "none", "pulse", "fade", "rainbow", "glow"
    animation_speed = 1.5,
    
    -- Interactive features
    clickable = true,
    click_callback = function() 
        core.log("Label clicked!") 
    end,
    hover_color = color.white(255),
    
    -- Special effects
    shadow = true,
    shadow_color = color.new(0, 0, 0, 100),
    shadow_offset = {x = 2, y = 2},
    
    -- Layout options
    align = "center",                  -- "left", "center", "right"
    max_width = 200
})
```

**Dynamic Labels:**
```lua
local health_label = gui:AddLabel("Health: 100", 10, 10, {
    dynamic = true,
    update_callback = function()
        return "Health: " .. tostring(player.health)
    end,
    animation = "pulse",
    color = player.health < 50 and color.red(255) or color.green(255)
})
```

### Buttons - Interactive Controls

Professional buttons with hover effects and customizable styling.

```lua
gui:AddButton(text, x, y, width, height, callback, bg_color, text_color, border_color)
```

**Example:**
```lua
gui:AddButton("Execute Action", 10, 50, 120, 30, function()
    core.log("Action executed!")
    -- Your action code here
end, 
color.new(60, 90, 140, 200),    -- Background color
color.white(255),               -- Text color  
color.new(80, 110, 160, 255))   -- Border color
```

**Features:**
- Automatic hover effects with color brightening
- Precise click detection
- Centered text rendering
- Customizable colors and dimensions

### Checkboxes - Boolean Toggles

Interactive checkboxes with visual feedback and auto-save support.

```lua
gui:AddCheckbox(text, x, y, default_state, callback, options)
```

**Example:**
```lua
local auto_attack = gui:AddCheckbox("Enable Auto Attack", 10, 90, true, function(state)
    game.combat.auto_attack = state
    core.log("Auto attack: " .. tostring(state))
end, {
    auto_save = true,                 -- Save state automatically (default: true)
    text_color = color.white(255),
    width = 200
})

-- Get current state
local is_enabled = gui:GetCheckboxValue(auto_attack)
```

**Features:**
- Visual checkmark rendering
- Hover effects with color changes
- Automatic state persistence
- Click area includes text for better usability

### Integer Sliders - Numeric Input

Draggable sliders for integer values with visual feedback.

```lua
gui:AddSliderInt(text, x, y, min_value, max_value, default_value, callback, options)
```

**Example:**
```lua
local damage_slider = gui:AddSliderInt("Base Damage", 10, 130, 1, 100, 25, function(value)
    game.combat.base_damage = value
    core.log("Damage set to: " .. value)
end, {
    width = 200,
    text_color = color.cyan(255)
})

-- Get current value
local current_damage = gui:GetSliderIntValue(damage_slider)
```

### Float Sliders - Precise Numeric Input

Draggable sliders for floating-point values.

```lua
gui:AddSliderFloat(text, x, y, min_value, max_value, default_value, callback, options)
```

**Example:**
```lua
local speed_modifier = gui:AddSliderFloat("Speed Multiplier", 10, 170, 0.1, 3.0, 1.0, function(value)
    game.player.speed_modifier = value
end)

local current_speed = gui:GetSliderFloatValue(speed_modifier)
```

### Comboboxes - Dropdown Selection

Dropdown lists with full keyboard and mouse support.

```lua
gui:AddCombobox(text, x, y, items, default_index, callback, options)
```

**Example:**
```lua
local target_priority = gui:AddCombobox("Target Priority", 10, 210, {
    "Closest Enemy",
    "Lowest Health", 
    "Highest Threat",
    "Player Selected"
}, 1, function(selected_index)
    game.combat.target_mode = selected_index
end)

local current_selection = gui:GetComboboxValue(target_priority)
```

**Features:**
- Smooth dropdown animations
- Click-outside-to-close behavior
- Hover highlighting of options
- Keyboard navigation support

### Keybinds - Interactive Key Assignment

Advanced keybind configuration with listening mode and visibility options.

```lua
gui:AddKeybind(text, x, y, default_key, callback, options)
```

**Basic Example:**
```lua
local attack_key = gui:AddKeybind("Attack Key", 10, 250, 0x20, function(key_code) -- Space bar
    game.combat.attack_key = key_code
    core.log("Attack key set to: " .. key_code)
end)
```

**Advanced Example with Visibility Control:**
```lua
local special_ability = gui:AddKeybind("Special Ability", 10, gui:GetNextKeybindY(10), 0x46, function(key_code) -- F key
    game.abilities.special_key = key_code
end, {
    show_visibility_option = true,     -- Show visibility dropdown (default: true)
    visibility_callback = function(visibility_index)
        local options = {"None", "On Active", "Permanent"}
        game.abilities.special_visibility = options[visibility_index]
        core.log("Visibility: " .. options[visibility_index])
    end
})

-- Helper methods
local current_key = gui:GetKeybindCurrentKey(special_ability)
local is_listening = gui:IsKeybindListening(special_ability)
local visibility = gui:GetKeybindVisibility(special_ability)
local visibility_name = gui:GetKeybindVisibilityName(special_ability)

-- Programmatic control
gui:SetKeybindKey(special_ability, 0x47)        -- Set to G key
gui:SetKeybindVisibility(special_ability, 2)    -- Set to "On Active"
```

**Advanced Features:**
- **Listening Mode**: Click to enter key listening (blue animated highlight)
- **Timeout Protection**: 5-second automatic timeout during listening
- **Clear Function**: X button to remove keybind
- **Key Name Display**: Automatic conversion to readable names (F1, Space, etc.)
- **Visibility Options**: None, On Active, Permanent with dropdown selection
- **Conflict Detection**: Visual feedback for key assignment conflicts
- **Input Blocking**: Complete game input blocking while listening
- **Auto-Save**: Automatic persistence of both key and visibility settings

**Spacing Helper:**
```lua
-- Use GetNextKeybindY for proper spacing when adding multiple keybinds
local primary = gui:AddKeybind("Primary", 10, gui:GetNextKeybindY(10), 0x47, callback)     -- G
local secondary = gui:AddKeybind("Secondary", 10, gui:GetNextKeybindY(10), 0x48, callback) -- H  
local modifier = gui:AddKeybind("Modifier", 10, gui:GetNextKeybindY(10), 0x10, callback)   -- Shift
```

### Color Pickers - Advanced Color Selection

Interactive RGB color selection with live preview and preset support.

```lua
gui:AddColorPicker(text, x, y, default_color, callback, options)
```

**Example:**
```lua
local theme_color = gui:AddColorPicker("UI Theme Color", 10, 290, color.blue(255), function(new_color)
    game.ui.theme_color = new_color
    core.log("Color changed: RGB(" .. new_color.r .. ", " .. new_color.g .. ", " .. new_color.b .. ")")
end, {
    auto_save = true,                 -- Save color automatically (default: true)
    width = 220
})

local current_color = gui:GetColorPickerValue(theme_color)
```

**Features:**
- **RGB Sliders**: Individual red, green, blue sliders with drag interaction
- **Live Preview**: Real-time color preview during adjustment
- **Color Display**: Current color swatch with RGB values
- **Rainbow Presets**: Quick access to common colors
- **Auto-Save**: Automatic persistence in "r,g,b,a" string format
- **Drag Interaction**: Smooth slider dragging with visual feedback

### Text Inputs - Advanced Text Fields

Full-featured text input with comprehensive keyboard support and editing features.

```lua
gui:AddTextInput(text, x, y, default_text, callback, options)
```

**Example:**
```lua
local player_name = gui:AddTextInput("Character Name", 10, 330, "", function(text)
    game.player.custom_name = text
    core.log("Name changed to: " .. text)
end, {
    auto_save = true,                 -- Enable auto-save (default: false)
    placeholder = "Enter your character name...",
    width = 250,
    save_input = true
})

local current_name = gui:GetTextInputValue(player_name)
```

**Advanced Features:**
- **Focus Management**: Automatic input blocking when focused
- **Text Selection**: Click positioning and double-click to select all
- **Keyboard Navigation**: Arrow keys, Home/End, Ctrl+A for select all
- **Text Editing**: Delete, Backspace with proper cursor handling
- **Key Repeat**: Hold keys for continuous action
- **Visual Selection**: Highlighted text selection display
- **Placeholder Text**: Grayed-out hint text when empty
- **Auto-Save**: Optional persistence across sessions

**Keyboard Shortcuts:**
- **Arrow Keys**: Move cursor left/right
- **Home/End**: Move to start/end of text
- **Delete/Backspace**: Remove characters
- **Ctrl+A**: Select all text
- **Double-click**: Select all text
- **Escape**: Clear focus

### Headers - Section Dividers

Styled section headers for organizing content.

```lua
gui:AddHeader(text, x, y, options)
```

**Example:**
```lua
gui:AddHeader("Combat Settings", 10, 10, {
    text_color = color.yellow(255),
    font_size = 16
})
```

### Tree Nodes - Collapsible Sections

Expandable/collapsible content sections.

```lua
gui:AddTreeNode(text, x, y, render_callback, options)
```

**Example:**
```lua
gui:AddTreeNode("Advanced Options", 10, 50, function()
    -- Content rendered when expanded
    gui:AddLabel("Nested option 1", 20, 80)
    gui:AddCheckbox("Nested setting", 20, 100, false, callback)
end, {
    text_color = color.cyan(255)
})
```

### Key Checkboxes - Combined Key + Toggle

Checkboxes with associated keybind functionality.

```lua
gui:AddKeyCheckbox(text, x, y, default_key, default_state, callback, options)
```

**Example:**
```lua
local auto_heal = gui:AddKeyCheckbox("Auto Heal", 10, 120, 0x48, true, function(state) -- H key
    game.healing.auto_enabled = state
end, {
    show_in_binds = true,
    initial_toggle_state = false
})

local current_state = gui:GetKeyCheckboxValue(auto_heal)
```

### Images - Visual Content

Image rendering support (if available in environment).

```lua
gui:AddImage(image_data, x, y, width, height, options)
```

**Example:**
```lua
local logo = gui:AddImage(base64_image_data, 10, 10, 64, 64, {
    clickable = true,
    click_callback = function()
        core.log("Logo clicked!")
    end,
    hover_scale = 1.1,                -- Scale up 10% on hover
    rotation = 0,
    alpha = 1.0
})
```

**Features:**
- Support for base64 image data
- Hover scaling effects
- Click interaction support
- Rotation and alpha blending (if supported)

## Advanced Features

### Animation System

Labels support various sophisticated animation effects:

- **pulse**: Smooth intensity pulsing effect
- **fade**: Opacity fading in and out
- **rainbow**: Color cycling through full spectrum
- **glow**: Brightness glow effect with intensity variation

**Animation Configuration:**
```lua
{
    animation = "rainbow",
    animation_speed = 2.0,     -- Speed multiplier
    animation_time = 0         -- Internal time tracking (auto-managed)
}
```

### Input Blocking Intelligence

The system automatically manages input blocking with sophisticated detection:

**Automatic Blocking Triggers:**
- Mouse hovering over any GUI area (tabs or windows)
- Text inputs gaining focus
- Keybinds entering listening mode
- Dropdown menus being open
- Color picker interaction

**Smart State Management:**
- Input blocking persists only while GUI elements are active
- Automatic cleanup when focus is lost or interactions complete
- Cross-GUI state tracking for proper behavior

### Visual Effects System

**Hover Effects:**
- Color brightening on interactive elements
- Smooth transitions and visual feedback
- Consistent styling across all components

**Professional Styling:**
- Modern dark theme with blue accents
- Consistent spacing and alignment
- Rounded corners and smooth borders
- Shadow effects and outlines for text

**Responsive Design:**
- Automatic screen size adaptation
- Centered positioning and smart layout
- Proper text alignment and scaling

### Selection Bar - Multi-GUI Navigation

Professional hanging tab interface for managing multiple GUIs:

**Features:**
- **Hanging Tab Design**: Elegant angled tabs with professional appearance
- **Hover Effects**: Cyan glow effects on tab hover
- **State Indication**: Visual distinction between open/closed GUIs
- **Centered Layout**: Automatic positioning based on screen width
- **Enable/Disable**: Individual GUI enable/disable from main menu

**Tab Styling:**
- Angled bottom cuts for hanging appearance
- Black text outlines for readability
- Smooth color transitions
- Responsive hover feedback

## Helper Functions & Utilities

### Component Value Retrieval

```lua
-- Get current values from components
local checkbox_state = gui:GetCheckboxValue(checkbox_info)
local slider_value = gui:GetSliderIntValue(slider_info)
local float_value = gui:GetSliderFloatValue(slider_info)
local combo_selection = gui:GetComboboxValue(combo_info)
local keybind_state = gui:GetKeybindValue(keybind_info)
local color_value = gui:GetColorPickerValue(colorpicker_info)
local text_content = gui:GetTextInputValue(textinput_info)
local key_checkbox_state = gui:GetKeyCheckboxValue(keycheckbox_info)
```

### Advanced Keybind Management

```lua
-- Get current key assignment
local key_code = gui:GetKeybindCurrentKey(keybind_info)

-- Check listening state
local is_listening = gui:IsKeybindListening(keybind_info)

-- Programmatic key assignment
gui:SetKeybindKey(keybind_info, 0x70)  -- Set to F1

-- Visibility management
local visibility_index = gui:GetKeybindVisibility(keybind_info)
local visibility_name = gui:GetKeybindVisibilityName(keybind_info)
gui:SetKeybindVisibility(keybind_info, 2)  -- Set to "On Active"
```

### GUI Control Methods

```lua
-- Toggle GUI visibility
gui:toggle()

-- Generate unique component IDs
local unique_id = gui:generate_id("custom_prefix")

-- Keybind spacing helper
local next_y = gui:GetNextKeybindY(starting_y)
```

### Persistence Management

```lua
-- Manual save/load operations
gui:SaveComponentValue("checkbox", "my_setting", true)
local saved_value = gui:LoadComponentValue("text_input", "username", "default_name")

-- Global auto-save control
gui:SetAutoSave(false)      -- Disable auto-save for this GUI
gui:ClearSavedData()        -- Clear all saved data
gui:LoadSavedData()         -- Reload data from file
```

## Best Practices

### 1. Component Organization and Layout

```lua
-- Group related components with proper spacing
local settings_start_y = 10
local current_y = settings_start_y

-- Use headers to organize sections
gui:AddHeader("Combat Configuration", 10, current_y)
current_y = current_y + 30

-- Group related settings
gui:AddCheckbox("Enable Combat", 10, current_y, true, callback)
current_y = current_y + 30

gui:AddSliderInt("Base Damage", 10, current_y, 1, 100, 25, callback)  
current_y = current_y + 40

-- Use the helper for keybinds
local attack_key = gui:AddKeybind("Attack Key", 10, gui:GetNextKeybindY(current_y), 0x20, callback)
```

### 2. Proper Auto-Save Configuration

```lua
-- Enable auto-save for important settings
local critical_setting = gui:AddCheckbox("Critical Feature", 10, 50, false, callback, {
    auto_save = true  -- Will persist across sessions
})

-- Disable auto-save for temporary or sensitive data  
local temp_input = gui:AddTextInput("Temporary Note", 10, 80, "", callback, {
    auto_save = false  -- Will not be saved
})

-- Use auto-save for user preferences
local ui_color = gui:AddColorPicker("UI Color", 10, 120, color.blue(255), callback, {
    auto_save = true  -- User's color choice will be remembered
})
```

### 3. Effective Callback Patterns

```lua
-- Use proper callback patterns with error handling
local function on_combat_setting_changed(enabled)
    if not game or not game.combat then
        core.log("Warning: Game combat system not available")
        return
    end
    
    game.combat.enabled = enabled
    
    -- Update related UI elements
    if enabled then
        core.log("Combat system enabled")
    else
        core.log("Combat system disabled")
        -- Clean up any active combat state
        game.combat:stop_all_actions()
    end
end

gui:AddCheckbox("Enable Combat", 10, 50, false, on_combat_setting_changed, {
    auto_save = true
})
```

### 4. Input Blocking Integration

```lua
-- Proper integration with plugin input handling
local function on_plugin_update()
    -- Check if GUI is blocking input before processing game actions
    if LxCommon.isInputBlocked() then
        return  -- Don't process any game input while GUI is active
    end
    
    -- Safe to process game input
    if core.input.is_key_pressed(game.settings.attack_key) then
        game.combat:perform_attack()
    end
end

core.register_on_update_callback(on_plugin_update)
```

### 5. Dynamic Content Management

```lua
-- Efficient dynamic label updates
local status_label = gui:AddLabel("", 10, 200, {
    dynamic = true,
    update_callback = function()
        if not game.player then return "Player not available" end
        
        local health_pct = (game.player.health / game.player.max_health) * 100
        return string.format("Health: %d/%d (%.1f%%)", 
                           game.player.health, game.player.max_health, health_pct)
    end,
    color = function()
        if not game.player then return color.gray(255) end
        local pct = game.player.health / game.player.max_health
        if pct > 0.5 then return color.green(255)
        elseif pct > 0.25 then return color.yellow(255)
        else return color.red(255) end
    end,
    animation = function()
        if not game.player then return "none" end
        return game.player.health < (game.player.max_health * 0.25) and "pulse" or "none"
    end
})
```

### 6. Error Handling and Safety

```lua
-- Always validate component references
local function setup_gui()
    local combat_checkbox = gui:AddCheckbox("Enable Combat", 10, 50, false, callback)
    
    if not combat_checkbox then
        core.log("Error: Failed to create combat checkbox")
        return false
    end
    
    -- Store reference for later use
    gui.combat_checkbox = combat_checkbox
    return true
end

-- Safe value retrieval
local function get_combat_enabled()
    if not gui.combat_checkbox then
        return false  -- Safe default
    end
    
    local state = gui:GetCheckboxValue(gui.combat_checkbox)
    return state ~= nil and state or false
end
```

### 7. Performance Optimization

```lua
-- Limit dynamic updates for performance
local last_update_time = 0
local update_interval = 0.1  -- Update every 100ms

local fps_label = gui:AddLabel("", 10, 10, {
    dynamic = true,
    update_callback = function()
        local current_time = core.get_time()
        if current_time - last_update_time < update_interval then
            return nil  -- Skip update
        end
        last_update_time = current_time
        
        return "FPS: " .. tostring(math.floor(1 / core.get_frame_time()))
    end
})
```

## Integration Examples

### Complete Combat Configuration GUI

```lua
-- Create the main combat GUI
local combat_gui = LxCommon.Menu:new("Combat System", 450, 600, "combat_config")

-- Set up the render callback
combat_gui:set_render_callback(function()
    local y_pos = 10
    
    -- Main header
    combat_gui:AddHeader("Combat Configuration", 10, y_pos)
    y_pos = y_pos + 35
    
    -- Enable/disable toggle
    local combat_enabled = combat_gui:AddCheckbox("Enable Combat System", 10, y_pos, false, function(state)
        game.combat.enabled = state
        if state then
            core.log("Combat system activated")
        else
            core.log("Combat system deactivated")
            game.combat:stop_all_actions()
        end
    end, {auto_save = true})
    y_pos = y_pos + 35
    
    -- Combat settings section
    combat_gui:AddHeader("Combat Settings", 10, y_pos)
    y_pos = y_pos + 30
    
    -- Damage configuration
    local base_damage = combat_gui:AddSliderInt("Base Damage", 10, y_pos, 1, 200, 50, function(value)
        game.combat.base_damage = value
    end)
    y_pos = y_pos + 40
    
    -- Critical chance
    local crit_chance = combat_gui:AddSliderFloat("Critical Chance", 10, y_pos, 0.0, 1.0, 0.15, function(value)
        game.combat.crit_chance = value
    end)
    y_pos = y_pos + 40
    
    -- Target selection
    local target_mode = combat_gui:AddCombobox("Target Priority", 10, y_pos, {
        "Closest Enemy",
        "Lowest Health",
        "Highest Threat", 
        "Player Selected"
    }, 1, function(index)
        game.combat.target_mode = index
    end)
    y_pos = y_pos + 40
    
    -- Keybind configuration section
    combat_gui:AddHeader("Keybinds", 10, y_pos)
    y_pos = y_pos + 25
    
    -- Attack keybind
    local attack_key = combat_gui:AddKeybind("Primary Attack", 10, combat_gui:GetNextKeybindY(y_pos), 0x20, function(key)
        game.combat.primary_attack_key = key
    end, {
        show_visibility_option = true,
        visibility_callback = function(vis)
            game.combat.attack_visibility = vis
        end
    })
    
    -- Special ability keybind
    local special_key = combat_gui:AddKeybind("Special Ability", 10, combat_gui:GetNextKeybindY(y_pos), 0x46, function(key)
        game.combat.special_ability_key = key
    end)
    
    -- Block/defend keybind  
    local block_key = combat_gui:AddKeybind("Block/Defend", 10, combat_gui:GetNextKeybindY(y_pos), 0x47, function(key)
        game.combat.block_key = key
    end)
    
    y_pos = combat_gui:GetNextKeybindY(y_pos) + 60
    
    -- Visual customization
    combat_gui:AddHeader("Visual Settings", 10, y_pos)
    y_pos = y_pos + 30
    
    -- UI color picker
    local ui_color = combat_gui:AddColorPicker("UI Accent Color", 10, y_pos, color.cyan(255), function(new_color)
        game.ui.accent_color = new_color
    end, {auto_save = true})
    y_pos = y_pos + 80
    
    -- Status display
    local status_text = "Status: " .. (game.combat.enabled and "Active" or "Disabled")
    combat_gui:AddLabel(status_text, 10, y_pos, {
        color = game.combat.enabled and color.green(255) or color.red(255),
        animation = game.combat.enabled and "pulse" or "none",
        font_size = 14
    })
end)
```

### Advanced Settings Panel with Persistence

```lua
-- Create settings GUI with comprehensive auto-save
local settings_gui = LxCommon.Menu:new("Advanced Settings", 500, 700, "advanced_settings")

settings_gui:set_render_callback(function()
    local y = 10
    
    -- User preferences section
    settings_gui:AddHeader("User Preferences", 10, y)
    y = y + 30
    
    -- Username with auto-save
    local username = settings_gui:AddTextInput("Display Name", 10, y, "", function(text)
        game.player.display_name = text
    end, {
        auto_save = true,
        placeholder = "Enter your display name..."
    })
    y = y + 40
    
    -- Theme selection
    local theme = settings_gui:AddCombobox("UI Theme", 10, y, {
        "Dark Blue", "Dark Green", "Dark Purple", "Classic"
    }, 1, function(index)
        game.ui:apply_theme(index)
    end)
    y = y + 40
    
    -- Performance settings
    settings_gui:AddHeader("Performance", 10, y)
    y = y + 30
    
    local fps_limit = settings_gui:AddCheckbox("Limit FPS", 10, y, false, function(enabled)
        game.graphics.fps_limit_enabled = enabled
    end, {auto_save = true})
    y = y + 30
    
    local render_quality = settings_gui:AddSliderFloat("Render Quality", 10, y, 0.5, 2.0, 1.0, function(quality)
        game.graphics.render_scale = quality
    end)
    y = y + 40
    
    -- Advanced options with tree node
    settings_gui:AddTreeNode("Advanced Options", 10, y, function()
        -- Content only shown when expanded
        local debug_mode = settings_gui:AddCheckbox("Debug Mode", 30, y + 30, false, function(enabled)
            game.debug.enabled = enabled
        end, {auto_save = true})
        
        local verbose_logging = settings_gui:AddCheckbox("Verbose Logging", 30, y + 60, false, function(enabled)
            game.debug.verbose = enabled
        end, {auto_save = true})
    end)
end)
```

## Troubleshooting

### Common Issues and Solutions

1. **Components Not Appearing**
   - Check if GUI is properly opened and visible
   - Verify GUI is enabled in the main menu selection bar
   - Ensure render callback is set if using custom content

2. **Auto-Save Not Working**
   - Verify auto-save is enabled: `{auto_save = true}`
   - Check if unique plugin key is properly set
   - Ensure core file API functions are available

3. **Input Not Being Blocked**
   - Check if `LxCommon.isInputBlocked()` returns true during GUI interaction
   - Verify text inputs and keybinds are properly focused
   - Ensure proper integration in your plugin's input handling

4. **Keybinds Not Saving**
   - Keybinds always auto-save by design (cannot be disabled)
   - Check if visibility settings are being saved separately
   - Verify callback functions are properly set

5. **Visual Glitches**
   - Ensure proper component spacing to avoid overlaps
   - Check color values are within valid ranges (0-255)
   - Verify screen size compatibility

### Performance Monitoring

```lua
-- Monitor GUI performance impact
local function check_gui_performance()
    local start_time = core.get_time()
    
    -- Your GUI operations here
    
    local end_time = core.get_time()
    local duration = end_time - start_time
    
    if duration > 0.001 then  -- 1ms threshold
        core.log("Warning: GUI operation took " .. duration .. "s")
    end
end
```

## Advanced Integration Patterns

### Plugin State Management

```lua
-- Integrate GUI state with plugin lifecycle
local function load_plugin_settings()
    -- Load settings when plugin initializes
    if gui and gui.LoadSavedData then
        gui:LoadSavedData()
    end
end

local function save_plugin_settings()
    -- Save settings when plugin shuts down
    if gui and gui.SaveDataToFile then
        gui:SaveDataToFile()
    end
end

-- Register lifecycle callbacks
core.register_on_plugin_load_callback(load_plugin_settings)
core.register_on_plugin_unload_callback(save_plugin_settings)
```

### Cross-GUI Communication

```lua
-- Share data between multiple GUIs
local shared_data = {
    combat_enabled = false,
    selected_target = nil,
    theme_color = color.blue(255)
}

-- Update shared data from GUI callbacks
local combat_gui = LxCommon.Menu:new("Combat", 400, 300)
local settings_gui = LxCommon.Menu:new("Settings", 350, 250)

-- Combat GUI updates shared state
combat_gui:AddCheckbox("Enable Combat", 10, 50, false, function(state)
    shared_data.combat_enabled = state
    -- Notify other systems
    game.events:fire("combat_state_changed", state)
end)

-- Settings GUI can read and modify shared state
settings_gui:AddColorPicker("Theme Color", 10, 50, shared_data.theme_color, function(color)
    shared_data.theme_color = color
    -- Apply to all GUIs
    game.ui:update_theme(color)
end)
```

This comprehensive documentation covers all aspects of the LxCommon GUI system. The system provides a powerful, flexible foundation for creating professional user interfaces in Lua-based game plugins with automatic persistence, advanced visual effects, and comprehensive input handling. 