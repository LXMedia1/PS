--[[
    Lx_Nav Binary Heap
    Author: Lexxer

    Min-heap implementation for A* pathfinding open list.
    Elements are sorted by their priority (lowest first).
]]

local BinaryHeap = {}
BinaryHeap.__index = BinaryHeap

-- Create a new empty heap
function BinaryHeap.new()
    local self = setmetatable({}, BinaryHeap)
    self.data = {}      -- {item, priority} pairs
    self.size = 0
    self.positions = {} -- item -> index mapping for decrease_key
    return self
end

-- Check if heap is empty
function BinaryHeap:empty()
    return self.size == 0
end

-- Get current size
function BinaryHeap:count()
    return self.size
end

-- Clear the heap
function BinaryHeap:clear()
    self.data = {}
    self.size = 0
    self.positions = {}
end

-- Parent index
local function parent(i)
    return math.floor(i / 2)
end

-- Left child index
local function left(i)
    return 2 * i
end

-- Right child index
local function right(i)
    return 2 * i + 1
end

-- Swap two elements
function BinaryHeap:swap(i, j)
    local data = self.data
    data[i], data[j] = data[j], data[i]

    -- Update position tracking
    self.positions[data[i].item] = i
    self.positions[data[j].item] = j
end

-- Bubble up (used after insert or decrease_key)
function BinaryHeap:bubble_up(i)
    local data = self.data
    while i > 1 do
        local p = parent(i)
        if data[p].priority <= data[i].priority then
            break
        end
        self:swap(i, p)
        i = p
    end
end

-- Bubble down (used after pop)
function BinaryHeap:bubble_down(i)
    local data = self.data
    local size = self.size

    while true do
        local smallest = i
        local l = left(i)
        local r = right(i)

        if l <= size and data[l].priority < data[smallest].priority then
            smallest = l
        end
        if r <= size and data[r].priority < data[smallest].priority then
            smallest = r
        end

        if smallest == i then
            break
        end

        self:swap(i, smallest)
        i = smallest
    end
end

-- Push an item with a priority
function BinaryHeap:push(item, priority)
    self.size = self.size + 1
    self.data[self.size] = {item = item, priority = priority}
    self.positions[item] = self.size
    self:bubble_up(self.size)
end

-- Pop the item with lowest priority
function BinaryHeap:pop()
    if self.size == 0 then
        return nil
    end

    local data = self.data
    local min = data[1]

    -- Move last element to root
    data[1] = data[self.size]
    self.positions[data[1].item] = 1
    self.positions[min.item] = nil
    data[self.size] = nil
    self.size = self.size - 1

    -- Restore heap property
    if self.size > 0 then
        self:bubble_down(1)
    end

    return min.item, min.priority
end

-- Peek at the minimum without removing
function BinaryHeap:peek()
    if self.size == 0 then
        return nil
    end
    return self.data[1].item, self.data[1].priority
end

-- Check if item exists in heap
function BinaryHeap:contains(item)
    return self.positions[item] ~= nil
end

-- Get priority of an item (nil if not in heap)
function BinaryHeap:get_priority(item)
    local i = self.positions[item]
    if not i then
        return nil
    end
    return self.data[i].priority
end

-- Decrease the priority of an item (must be lower than current)
-- Returns true if successful
function BinaryHeap:decrease_key(item, new_priority)
    local i = self.positions[item]
    if not i then
        return false
    end

    local data = self.data
    if new_priority >= data[i].priority then
        return false
    end

    data[i].priority = new_priority
    self:bubble_up(i)
    return true
end

-- Update or insert: if item exists and new_priority is lower, decrease key
-- If item doesn't exist, push it
function BinaryHeap:upsert(item, priority)
    if self:contains(item) then
        local current = self:get_priority(item)
        if priority < current then
            self:decrease_key(item, priority)
        end
    else
        self:push(item, priority)
    end
end

return BinaryHeap
