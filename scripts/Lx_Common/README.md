# LxCommon - Advanced GUI System for Game Plugins

⚠️ **IMPORTANT WARNING - EARLY DEVELOPMENT** ⚠️

I will keep LxCommon open source for others to learn/use things from, but for your projects I suggest making a copy of the current stage. This is an early project and LxCommon will be changed a lot - I don't want to keep backward compatibility at this stage. Use the code at your will, credits would be appreciated but use it as you like. Don't rely on the public repository as it changes frequently. I will remove this warning when I enter a stable phase.

---

## Overview

LxCommon is a comprehensive GUI system designed for game plugins, providing a complete framework for creating interactive user interfaces with advanced features like auto-save persistence, input handling, and component management.

## Features

### Core GUI System
- **Modular Architecture**: Clean separation of concerns with dedicated modules for rendering, input, utilities, and components
- **Multiple GUI Support**: Register and manage multiple GUI windows simultaneously
- **Tab-based Navigation**: Beautiful hanging tab interface with hover effects and glow
- **Auto-positioning**: Smart window positioning and screen size adaptation
- **Input Blocking**: Prevents game input when interacting with GUI elements

### Component Library
- **Labels**: Enhanced text rendering with animations (pulse, fade, rainbow, glow), backgrounds, shadows, outlines, and click handling
- **Buttons**: Interactive buttons with hover effects and custom styling
- **Checkboxes**: Auto-save enabled checkboxes with state persistence and immediate saving
- **Sliders**: Integer and float sliders with drag interaction and visual feedback
- **Comboboxes**: Dropdown menus with full keyboard and mouse support and auto-save
- **Color Pickers**: Advanced RGB color selection with rainbow presets, live preview, and auto-save
- **Text Inputs**: Full-featured text input with cursor positioning, text selection, keyboard shortcuts, and placeholder support
- **Keybinds**: Interactive keybind configuration with conflict detection, visibility options, and auto-save
- **Headers**: Section headers for organizing content
- **Tree Nodes**: Collapsible content sections
- **Images**: Image rendering support (if available in environment)

### Persistence System ⭐ **COMPLETE & ROBUST**
- **Auto-Save**: Configurable automatic saving for all components with immediate persistence
- **File-based Storage**: Individual `.dat` files per GUI using core API with error handling
- **Type-safe Loading**: Proper value conversion, parsing, and fallback handling
- **Per-component Control**: Enable/disable auto-save on individual components
- **Smart Initialization**: Loads saved values on startup, skips saving when existing data found
- **Live Saving**: Real-time saving during user interactions (color changes, text input, checkbox toggles)
- **Cross-session Persistence**: All settings maintained across application restarts

### Advanced Input Handling
- **Mouse Interaction**: Precise click detection, hover effects, drag operations
- **Keyboard Support**: Full keyboard input for text fields and keybinds
- **Key Repeat**: Proper key repeat functionality for text editing
- **Input Blocking**: Smart game input blocking when GUI is active
- **Text Selection**: Click positioning, double-click selection, keyboard navigation

### Visual Features
- **Professional Styling**: Modern dark theme with blue accents
- **Hover Effects**: Interactive feedback on all components
- **Animations**: Multiple animation types for labels and visual feedback
- **Glow Effects**: Dynamic glow effects for enhanced visual appeal
- **Smart Layouts**: Automatic spacing and alignment

## Quick Start

### Basic Setup
```lua
-- Create a new GUI
local my_gui = LxCommon.Menu:new("My GUI", 400, 300)

-- Add components
my_gui:AddLabel("Welcome to my GUI!", 10, 10)
my_gui:AddButton("Click Me", 10, 40, 100, 30, function()
    core.log("Button clicked!")
end)

-- Add checkbox with auto-save
local checkbox = my_gui:AddCheckbox("Enable Feature", 10, 80, false, function(state)
    core.log("Checkbox state: " .. tostring(state))
end, {auto_save = true})

-- Set render callback for custom content
my_gui:set_render_callback(function()
    -- Custom rendering code here
end)
```

### Component Examples

#### Auto-save Text Input
```lua
local text_input = my_gui:AddTextInput("Username", 10, 120, "", function(text)
    core.log("Username changed: " .. text)
end, {
    auto_save = true,
    placeholder = "Enter your username..."
})
```

#### Color Picker with Auto-save
```lua
local color_picker = my_gui:AddColorPicker("Theme Color", 10, 160, color.blue(255), function(new_color)
    -- Color changed callback
end, {auto_save = true})
```

#### Interactive Keybind
```lua
local keybind = my_gui:AddKeybind("Toggle Feature", 10, 200, 0x46, function(key_code)
    core.log("Keybind set to: " .. key_code)
end, {
    show_visibility_option = true,
    visibility_callback = function(visibility)
        core.log("Visibility changed to: " .. visibility)
    end
})
```

#### Advanced Label with Animation
```lua
my_gui:AddLabel("Animated Text", 10, 240, {
    color = color.yellow(255),
    animation = "rainbow",
    animation_speed = 1.5,
    background = true,
    bg_color = color.new(20, 20, 30, 180),
    outline = true,
    clickable = true,
    click_callback = function()
        core.log("Animated label clicked!")
    end
})
```

## Auto-Save System

The LxCommon GUI framework includes a comprehensive auto-save system that automatically persists user settings across sessions.

### How It Works

1. **Automatic Persistence**: Components save their values immediately when changed
2. **File Storage**: Each GUI creates a unique `.dat` file (e.g., `lxcommon_my_gui_1.dat`)
3. **Cross-Session Loading**: Saved values are automatically loaded when the GUI is created
4. **Type Safety**: Values are properly converted and validated during save/load operations

### Auto-Save Defaults

