local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrApplication = import 'LrApplication'
local LrHttp = import 'LrHttp'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrExportSession = import 'LrExportSession'

local ASSISTANT_ID = "asst_HQan3G9EY0pDEpFaQG97idQL"
local OPENAI_API_BASE = "https://api.openai.com/v1"

local function createThread(apiKey)
    local headers = {
        { field = "Authorization", value = "Bearer " .. apiKey },
        { field = "Content-Type", value = "application/json" },
        { field = "OpenAI-Beta", value = "assistants=v2" }
    }
    
    local response, responseHeaders = LrHttp.post(OPENAI_API_BASE .. "/threads", "{}", headers)
    
    if responseHeaders.status == 200 then
        local threadData = JSON:decode(response)
        return threadData.id
    else
        error("Failed to create thread: " .. (response or "Unknown error"))
    end
end

local function processBatch(selectedPhotos, apiKey)
    LrDialogs.message("Starting Batch Process", 
        "Creating AI thread and preparing photos...\n\n" ..
        "This is a demo - real implementation coming next!", "info")
    
    -- TODO: Real implementation will:
    -- 1. Create OpenAI thread
    -- 2. Export photos to temp files
    -- 3. Upload photos to Assistant
    -- 4. Process with Assistant
    -- 5. Parse results and apply metadata
    
    LrDialogs.message("Batch Complete", 
        "Demo completed for " .. #selectedPhotos .. " photos.\n\n" ..
        "Ready to implement full Assistant API integration!", "info")
end

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local selectedPhotos = catalog:getTargetPhotos()
    
    if not selectedPhotos or #selectedPhotos == 0 then
        LrDialogs.message("No Photos Selected", "Please select photos for batch processing.", "info")
        return
    end
    
    local apiKey = prefs.chatgptApiKey
    if not apiKey or apiKey == "" then
        LrDialogs.message("API Key Missing", "Please configure your ChatGPT API key in Plugin Manager first.", "warning")
        return
    end
    
    local result = LrDialogs.confirm(
        "Batch Process " .. #selectedPhotos .. " Photos",
        "This will upload " .. #selectedPhotos .. " photos to OpenAI Assistant for analysis.\n\n" ..
        "Assistant ID: " .. ASSISTANT_ID .. "\n" ..
        "Estimated cost: ~$" .. string.format("%.2f", #selectedPhotos * 0.02) .. "\n\n" ..
        "Continue?",
        "Process Batch",
        "Cancel"
    )
    
    if result == "cancel" then
        return
    end
    
    processBatch(selectedPhotos, apiKey)
end)
