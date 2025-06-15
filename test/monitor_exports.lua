-- Monitor AI_Staging exports to ensure no files are lost
-- This script watches the AI_Staging folder and logs all export activity

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'
local json = require 'json'

-- Configuration
local STAGING_DIR = "/Users/demetrimouratis/AI_Staging"
local LOG_FILE = "/Users/demetrimouratis/AI_Staging/export_monitor.log"
local MONITOR_INTERVAL = 2 -- seconds

-- State tracking
local KNOWN_BURSTS = {}
local MONITORING = true

-- Logging function
local function log(message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logEntry = string.format("[%s] %s\n", timestamp, message)
    
    -- Write to log file
    local logFile = io.open(LOG_FILE, "a")
    if logFile then
        logFile:write(logEntry)
        logFile:close()
    end
    
    -- Also print to console
    print(logEntry:sub(1, -2)) -- Remove trailing newline
end

-- Scan a burst folder and return file info
local function scanBurstFolder(burstPath)
    local info = {
        path = burstPath,
        jpgFiles = {},
        hasJobJson = false,
        totalFiles = 0,
        timestamp = os.time()
    }
    
    if not LrFileUtils.exists(burstPath) then
        return info
    end
    
    local items = LrFileUtils.directoryEntries(burstPath)
    if items then
        for item in items do
            local itemPath = LrPathUtils.child(burstPath, item)
            if LrFileUtils.exists(itemPath) then
                info.totalFiles = info.totalFiles + 1
                
                if string.lower(LrPathUtils.extension(item)) == "jpg" then
                    table.insert(info.jpgFiles, item)
                elseif item == "job.json" then
                    info.hasJobJson = true
                end
            end
        end
    end
    
    return info
end

-- Check job.json content matches actual files
local function validateJobJson(burstPath, actualJpgs)
    local jobPath = LrPathUtils.child(burstPath, "job.json")
    if not LrFileUtils.exists(jobPath) then
        return false, "job.json missing"
    end
    
    local jobFile = io.open(jobPath, "r")
    if not jobFile then
        return false, "Cannot read job.json"
    end
    
    local content = jobFile:read("*all")
    jobFile:close()
    
    local success, jobData = pcall(json.decode, content)
    if not success then
        return false, "Invalid JSON"
    end
    
    if not jobData.files then
        return false, "No 'files' array in job.json"
    end
    
    -- Check counts match
    if #jobData.files ~= #actualJpgs then
        return false, string.format("Count mismatch: job.json has %d, folder has %d", #jobData.files, #actualJpgs)
    end
    
    -- Check all files are listed
    for _, actualFile in ipairs(actualJpgs) do
        local found = false
        for _, listedFile in ipairs(jobData.files) do
            if listedFile == actualFile then
                found = true
                break
            end
        end
        if not found then
            return false, "File not in job.json: " .. actualFile
        end
    end
    
    return true, "Valid"
end

-- Scan all burst folders for today
local function scanTodaysBursts()
    local currentDate = LrDate.currentTime()
    local dateStr = LrDate.timeToUserFormat(currentDate, "%Y-%m-%d")
    local dateFolder = LrPathUtils.child(STAGING_DIR, dateStr)
    
    if not LrFileUtils.exists(dateFolder) then
        return {}
    end
    
    local bursts = {}
    local items = LrFileUtils.directoryEntries(dateFolder)
    if items then
        for item in items do
            if string.match(item, "^Burst_%d%d%d$") then
                local burstPath = LrPathUtils.child(dateFolder, item)
                local burstInfo = scanBurstFolder(burstPath)
                bursts[item] = burstInfo
            end
        end
    end
    
    return bursts
end

-- Monitor for changes and log them
local function monitorExports()
    log("Export monitor started")
    log("Monitoring: " .. STAGING_DIR)
    
    while MONITORING do
        local currentBursts = scanTodaysBursts()
        
        -- Check for new bursts
        for burstName, burstInfo in pairs(currentBursts) do
            if not KNOWN_BURSTS[burstName] then
                log(string.format("NEW BURST: %s (folder created)", burstName))
                KNOWN_BURSTS[burstName] = burstInfo
            else
                local oldInfo = KNOWN_BURSTS[burstName]
                
                -- Check for file changes
                if #burstInfo.jpgFiles ~= #oldInfo.jpgFiles then
                    log(string.format("BURST %s: JPG count changed from %d to %d", 
                        burstName, #oldInfo.jpgFiles, #burstInfo.jpgFiles))
                    
                    -- List new files
                    for _, jpgFile in ipairs(burstInfo.jpgFiles) do
                        local wasKnown = false
                        for _, oldJpg in ipairs(oldInfo.jpgFiles) do
                            if jpgFile == oldJpg then
                                wasKnown = true
                                break
                            end
                        end
                        if not wasKnown then
                            log(string.format("  NEW FILE: %s", jpgFile))
                        end
                    end
                    
                    -- Check for removed files
                    for _, oldJpg in ipairs(oldInfo.jpgFiles) do
                        local stillExists = false
                        for _, jpgFile in ipairs(burstInfo.jpgFiles) do
                            if jpgFile == oldJpg then
                                stillExists = true
                                break
                            end
                        end
                        if not stillExists then
                            log(string.format("  REMOVED FILE: %s", oldJpg))
                        end
                    end
                end
                
                -- Check job.json
                if burstInfo.hasJobJson and not oldInfo.hasJobJson then
                    log(string.format("BURST %s: job.json created", burstName))
                elseif not burstInfo.hasJobJson and oldInfo.hasJobJson then
                    log(string.format("BURST %s: job.json REMOVED", burstName))
                end
                
                KNOWN_BURSTS[burstName] = burstInfo
            end
            
            -- Validate each burst
            if burstInfo.hasJobJson and #burstInfo.jpgFiles > 0 then
                local isValid, errorMsg = validateJobJson(burstInfo.path, burstInfo.jpgFiles)
                if not isValid then
                    log(string.format("VALIDATION ERROR in %s: %s", burstName, errorMsg))
                end
            end
        end
        
        -- Check for removed bursts
        for knownBurst, _ in pairs(KNOWN_BURSTS) do
            if not currentBursts[knownBurst] then
                log(string.format("BURST REMOVED: %s", knownBurst))
                KNOWN_BURSTS[knownBurst] = nil
            end
        end
        
        LrTasks.sleep(MONITOR_INTERVAL)
    end
    
    log("Export monitor stopped")
end

-- Create a summary of current state
local function createSummary()
    log("=== EXPORT SUMMARY ===")
    local totalBursts = 0
    local totalFiles = 0
    
    for burstName, burstInfo in pairs(KNOWN_BURSTS) do
        totalBursts = totalBursts + 1
        totalFiles = totalFiles + #burstInfo.jpgFiles
        
        local status = "OK"
        if not burstInfo.hasJobJson then
            status = "NO job.json"
        elseif #burstInfo.jpgFiles == 0 then
            status = "NO JPEGs"
        else
            local isValid, errorMsg = validateJobJson(burstInfo.path, burstInfo.jpgFiles)
            if not isValid then
                status = "INVALID: " .. errorMsg
            end
        end
        
        log(string.format("  %s: %d JPEGs, %s", burstName, #burstInfo.jpgFiles, status))
    end
    
    log(string.format("Total: %d bursts, %d JPEG files", totalBursts, totalFiles))
    log("===================")
end

-- Start monitoring (run this in background)
local function startMonitoring()
    -- Initial scan
    KNOWN_BURSTS = scanTodaysBursts()
    createSummary()
    
    -- Start monitoring in async task
    LrTasks.startAsyncTask(function()
        monitorExports()
    end)
    
    log("Monitor started in background. Check " .. LOG_FILE .. " for updates.")
end

-- Stop monitoring
local function stopMonitoring()
    MONITORING = false
    createSummary()
end

-- Export functions for manual use
return {
    start = startMonitoring,
    stop = stopMonitoring,
    summary = createSummary,
    scan = scanTodaysBursts
}