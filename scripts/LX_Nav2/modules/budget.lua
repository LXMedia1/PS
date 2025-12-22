-- Budget Module
-- Frame budget helper for yieldable coroutines
-- Allows parsing loops to yield when time budget is exhausted

local Budget = {}
Budget.__index = Budget

--- Create a new Budget instance
-- @param check_every How often to check cpu_ticks (default 128, reduces overhead)
function Budget.new(check_every)
    return setmetatable({
        deadline_ticks = 0,
        check_every = check_every or 128,
        _counter = 0,
    }, Budget)
end

--- Set the deadline for this frame
-- Called once per frame by the TileManager before resuming coroutines
-- @param frame_budget_ms Maximum milliseconds to spend this frame
function Budget:set_deadline_from_ms(frame_budget_ms)
    local now = core.cpu_ticks()
    local ticks_per_ms = core.cpu_ticks_per_second() / 1000.0
    self.deadline_ticks = now + (frame_budget_ms * ticks_per_ms)
    self._counter = 0
end

--- Check if there's time left in the budget
-- @return true if deadline has not been reached
function Budget:time_left()
    return core.cpu_ticks() < self.deadline_ticks
end

--- Step function - call inside tight loops
-- Yields when frame budget is exhausted
-- Only checks ticks every check_every iterations to reduce overhead
-- @param stage Name of current parsing stage (for debugging)
-- @param i Current iteration index
-- @param total Total iterations expected
function Budget:step(stage, i, total)
    self._counter = self._counter + 1

    -- Only check ticks every N iterations to reduce overhead
    if (self._counter % self.check_every) ~= 0 then
        return
    end

    -- Check if we've exceeded the frame budget
    if core.cpu_ticks() >= self.deadline_ticks then
        -- Yield back to TileManager with progress info
        return coroutine.yield("budget", stage, i, total)
    end
end

--- Get elapsed time since deadline was set (for debugging)
-- @return elapsed milliseconds (negative if before deadline)
function Budget:elapsed_ms()
    local now = core.cpu_ticks()
    local ticks_per_ms = core.cpu_ticks_per_second() / 1000.0
    -- This calculates time UNTIL deadline (positive = time left, negative = overrun)
    return (self.deadline_ticks - now) / ticks_per_ms
end

return Budget