-- ===========================
-- NOCTIS LOGGER SYSTEM
-- ===========================

local Logger = {}
Logger.__index = Logger

-- Log levels
Logger.LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    NONE = 5  -- Disable all logging
}

-- Default configuration
Logger.config = {
    level = Logger.LEVELS.INFO,  -- Change to NONE for production
    showTimestamp = true,
    showLevel = true,
    prefix = "[Noctis]",
    colors = {
        DEBUG = "\27[36m",  -- Cyan
        INFO = "\27[32m",   -- Green
        WARN = "\27[33m",   -- Yellow
        ERROR = "\27[31m",  -- Red
        RESET = "\27[0m"    -- Reset
    }
}

-- Create new logger instance
function Logger.new(moduleName)
    local self = setmetatable({}, Logger)
    self.moduleName = moduleName or "Main"
    return self
end

-- Format message with timestamp and level
function Logger:formatMessage(level, message)
    local parts = {}
    
    if self.config.showTimestamp then
        table.insert(parts, os.date("[%H:%M:%S]"))
    end
    
    if self.config.prefix then
        table.insert(parts, self.config.prefix)
    end
    
    if self.config.showLevel then
        local levelName = ""
        for name, value in pairs(self.LEVELS) do
            if value == level then
                levelName = name
                break
            end
        end
        table.insert(parts, string.format("[%s]", levelName))
    end
    
    if self.moduleName then
        table.insert(parts, string.format("[%s]", self.moduleName))
    end
    
    table.insert(parts, tostring(message))
    
    return table.concat(parts, " ")
end

-- Log debug message
function Logger:debug(message)
    if self.config.level <= self.LEVELS.DEBUG then
        local formatted = self:formatMessage(self.LEVELS.DEBUG, message)
        print(self.config.colors.DEBUG .. formatted .. self.config.colors.RESET)
    end
end

-- Log info message
function Logger:info(message)
    if self.config.level <= self.LEVELS.INFO then
        local formatted = self:formatMessage(self.LEVELS.INFO, message)
        print(self.config.colors.INFO .. formatted .. self.config.colors.RESET)
    end
end

-- Log warning message
function Logger:warn(message)
    if self.config.level <= self.LEVELS.WARN then
        local formatted = self:formatMessage(self.LEVELS.WARN, message)
        warn(self.config.colors.WARN .. formatted .. self.config.colors.RESET)
    end
end

-- Log error message
function Logger:error(message)
    if self.config.level <= self.LEVELS.ERROR then
        local formatted = self:formatMessage(self.LEVELS.ERROR, message)
        warn(self.config.colors.ERROR .. formatted .. self.config.colors.RESET)
    end
end

-- Set global log level
function Logger.setLevel(level)
    Logger.config.level = level
end

-- Enable/disable logging completely
function Logger.setEnabled(enabled)
    Logger.config.level = enabled and Logger.LEVELS.INFO or Logger.LEVELS.NONE
end

-- Quick disable all logging for production
function Logger.disableAll()
    Logger.config.level = Logger.LEVELS.NONE
end

-- Quick enable for development
function Logger.enableAll()
    Logger.config.level = Logger.LEVELS.DEBUG
end

-- Global logger instance
_G.Logger = Logger.new("Noctis")

return Logger