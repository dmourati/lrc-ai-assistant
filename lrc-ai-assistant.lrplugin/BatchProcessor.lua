--[[
BatchProcessor.lua - Main batch processing integration for LRC AI Assistant
Extends existing plugin with Assistant API batch capabilities
]]--

local LrTasks = import 'LrTasks'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrDialogs = import 'LrDialogs'
local LrApplication = import 'LrApplication'
local LrSelection = import 'LrSelection'
local LrErrors = import 'LrErrors'

local AssistantAPI = require 'AssistantAPI'

local BatchProcessor = {}


-- Main batch processing function called from menu
function BatchProcessor.processBatchSelection()
    LrTasks.startAsyncTask(function()
        local catalog = LrApplication.activeCatalog()
        local selectedPhotos = catalog:getTargetPhotos()
        
        if not selectedPhotos or #selectedPhotos == 0 then
            LrDialogs.message("No Photos Selected", "Please select photos to process with AI Assistant.", "info")
            return
        end
        
        if #selectedPhotos == 1 then
            local result = LrDialogs.confirm(
                "Single Photo Selected",
                "You have only one photo selected. Batch processing works best with multiple related images. Continue anyway?",
                "Continue",
                "Cancel"
            )
            if result == "cancel" then
                return
            end
        end
        
        -- Show confirmation dialog
        local message = "Copy " .. #selectedPhotos .. " selected photos to AI_Staging for processing?\n\n"
        message = message .. "This will:\n"
        message = message .. "• Copy photos to AI_Staging directory\n"
        message = message .. "• Trigger your photo watcher for automated HNS analysis\n"
        message = message .. "• Processed results will appear in AI_Processed"
        
        local result = LrDialogs.confirm(
            "Stage Photos for AI Processing",
            message,
            "Copy to Staging",
            "Cancel"
        )
        
        if result == "cancel" then
            return
        end
        
        -- Process with progress dialog using correct LrFunctionContext pattern
        LrFunctionContext.callWithContext("Batch Processing", function(context)
            local progressScope = LrProgressScope({
                title = "AI Assistant Batch Processing",
                functionContext = context
            })
            BatchProcessor.processBatchWithProgress(selectedPhotos, progressScope)
        end)
    end)
end

-- Process batch with progress reporting
function BatchProcessor.processBatchWithProgress(selectedPhotos, progressScope)
    progressScope:setCaption("Copying photos to AI_Staging...")
    
    local successCount = 0
    local totalCount = #selectedPhotos
    
    -- Copy each photo to AI_Staging for photo watcher processing
    for i, photo in ipairs(selectedPhotos) do
        progressScope:setCaption("Copying photo " .. i .. " of " .. totalCount .. " to AI_Staging...")
        progressScope:setPortionComplete(i / totalCount)
        
        local success = BatchProcessor.stagePhotoForProcessing(photo)
        if success then
            successCount = successCount + 1
        end
    end
    
    progressScope:setCaption("Photos staged for processing!")
    progressScope:setPortionComplete(1.0)
    
    -- Show completion dialog
    LrDialogs.message(
        "Photos Staged for AI Processing",
        "Successfully copied " .. successCount .. " of " .. totalCount .. " photos to AI_Staging.\n\n" ..
        "Your photo watcher will detect these files and trigger the automated\n" ..
        "Croatian Football Federation (HNS) soccer analysis workflow.\n\n" ..
        "Processed results will appear in AI_Processed when complete.",
        "info"
    )
end

-- Copy photo to staging for photo watcher processing
function BatchProcessor.stagePhotoForProcessing(photo)
    return BatchProcessor.copyToStaging(photo)
end

-- Copy photo to AI_Staging for photo watcher processing
function BatchProcessor.copyToStaging(photo)
    local LrPathUtils = import 'LrPathUtils'
    local LrFileUtils = import 'LrFileUtils'
    
    -- Get source file path
    local sourcePath = photo:getRawMetadata('path')
    if not sourcePath then
        if log then log:info("Could not get source path for photo") end
        return false
    end
    
    -- Use AI_Staging directory in home folder
    local homeDir = LrPathUtils.getStandardFilePath("home")
    local stagingDir = LrPathUtils.child(homeDir, "AI_Staging")
    
    -- Verify AI_Staging directory exists
    if not LrFileUtils.exists(stagingDir) then
        if log then log:info("AI_Staging directory not found at: " .. stagingDir) end
        return false
    end
    
    -- Get filename and create destination path
    local filename = LrPathUtils.leafName(sourcePath)
    local destPath = LrPathUtils.child(stagingDir, filename)
    
    -- Copy file to AI_Staging directory (preserve original)
    if LrFileUtils.exists(sourcePath) and not LrFileUtils.exists(destPath) then
        local success = LrFileUtils.copy(sourcePath, destPath)
        if log then
            if success then
                log:info("Copied photo to staging: " .. destPath)
            else
                log:info("Failed to copy photo to AI_Staging directory")
            end
        end
        return success
    end
    
    return true -- Already exists, consider successful
end


-- Apply hierarchical keywords
function BatchProcessor.applyKeywords(photo, keywords)
    local catalog = LrApplication.activeCatalog()
    local keywordRoot = "AI Assistant Batch"
    
    -- Create or get root keyword
    local rootKeyword = catalog:createKeyword(keywordRoot, {}, false, nil, true)
    
    -- Process keywords hierarchically
    for _, keywordData in ipairs(keywords) do
        if type(keywordData) == "string" then
            -- Simple keyword
            local keyword = catalog:createKeyword(keywordData, {}, false, rootKeyword, true)
            photo:addKeyword(keyword)
        elseif type(keywordData) == "table" and keywordData.category and keywordData.keywords then
            -- Hierarchical keyword
            local categoryKeyword = catalog:createKeyword(keywordData.category, {}, false, rootKeyword, true)
            
            for _, subKeyword in ipairs(keywordData.keywords) do
                local keyword = catalog:createKeyword(subKeyword, {}, false, categoryKeyword, true)
                photo:addKeyword(keyword)
            end
        end
    end
end

-- Check if field should be updated based on preferences
function BatchProcessor.shouldUpdateField(fieldType, currentValue)
    local prefs = BatchProcessor.prefs
    
    -- Check if review mode is enabled for this field
    local reviewPref = "review" .. fieldType:gsub("^%l", string.upper)  -- Convert to camelCase
    if prefs[reviewPref] then
        -- In review mode, only update if field is empty
        return not currentValue or currentValue == ""
    end
    
    -- Default: only update empty fields
    return not currentValue or currentValue == ""
end

return BatchProcessor