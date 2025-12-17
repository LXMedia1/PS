local Lx_Debug = {}
Lx_Debug.__index = Lx_Debug

-----------------------------------------------------------
-- Log Levels
-----------------------------------------------------------
Lx_Debug.LogLevel = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4,
    CRITICAL = 5
}

local LEVEL_NAMES = {
    [1] = "DEBUG",
    [2] = "INFO",
    [3] = "WARNING",
    [4] = "ERROR",
    [5] = "CRITICAL"
}

-----------------------------------------------------------
-- Default Configuration
-----------------------------------------------------------
local DEFAULT_CONFIG = {
    logLevel = 2,
    enableConsole = true,
    enableFile = true,
    logFile = "lx_debug.log",
    bufferSize = 50,
    flushInterval = 5.0,
    enablePerformance = true,
    component = "Lx_Debug"
}

-----------------------------------------------------------
-- Constructor
-----------------------------------------------------------
function Lx_Debug:new(config)
    local instance = setmetatable({}, Lx_Debug)

    instance.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        instance.config[k] = v
    end
    if config then
        for k, v in pairs(config) do
            instance.config[k] = v
        end
    end

    instance.buffer = {}
    instance.lastFlush = 0
    instance.performanceTraces = {}
    instance.performanceStats = {}
    instance.fileInitialized = false

    if instance.config.enableFile then
        instance:initFile()
    end

    return instance
end

-----------------------------------------------------------
-- File Initialization
-----------------------------------------------------------
function Lx_Debug:initFile()
    if self.fileInitialized then return end

    if core.create_log_file then
        core.create_log_file(self.config.logFile)
        self.fileInitialized = true
    end
end

-----------------------------------------------------------
-- Get Timestamp
-----------------------------------------------------------
function Lx_Debug:getTimestamp()
    if GetTime then
        return GetTime()
    elseif core.get_time then
        return core.get_time()
    else
        return 0
    end
end

-----------------------------------------------------------
-- Format Metadata
-----------------------------------------------------------
function Lx_Debug:formatMetadata(metadata)
    if not metadata or type(metadata) ~= "table" then
        return ""
    end

    local parts = {}
    for k, v in pairs(metadata) do
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end

    if #parts == 0 then
        return ""
    end

    return " {" .. table.concat(parts, ", ") .. "}"
end

-----------------------------------------------------------
-- Format Message
-----------------------------------------------------------
function Lx_Debug:formatMessage(level, message, metadata)
    local timestamp = self:getTimestamp()
    local levelName = LEVEL_NAMES[level] or "UNKNOWN"
    local component = self.config.component
    local metaStr = self:formatMetadata(metadata)

    return string.format("[%.3f] [%s] %s: %s%s",
        timestamp, levelName, component, message, metaStr)
end

-----------------------------------------------------------
-- Write to Console
-----------------------------------------------------------
function Lx_Debug:writeToConsole(level, formattedMessage)
    if not self.config.enableConsole then return end

    if level >= Lx_Debug.LogLevel.ERROR then
        if core.log_error then
            core.log_error(formattedMessage)
        elseif print then
            print(formattedMessage)
        end
    elseif level >= Lx_Debug.LogLevel.WARNING then
        if core.log_warning then
            core.log_warning(formattedMessage)
        elseif print then
            print(formattedMessage)
        end
    else
        if core.log then
            core.log(formattedMessage)
        elseif print then
            print(formattedMessage)
        end
    end
end

-----------------------------------------------------------
-- Write to File Buffer
-----------------------------------------------------------
function Lx_Debug:writeToBuffer(formattedMessage)
    if not self.config.enableFile then return end

    table.insert(self.buffer, formattedMessage)

    if #self.buffer >= self.config.bufferSize then
        self:flush()
    end
end

-----------------------------------------------------------
-- Flush Buffer to File
-----------------------------------------------------------
function Lx_Debug:flush()
    if #self.buffer == 0 then return end
    if not self.config.enableFile then return end

    if not self.fileInitialized then
        self:initFile()
    end

    if core.write_log_file then
        local content = table.concat(self.buffer, "\n") .. "\n"
        core.write_log_file(self.config.logFile, content)
    end

    self.buffer = {}
    self.lastFlush = self:getTimestamp()
end

