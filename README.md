# Project Sylvanas (PS)

A comprehensive Lua-based plugin framework for game automation and GUI development.

## Features

- **LxCommon GUI System**: Advanced drawing and UI framework with direct rendering capabilities
- **Modular Architecture**: Clean separation of concerns with reusable components
- **Plugin Ecosystem**: Extensible system for custom plugins and rotations

## GUI System

The project includes a powerful GUI framework (`LxCommon`) that provides:

- Direct rendering without traditional windows
- Rich UI components (buttons, sliders, checkboxes, etc.)
- Input handling with click-through prevention
- Animation effects and interactive elements
- Persistent settings and state management

**📖 [Complete GUI Documentation](LxCommon_GUI_Documentation.md)**

## Quick Start

```lua
-- Create a new GUI
local my_gui = LxCommon.Gui.register("My GUI", 400, 300)

-- Set up the render callback
my_gui:set_render_callback(function()
    my_gui:AddLabel("Hello World", 10, 10)
    my_gui:AddButton("Click Me", 10, 50, 100, 30, function()
        print("Button clicked!")
    end)
end)
```

## Project Structure

```
PS/
├── scripts/
│   ├── Lx_Common/        # GUI framework
│   ├── LX_Debug/         # Debug utilities
│   └── [plugins]/        # Various game plugins
└── README.md
```

## Contributing

This project follows modular development principles. Each component is designed to be independent and reusable across different game environments.
