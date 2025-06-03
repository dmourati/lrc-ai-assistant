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

-- Initialize batch processor with settings
function BatchProcessor.initialize(prefs)
    local apiKey = prefs.chatgptApiKey  -- Use existing ChatGPT API key
    local assistantId = prefs.assistantId
    
    if not apiKey or apiKey == "" then
        LrErrors.throwUserError("OpenAI API key not configured. Please set it in Plugin Manager.")
    end
    
    if not assistantId or assistantId == "" then
        LrErrors.throwUserError("Assistant ID not configured. Please set it in Plugin Manager.")
    end
    
    AssistantAPI.initialize(apiKey, assistantId)
    BatchProcessor.prefs = prefs
end

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
        local message = "Process " .. #selectedPhotos .. " selected photos with AI Assistant?\n\n"
        message = message .. "This will:\n"
        message = message .. "• Upload images to OpenAI for analysis\n"
        message = message .. "• Generate consistent metadata across the batch\n"
        message = message .. "• Apply results to title, caption, keywords, and alt text\n\n"
        message = message .. "Estimated cost: ~$" .. string.format("%.2f", #selectedPhotos * 0.02)
        
        local result = LrDialogs.confirm(
            "Batch Process with AI Assistant",
            message,
            "Process Batch",
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
    progressScope:setCaption("Initializing AI Assistant...")
    
    -- Initialize Assistant API
    BatchProcessor.initialize(_PLUGIN.preferences)
    
    -- Process batch
    local results = AssistantAPI.processBatch(selectedPhotos, progressScope)
    
    -- Apply metadata to photos
    progressScope:setCaption("Applying metadata to photos...")
    local catalog = LrApplication.activeCatalog()
    
    catalog:withWriteAccessDo("Apply AI Assistant Metadata", function()
        for i, photo in ipairs(selectedPhotos) do
            progressScope:setCaption("Applying metadata to photo " .. i .. " of " .. #selectedPhotos)
            progressScope:setPortionComplete(0.8 + (i / #selectedPhotos) * 0.2)
            
            local metadata = results[photo]
            if metadata then
                BatchProcessor.applyMetadataToPhoto(photo, metadata)
            end
        end
    end)
    
    progressScope:setCaption("Batch processing complete!")
    
    -- Show completion dialog
    LrDialogs.message(
        "Batch Processing Complete",
        "Successfully processed " .. #selectedPhotos .. " photos with AI Assistant.\n\n" ..
        "Generated metadata has been applied to:\n" ..
        "• Photo titles\n" ..
        "• Captions\n" ..
        "• Keywords\n" ..
        "• Alt text",
        "info"
    )
end

-- Apply metadata to individual photo
function BatchProcessor.applyMetadataToPhoto(photo, metadata)
    local updates = {}
    
    -- Apply title
    if metadata.title and BatchProcessor.shouldUpdateField("title", photo:getFormattedMetadata("title")) then
        updates.title = metadata.title
    end
    
    -- Apply caption
    if metadata.caption and BatchProcessor.shouldUpdateField("caption", photo:getFormattedMetadata("caption")) then
        updates.caption = metadata.caption
    end
    
    -- Apply alt text (if supported)
    if metadata.alt_text and BatchProcessor.shouldUpdateField("alt_text", photo:getPropertyForPlugin(_PLUGIN, "alt_text")) then
        photo:setPropertyForPlugin(_PLUGIN, "alt_text", metadata.alt_text)
    end
    
    -- Apply basic metadata
    if next(updates) then
        photo:batchSetMetadata(updates)
    end
    
    -- Apply keywords (requires special handling)
    if metadata.keywords and type(metadata.keywords) == "table" then
        BatchProcessor.applyKeywords(photo, metadata.keywords)
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