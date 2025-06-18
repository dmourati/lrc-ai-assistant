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
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrExportSession = import 'LrExportSession'

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
    progressScope:setCaption("Organizing photos into burst folders...")
    
    local successCount = 0
    local totalCount = #selectedPhotos
    
    -- Get or create base staging directory with date
    local homeDir = LrPathUtils.getStandardFilePath("home")
    local stagingDir = LrPathUtils.child(homeDir, "AI_Staging")
    local currentDate = os.date("%Y-%m-%d")
    local dateDir = LrPathUtils.child(stagingDir, currentDate)
    
    -- Create date directory if it doesn't exist
    if not LrFileUtils.exists(dateDir) then
        LrFileUtils.createDirectory(dateDir)
    end
    
    -- Process photos in bursts of 9
    local burstSize = 9
    local burstCount = math.ceil(totalCount / burstSize)
    
    for burstIndex = 1, burstCount do
        -- Create burst folder (Burst_001, Burst_002, etc.)
        local burstFolder = string.format("Burst_%03d", burstIndex)
        local burstDir = LrPathUtils.child(dateDir, burstFolder)
        
        if not LrFileUtils.exists(burstDir) then
            LrFileUtils.createDirectory(burstDir)
        end
        
        -- Process photos for this burst
        local startPhoto = (burstIndex - 1) * burstSize + 1
        local endPhoto = math.min(burstIndex * burstSize, totalCount)
        local burstPhotoCount = endPhoto - startPhoto + 1
        
        for photoIndex = startPhoto, endPhoto do
            local photo = selectedPhotos[photoIndex]
            
            progressScope:setCaption("Copying photo " .. photoIndex .. " of " .. totalCount .. " to " .. burstFolder .. "...")
            progressScope:setPortionComplete(photoIndex / totalCount)
            
            local success = BatchProcessor.copyPhotoToBurst(photo, burstDir)
            if success then
                successCount = successCount + 1
            end
        end
        
        -- Create job.json for this burst
        BatchProcessor.createJobJson(burstDir, selectedPhotos, startPhoto, endPhoto)
    end
    
    progressScope:setCaption("Photos staged for processing!")
    progressScope:setPortionComplete(1.0)
    
    -- Show completion dialog
    LrDialogs.message(
        "Photos Staged for AI Processing",
        "Successfully organized " .. successCount .. " of " .. totalCount .. " photos into " .. burstCount .. " burst folders.\n\n" ..
        "Structure: AI_Staging/" .. currentDate .. "/Burst_001, Burst_002, etc.\n\n" ..
        "Your photo watcher will detect these files and trigger the automated\n" ..
        "Croatian Football Federation (HNS) soccer analysis workflow.",
        "info"
    )
end

-- Export photo as JPG to specific burst directory
function BatchProcessor.copyPhotoToBurst(photo, burstDir)
    -- Get base filename without extension and create JPG filename
    local sourcePath = photo:getRawMetadata('path')
    if not sourcePath then
        if log then log:info("Could not get source path for photo") end
        return false
    end
    
    local baseFilename = LrPathUtils.leafName(sourcePath)
    -- Remove original extension and add .jpg
    local jpgFilename = baseFilename:gsub("%.[^%.]*$", "") .. ".jpg"
    local destPath = LrPathUtils.child(burstDir, jpgFilename)
    
    -- Skip if JPG already exists
    if LrFileUtils.exists(destPath) then
        return true
    end
    
    -- Export settings for JPG conversion
    local exportSettings = {
        LR_format = "JPEG",
        LR_jpeg_quality = 0.9,
        LR_size_doConstrain = true,
        LR_size_maxHeight = 1024,
        LR_size_resizeType = 'longEdge',
        LR_size_units = 'pixels',
        LR_export_destinationType = "specificFolder",
        LR_export_destinationPathPrefix = burstDir,
        LR_export_useSubfolder = false,
        LR_renamingTokensOn = true,
        LR_tokens = jpgFilename:gsub("%.jpg$", ""), -- Remove .jpg for token
        LR_tokenCustomString = "",
        LR_collisionHandling = "overwrite",
        LR_embeddedMetadataOption = "all"
    }
    
    -- Perform export
    local success = false
    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = exportSettings
    })
    
    if exportSession then
        exportSession:doExportOnCurrentTask()
        success = LrFileUtils.exists(destPath)
        
        if log then
            if success then
                log:info("Exported photo as JPG to burst: " .. destPath)
            else
                log:info("Failed to export photo to burst directory")
            end
        end
    end
    
    return success
end

-- Create job.json file for burst folder
function BatchProcessor.createJobJson(burstDir, selectedPhotos, startPhoto, endPhoto)
    local JSON = require 'JSON'
    
    -- Build files array from the JPG files we just exported
    local files = {}
    for photoIndex = startPhoto, endPhoto do
        local photo = selectedPhotos[photoIndex]
        local sourcePath = photo:getRawMetadata('path')
        if sourcePath then
            local baseFilename = LrPathUtils.leafName(sourcePath)
            -- Convert to JPG filename (same logic as in copyPhotoToBurst)
            local jpgFilename = baseFilename:gsub("%.[^%.]*$", "") .. ".jpg"
            table.insert(files, jpgFilename)
        end
    end
    
    -- Create job configuration matching existing format
    local jobData = {
        files = files
    }
    
    -- Write job.json file
    local jobPath = LrPathUtils.child(burstDir, "job.json")
    local jsonContent = JSON:encode(jobData)
    
    -- Write JSON to file
    local file = io.open(jobPath, "w")
    if file then
        file:write(jsonContent)
        file:close()
        if log then
            log:info("Created job.json: " .. jobPath .. " with " .. #files .. " files")
        end
        return true
    else
        if log then
            log:info("Failed to create job.json: " .. jobPath)
        end
        return false
    end
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