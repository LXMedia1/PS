-- Binary Heap with decrease-key support
-- O(log n) push, pop, and decrease operations
-- Used for A* priority queue

local Heap = {}
Heap.__index = Heap

function Heap.new()
    return setmetatable({
        n = 0,      -- Current size
        node = {},  -- Node IDs at each heap position
        f = {},     -- f-scores at each heap position
        pos = {},   -- Map: nodeId -> heap position (for decrease-key)
    }, Heap)
end

function Heap:clear()
    self.n = 0
    -- Note: We reuse arrays, just reset count
    -- Old values will be overwritten on next use
end

function Heap:size()
    return self.n
end

function Heap:empty()
    return self.n == 0
end

-- Internal: swap two positions
function Heap:_swap(i, j)
    local node, f, pos = self.node, self.f, self.pos

    -- Swap nodes and scores
    node[i], node[j] = node[j], node[i]
    f[i], f[j] = f[j], f[i]

    -- Update position map
    pos[node[i]] = i
    pos[node[j]] = j
end

-- Internal: bubble up from position i
function Heap:_up(i)
    local f = self.f
    while i > 1 do
        local p = math.floor(i / 2)
        if f[p] <= f[i] then break end
        self:_swap(i, p)
        i = p
    end
end

-- Internal: bubble down from position i
function Heap:_down(i)
    local n, f = self.n, self.f
    while true do
        local l = i * 2
        if l > n then break end

        local r = l + 1
        local m = (r <= n and f[r] < f[l]) and r or l

        if f[i] <= f[m] then break end

        self:_swap(i, m)
        i = m
    end
end

-- Push a new node with given f-score
function Heap:push(nodeId, fScore)
    local n = self.n + 1
    self.n = n

    self.node[n] = nodeId
    self.f[n] = fScore
    self.pos[nodeId] = n

    self:_up(n)
end

-- Decrease the f-score of an existing node
-- Only updates if newF is smaller than current
function Heap:decrease(nodeId, newF)
    local i = self.pos[nodeId]
    if not i or i == 0 then return false end
    if newF >= self.f[i] then return false end

    self.f[i] = newF
    self:_up(i)
    return true
end

-- Pop and return the node with smallest f-score
function Heap:pop()
    local n = self.n
    if n == 0 then return nil end

    local node = self.node[1]
    self.pos[node] = 0  -- Mark as removed

    if n == 1 then
        self.n = 0
        return node
    end

    -- Move last to root
    self.node[1] = self.node[n]
    self.f[1] = self.f[n]
    self.pos[self.node[1]] = 1
    self.n = n - 1

    self:_down(1)
    return node
end

-- Peek at the minimum node without removing
function Heap:peek()
    if self.n == 0 then return nil, nil end
    return self.node[1], self.f[1]
end

-- Check if a node is in the heap
function Heap:contains(nodeId)
    local i = self.pos[nodeId]
    return i and i > 0 and i <= self.n
end

-- Get the f-score of a node (or nil if not present)
function Heap:get_f(nodeId)
    local i = self.pos[nodeId]
    if not i or i == 0 or i > self.n then return nil end
    return self.f[i]
end

return Heap