| Component Type | Auto-Save Default | Override Option |
|----------------|-------------------|-----------------|
| **Checkboxes** | ✅ **Enabled** | `auto_save = false` to disable |
| **Comboboxes** | ✅ **Enabled** | `auto_save = false` to disable |
| **Color Pickers** | ✅ **Enabled** | `auto_save = false` to disable |
| **Keybinds** | ✅ **Always On** | Cannot be disabled |
| **Text Inputs** | ❌ **Disabled** | `auto_save = true` to enable |
| **Sliders** | ❌ **Disabled** | `auto_save = true` to enable |

### Usage Examples

```lua
-- Checkbox with auto-save (default enabled)
local auto_checkbox = my_gui:AddCheckbox("Auto-save Setting", 10, 50, false, callback)

-- Checkbox with auto-save disabled
local manual_checkbox = my_gui:AddCheckbox("Manual Setting", 10, 80, false, callback, {
    auto_save = false
})

-- Text input with auto-save enabled (default disabled)
local persistent_text = my_gui:AddTextInput("Username", 10, 110, "", callback, {
    auto_save = true,
    placeholder = "Enter username..."
})

-- Color picker with auto-save (default enabled)
local theme_color = my_gui:AddColorPicker("Theme", 10, 140, color.blue(255), callback)
```

### Manual Save/Load Control

```lua
-- Save a value manually
my_gui:SaveComponentValue("textinput", "my_text_id", "custom_value")

-- Load a value manually
local saved_value = my_gui:LoadComponentValue("textinput", "my_text_id", "default_value")

-- Clear all saved data for a GUI
my_gui:ClearSavedData()

-- Enable/disable auto-save for entire GUI
my_gui:SetAutoSave(false)  -- Disable
my_gui:SetAutoSave(true)   -- Enable
```

## API Reference

### Menu Class

#### Constructor
- `Menu:new(name, width, height, unique_plugin_key)` - Create new GUI

#### Component Methods
- `AddLabel(text, x, y, options)` - Add text label
- `AddButton(text, x, y, width, height, callback, bg_color, text_color, border_color)` - Add button
- `AddCheckbox(text, x, y, default_state, callback, options)` - Add checkbox
- `AddSliderInt(text, x, y, min, max, default, callback, options)` - Add integer slider
- `AddSliderFloat(text, x, y, min, max, default, callback, options)` - Add float slider
- `AddCombobox(text, x, y, items, default_index, callback, options)` - Add dropdown
- `AddColorPicker(text, x, y, default_color, callback, options)` - Add color picker
- `AddTextInput(text, x, y, default_text, callback, options)` - Add text input
- `AddKeybind(text, x, y, default_key, callback, options)` - Add keybind configurator
- `AddHeader(text, x, y, options)` - Add section header
- `AddTreeNode(text, x, y, render_callback, options)` - Add collapsible section
- `AddImage(image_data, x, y, width, height, options)` - Add image

#### Utility Methods
- `GetCheckboxValue(checkbox_info)` - Get checkbox state
- `GetSliderIntValue(slider_info)` - Get integer slider value
- `GetSliderFloatValue(slider_info)` - Get float slider value
- `GetComboboxValue(combo_info)` - Get combobox selection
- `GetKeybindValue(keybind_info)` - Get keybind state
- `GetColorPickerValue(colorpicker_info)` - Get color value
- `GetTextInputValue(textinput_info)` - Get text content

#### Persistence Methods
- `SaveComponentValue(type, id, value)` - Save component value manually
- `LoadComponentValue(type, id, default)` - Load component value with fallback
- `LoadSavedData()` - Load all saved data from file
- `ClearSavedData()` - Clear all saved data for this GUI
- `SetAutoSave(enabled)` - Enable/disable auto-save for entire GUI

### Global Access
```lua
-- Access through global LxCommon object
local gui = LxCommon.Menu:new("My GUI", 400, 300)

-- Legacy support
local gui = LxCommon.registerGui("My GUI", 400, 300)

-- Check if input is blocked
if LxCommon.isInputBlocked() then
    -- GUI is active, don't process game input
end
```

## Auto-save Configuration

### Component-specific Auto-save Defaults
- **Keybinds**: Always auto-save (cannot be disabled)
- **Checkboxes**: Auto-save enabled by default (opt-out with `auto_save = false`)
- **Color Pickers**: Auto-save enabled by default (opt-out with `auto_save = false`)
- **Text Inputs**: Auto-save disabled by default (opt-in with `auto_save = true`)

### File Storage
- Each GUI gets its own `.dat` file: `lxcommon_[unique_plugin_key].dat`
- Uses core API functions: `core.create_data_file()`, `core.write_data_file()`, `core.read_data_file()`
- Simple key=value format with type conversion
- Immediate saving on value changes

## Architecture

### Module Structure
```
Lx_Common/
├── gui/
│   ├── elements/
│   │   └── menu.lua          # Main Menu class and component management
│   ├── functions/
│   │   ├── input.lua         # Mouse and keyboard input handling
│   │   └── rendering.lua     # All rendering logic and visual effects
│   └── utils/
│       ├── constants.lua     # Shared constants and state
│       └── helpers.lua       # Utility functions
├── header.lua                # Plugin metadata
├── main.lua                  # Main entry point and registration
└── README.md                 # This file
```

### Key Features
- **Memory Safe**: Comprehensive nil checks and fallback values
- **Performance Optimized**: Efficient rendering and input handling
- **Extensible**: Easy to add new component types
- **User Friendly**: Intuitive API with sensible defaults

## Requirements

- Game environment with `core` API support
- `core.graphics` for rendering functions
- `core.input` for input handling
- `core.menu` for base menu components
- File system access for persistence

## Credits

Part of the PS project by Lexxes. Feel free to use, modify, and learn from this code. Credits appreciated but not required. 