-----------------------------------------------------------
-- Core Log Function
-----------------------------------------------------------
function Lx_Debug:log(level, message, metadata)
    if level < self.config.logLevel then return end

    local formattedMessage = self:formatMessage(level, message, metadata)

    self:writeToConsole(level, formattedMessage)
    self:writeToBuffer(formattedMessage)

    local currentTime = self:getTimestamp()
    if currentTime - self.lastFlush >= self.config.flushInterval then
        self:flush()
    end
end

-----------------------------------------------------------
-- Convenience Log Functions
-----------------------------------------------------------
function Lx_Debug:debug(message, metadata)
    self:log(Lx_Debug.LogLevel.DEBUG, message, metadata)
end

function Lx_Debug:info(message, metadata)
    self:log(Lx_Debug.LogLevel.INFO, message, metadata)
end

function Lx_Debug:warn(message, metadata)
    self:log(Lx_Debug.LogLevel.WARNING, message, metadata)
end

function Lx_Debug:error(message, metadata)
    self:log(Lx_Debug.LogLevel.ERROR, message, metadata)
end

function Lx_Debug:critical(message, metadata)
    self:log(Lx_Debug.LogLevel.CRITICAL, message, metadata)
end

-----------------------------------------------------------
-- Configuration Setters
-----------------------------------------------------------
function Lx_Debug:setLogLevel(level)
    self.config.logLevel = level
end

function Lx_Debug:setConsoleEnabled(enabled)
    self.config.enableConsole = enabled
end

function Lx_Debug:setFileEnabled(enabled)
    self.config.enableFile = enabled
    if enabled and not self.fileInitialized then
        self:initFile()
    end
end

-----------------------------------------------------------
-- Performance Tracking
-----------------------------------------------------------
function Lx_Debug:startTrace(operationId)
    if not self.config.enablePerformance then return end

    self.performanceTraces[operationId] = self:getTimestamp()
end

function Lx_Debug:endTrace(operationId, metadata)
    if not self.config.enablePerformance then return 0 end

    local startTime = self.performanceTraces[operationId]
    if not startTime then
        self:warn("endTrace called without startTrace", {operationId = operationId})
        return 0
    end

    local endTime = self:getTimestamp()
    local duration = (endTime - startTime) * 1000

    self.performanceTraces[operationId] = nil

    if not self.performanceStats[operationId] then
        self.performanceStats[operationId] = {
            count = 0,
            total = 0,
            min = math.huge,
            max = 0
        }
    end

    local stats = self.performanceStats[operationId]
    stats.count = stats.count + 1
    stats.total = stats.total + duration
    stats.min = math.min(stats.min, duration)
    stats.max = math.max(stats.max, duration)

    local meta = metadata or {}
    meta.duration_ms = string.format("%.2f", duration)
    self:debug("Trace '" .. operationId .. "' completed", meta)

    return duration
end

function Lx_Debug:getPerformanceStats(operationId)
    if operationId then
        local stats = self.performanceStats[operationId]
        if stats and stats.count > 0 then
            return {
                count = stats.count,
                avg = stats.total / stats.count,
                min = stats.min,
                max = stats.max,
                total = stats.total
            }
        end
        return nil
    end

    local allStats = {}
    for id, stats in pairs(self.performanceStats) do
        if stats.count > 0 then
            allStats[id] = {
                count = stats.count,
                avg = stats.total / stats.count,
                min = stats.min,
                max = stats.max,
                total = stats.total
            }
        end
    end
    return allStats
end

function Lx_Debug:resetPerformanceStats(operationId)
    if operationId then
        self.performanceStats[operationId] = nil
    else
        self.performanceStats = {}
    end
end

-----------------------------------------------------------
-- Child Logger
-----------------------------------------------------------
function Lx_Debug:createChild(component, additionalConfig)
    local childConfig = {}
    for k, v in pairs(self.config) do
        childConfig[k] = v
    end

    childConfig.component = self.config.component .. "." .. component

    if additionalConfig then
        for k, v in pairs(additionalConfig) do
            childConfig[k] = v
        end
    end

    local child = Lx_Debug:new(childConfig)
    child.buffer = self.buffer
    child.performanceStats = self.performanceStats
    child.fileInitialized = self.fileInitialized

    return child
end

-----------------------------------------------------------
-- Global Instance
-----------------------------------------------------------
local defaultLogger = Lx_Debug:new()

-----------------------------------------------------------
-- Module Export
-----------------------------------------------------------
Lx_Debug.default = defaultLogger

return Lx_Debug
