-- LX_Nav Debug Module
-- Performance tracking and logging using cpu_ticks

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")

local Debug = {}

-- Constants
local LOG_FILE = "LX_Nav.log"
local PERF_LOG_FILE = "LX_Nav_perf.log"
local ticks_per_ms = nil  -- Cached for performance

-- State
local frame_times = {}  -- Rolling window for FPS calculation
local max_frame_samples = 60

-- Performance tracking
local perf_stack = {}  -- Stack of {name, start_ticks}
local perf_log_created = false
local freeze_threshold_ms = 16  -- Log if operation takes > 16ms (1 frame at 60fps)

-- Initialize debug system
function Debug.init()
    core.create_log_file(LOG_FILE)
    ticks_per_ms = core.cpu_ticks_per_second() / 1000
    Debug.log("=== LX_Nav Debug Initialized ===")
    Debug.log(string.format("cpu_ticks_per_second: %d", core.cpu_ticks_per_second()))
    Debug.log(string.format("ticks_per_ms: %.2f", ticks_per_ms))
end

-- Log message to file
function Debug.log(msg)
    core.write_log_file(LOG_FILE, msg .. "\n")
end

-- Log error (also to console)
function Debug.log_error(msg)
    local full_msg = "[ERROR] " .. msg
    Debug.log(full_msg)
    core.log_error("[LX_Nav] " .. msg)
end

-- Log warning
function Debug.log_warning(msg)
    local full_msg = "[WARN] " .. msg
    Debug.log(full_msg)
    core.log_warning("[LX_Nav] " .. msg)
end

-- Get current ticks
function Debug.get_ticks()
    return core.cpu_ticks()
end

-- Convert ticks to milliseconds
function Debug.ticks_to_ms(ticks)
    if not ticks_per_ms then
        ticks_per_ms = core.cpu_ticks_per_second() / 1000
    end
    return ticks / ticks_per_ms
end

-- Measure a function's execution time
-- Usage: local result = Debug.measure("operation_name", my_function, arg1, arg2)
function Debug.measure(name, func, ...)
    local start_ticks = core.cpu_ticks()
    local results = {func(...)}
    local elapsed_ticks = core.cpu_ticks() - start_ticks
    local elapsed_ms = Debug.ticks_to_ms(elapsed_ticks)
    Debug.log(string.format("%s: %.3f ms", name, elapsed_ms))
    return table.unpack(results)
end

-- Start a named timer (returns start ticks)
function Debug.timer_start()
    return core.cpu_ticks()
end

-- End a named timer and log result
function Debug.timer_end(start_ticks, name)
    local elapsed_ticks = core.cpu_ticks() - start_ticks
    local elapsed_ms = Debug.ticks_to_ms(elapsed_ticks)
    Debug.log(string.format("%s: %.3f ms", name, elapsed_ms))
    return elapsed_ms
end

-- Update frame timing (call once per frame)
function Debug.update_frame_time()
    local dt = core.delta_time()
    table.insert(frame_times, dt)
    if #frame_times > max_frame_samples then
        table.remove(frame_times, 1)
    end
end

-- Get average FPS
function Debug.get_fps()
    if #frame_times == 0 then
        return 0
    end
    local total = 0
    for _, dt in ipairs(frame_times) do
        total = total + dt
    end
    local avg_dt = total / #frame_times
    if avg_dt > 0 then
        return 1 / avg_dt
    end
    return 0
end

-- Get current frame time in ms
function Debug.get_frame_time_ms()
    return core.delta_time() * 1000
end

-- Render on-screen debug stats
function Debug.render_stats(extra_lines)
    local stats = {}

    -- FPS and frame time
    local fps = Debug.get_fps()
    local frame_ms = Debug.get_frame_time_ms()
    table.insert(stats, string.format("FPS: %.1f", fps))
    table.insert(stats, string.format("Frame: %.2f ms", frame_ms))

    -- Add extra lines if provided
    if extra_lines then
        for _, line in ipairs(extra_lines) do
            table.insert(stats, line)
        end
    end

    -- Render
    local y = 10
    local col = color.new(0, 255, 100, 255)
    for _, line in ipairs(stats) do
        core.graphics.text_2d(line, vec2.new(10, y), 12, col, false)
        y = y + 14
    end
end

-- ===========================================
-- PERFORMANCE TRACKING (FREEZE DETECTION)
-- ===========================================

-- Initialize perf log
local function ensure_perf_log()
    if not perf_log_created then
        core.create_log_file(PERF_LOG_FILE)
        perf_log_created = true
    end
end

-- Log to performance file
local function perf_log(msg)
    ensure_perf_log()
    core.write_log_file(PERF_LOG_FILE, msg .. "\n")
end

--- Start tracking an operation (can be nested)
-- @param name Operation name for logging
function Debug.perf_start(name)
    if not ticks_per_ms then
        ticks_per_ms = core.cpu_ticks_per_second() / 1000
    end
    table.insert(perf_stack, {name = name, start = core.cpu_ticks()})
end

--- End tracking an operation and log if it exceeds threshold
-- @param name Optional - verify matching name
-- @return elapsed_ms Time elapsed
function Debug.perf_end(name)
    if #perf_stack == 0 then
        Debug.log_warning("perf_end called with empty stack: " .. tostring(name))
        return 0
    end

    local entry = table.remove(perf_stack)
    local elapsed_ticks = core.cpu_ticks() - entry.start
    local elapsed_ms = elapsed_ticks / ticks_per_ms

    -- Verify name matches if provided
    if name and name ~= entry.name then
        Debug.log_warning(string.format("perf_end mismatch: expected '%s', got '%s'", entry.name, name))
    end

    -- Log if exceeds threshold (freeze detection)
    if elapsed_ms > freeze_threshold_ms then
        local indent = string.rep("  ", #perf_stack)
        perf_log(string.format("%s[FREEZE] %s: %.1f ms (threshold: %d ms)",
            indent, entry.name, elapsed_ms, freeze_threshold_ms))
    end

    return elapsed_ms
end

--- Set freeze detection threshold
-- @param ms Milliseconds threshold (default 16 = 60fps frame budget)
function Debug.set_freeze_threshold(ms)
    freeze_threshold_ms = ms
end

--- Log performance summary (call periodically)
function Debug.perf_summary(name, elapsed_ms)
    if elapsed_ms > freeze_threshold_ms then
        perf_log(string.format("[SLOW] %s: %.1f ms", name, elapsed_ms))
    end
end

--- Wrap a function with performance tracking
-- @param name Operation name
-- @param func Function to track
-- @return Wrapped function
function Debug.perf_wrap(name, func)
    return function(...)
        Debug.perf_start(name)
        local results = {func(...)}
        Debug.perf_end(name)
        return table.unpack(results)
    end
end

return Debug
