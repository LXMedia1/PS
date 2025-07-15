# Project Sylvanas (PS)

## Early Development Warning

**This project is in early development stages.** Features, APIs, and documentation are subject to change. Expect breaking changes between versions. Use at your own risk in production environments.

A comprehensive Lua-based plugin framework for game automation and GUI development.

## Overview

Project Sylvanas provides a modular framework for creating game plugins with advanced GUI capabilities. The system is built around reusable components and clean architectural patterns.

## Key Features

- **LxCommon GUI System**: Advanced drawing and UI framework with direct rendering capabilities
- **Modular Architecture**: Clean separation of concerns with reusable components
- **Plugin Ecosystem**: Extensible system for custom plugins and rotations
- **Persistent Settings**: Automatic save/load system for component states
- **Debug Tools**: Built-in debugging utilities and test environments

## Documentation

This README provides a high-level overview. For detailed information, see the specialized documentation:

- **[LxCommon GUI Documentation](LxCommon_GUI_Documentation.md)** - Complete GUI framework guide
- Individual plugin documentation in their respective directories

## GUI System Overview

The LxCommon GUI framework provides:

- Direct rendering without traditional windows
- Rich UI components (buttons, sliders, checkboxes, color pickers, text inputs)
- Input handling with click-through prevention
- Animation effects and interactive elements
- Automatic persistent settings and state management
- Configurable auto-save for components

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
│   ├── Lx_Common/        # GUI framework and common utilities
│   ├── LX_Debug/         # Debug utilities and test environment
│   ├── core_*/           # Core system plugins
│   ├── ext_*/            # Extension plugins
│   └── [other plugins]/  # Various specialized plugins
├── scripts_data/         # Runtime data and settings
└── docs/                 # Documentation files
```

## Development Status

Current focus areas:
- GUI system stabilization and feature completion
- Save/load system improvements
- Plugin template standardization
- Documentation completion

## Contributing

This project follows modular development principles. Each component is designed to be independent and reusable across different game environments.

**Note:** Due to early development status, contribution guidelines are still being established. Please check back for updates.
