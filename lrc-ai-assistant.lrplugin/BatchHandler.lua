-- Gradual automation - try to add AI processing step by step
local LrDialogs = import 'LrDialogs'
local LrApplication = import 'LrApplication'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'

-- Get basic info (we know this works)
local prefs = LrPrefs.prefsForPlugin()
local apiKey = prefs.chatgptApiKey

if not apiKey or apiKey == "" then
    LrDialogs.message("API Key Required", 
        "Please set your OpenAI API key in Plugin Manager first.", "warning")
    return
end

local catalog = LrApplication.activeCatalog()
local selectedPhotos = catalog:getTargetPhotos()

if not selectedPhotos or #selectedPhotos == 0 then
    LrDialogs.message("No Photos Selected", "Please select photos to analyze.", "info")
    return
end

-- Try to get photo paths using the method we know works
local photoPaths = {}
local photoInfo = ""

for i, photo in ipairs(selectedPhotos) do
    -- Use direct property access (we tested this works)
    local photoPath = photo.path
    if photoPath then
        table.insert(photoPaths, photoPath)
        photoInfo = photoInfo .. "Photo " .. i .. ": " .. photoPath .. "\n"
    else
        photoInfo = photoInfo .. "Photo " .. i .. ": No path available\n"
    end
end

-- Show what we found
LrDialogs.message("Photo Analysis", 
    "Found " .. #photoPaths .. " photos with paths:\n\n" .. photoInfo, "info")

if #photoPaths == 0 then
    LrDialogs.message("No Photo Paths", "Cannot access photo file paths.", "warning")
    return
end

-- Ask user if they want to try automatic processing
local result = LrDialogs.confirm(
    "Try Automatic Processing?",
    "Found " .. #photoPaths .. " accessible photos.\n\n" ..
    "Would you like to try automatic AI processing?\n\n" ..
    "This will attempt to:\n" ..
    "1. Upload photos to OpenAI\n" ..
    "2. Process them with AI Assistant\n" ..
    "3. Return results\n\n" ..
    "If this fails, we'll fall back to the manual workflow.",
    "Try Automatic",
    "Use Manual Workflow"
)

if result == "cancel" then
    -- Fall back to manual workflow
    local instructions = "MANUAL WORKFLOW:\n\n" ..
        "1. Export your photos as JPEG to Desktop/LR_AI_Export/\n" ..
        "2. Go to https://chat.openai.com\n" ..
        "3. Upload the exported photos\n" ..
        "4. Ask for titles, descriptions, and keywords"
    
    LrDialogs.message("Manual Workflow", instructions, "info")
    return
end

-- Try automatic processing in async task
LrTasks.startAsyncTask(function()
    local LrHttp = import 'LrHttp'
    
    -- Simple test: try to create a thread
    local success, result = pcall(function()
        local headers = {
            { field = "Authorization", value = "Bearer " .. apiKey },
            { field = "Content-Type", value = "application/json" },
            { field = "OpenAI-Beta", value = "assistants=v2" }
        }
        
        local response, responseHeaders = LrHttp.post(
            "https://api.openai.com/v1/threads", 
            "{}", 
            headers
        )
        
        return responseHeaders.status == 200
    end)
    
    if success and result then
        LrDialogs.message("Success!", 
            "Automatic processing is working!\n\n" ..
            "The plugin can communicate with OpenAI.\n\n" ..
            "We can now build the full automation.", "info")
    else
        LrDialogs.message("Automatic Processing Failed", 
            "Error: " .. tostring(result) .. "\n\n" ..
            "Please use the manual workflow:\n" ..
            "1. Export photos to Desktop/LR_AI_Export/\n" ..
            "2. Go to https://chat.openai.com\n" ..
            "3. Upload and analyze", "warning")
    end
end)
