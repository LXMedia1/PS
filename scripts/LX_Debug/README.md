# LX Debug - Collision Detection Demo

This project demonstrates collision detection using `core.graphics.trace_line()` to check your surroundings for obstacles and validate movement paths.

## Features

### Collision Detection
- **Radial scanning**: Cast rays in multiple directions around your character
- **Real-time visualization**: See collision results with colored lines
- **Automatic checking**: Continuous monitoring of surroundings
- **Configurable parameters**: Adjust distance, directions, and collision flags

### Visual Feedback
- **Green lines**: Clear paths with no obstacles
- **Red lines**: Paths blocked by obstacles  
- **Red circles**: Mark collision points
- **Blue circle**: Shows scanning radius around player
- **Orange/Cyan line**: Detailed analysis line (thick line showing current flag result)
- **Screen overlay**: Real-time collision flag info and detailed analysis results

### GUI Controls

#### Basic Controls
- **Enable Debug Mode**: Shows detailed logging in console
- **Enable Collision Checks**: Toggle collision detection on/off
- **Auto Check (Continuous)**: Automatically scan every 100ms
- **Show Trace Lines**: Toggle visual display of scan results

#### Configuration
- **Check Distance**: How far to scan (5-50 units)
- **Directions (rays)**: Number of rays to cast (4-16)
- **Collision Flags**: What types of objects to detect (1-15)

#### Actions
- **Check Now**: Perform manual collision scan
- **Analyze All**: Test all 15 collision flags in forward direction

#### Results Display
- **Obstacles found**: Number of blocked directions
- **Clear paths**: Number of open directions

## Collision Flags

The collision flags parameter determines what types of objects the trace_line detects:

### Flag Definitions:
- **Flag 1**: Basic Collision
- **Flag 2**: Doodad Collision (decorative objects)
- **Flag 3**: Basic + Doodad
- **Flag 4**: WMO Collision (World Model Objects - buildings)
- **Flag 5**: Basic + WMO  
- **Flag 6**: Doodad + WMO
- **Flag 7**: Basic + Doodad + WMO (recommended for movement)
- **Flag 8**: WMO Render
- **Flag 9**: Basic + WMO Render
- **Flag 10**: Doodad + WMO Render
- **Flag 11**: Basic + Doodad + WMO Render
- **Flag 12**: WMO + WMO Render
- **Flag 13**: Basic + WMO + WMO Render
- **Flag 14**: Doodad + WMO + WMO Render  
- **Flag 15**: All Collision Types (most comprehensive)

### Recommended Settings:
- **Flag 7**: Best for general movement and pathfinding
- **Flag 15**: Most thorough detection (may include visual-only objects)
- **Flag 1**: Minimal detection for basic terrain only

## Usage Examples

### Basic Obstacle Detection
1. Enable "Show Trace Lines"
2. Click "Check Now" 
3. Observe green/red lines showing clear/blocked paths

### Continuous Monitoring
1. Enable "Auto Check (Continuous)"
2. Move around and watch the lines update in real-time
3. Useful for pathfinding validation

### Pathfinding Integration
Use the collision results in your movement logic:
```lua
-- Example: Find clear direction
for _, result in ipairs(collision_results) do
    if not result.has_collision then
        -- This direction is clear for movement
        local clear_angle = result.angle
        -- Use for pathfinding...
    end
end
```

## Technical Details

- **Scan origin**: Player position + half height offset
- **Scan pattern**: 360-degree radial from player center
- **Update frequency**: 10Hz when auto-check enabled
- **Ray casting**: Uses `core.graphics.trace_line(start_pos, end_pos, flags)`

## Tips

- Start with 8 directions and adjust based on your needs
- Use collision flags `7` for most general obstacle detection
- Enable debug mode to see detailed console output
- Adjust check distance based on your movement speed

This tool is perfect for:
- Validating movement paths before moving
- Creating smart pathfinding systems  
- Debugging collision detection issues
- Understanding your environment layout 