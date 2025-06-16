--[[
AssistantAPI.lua - OpenAI Assistant API integration for Lightroom
Handles batch processing of multiple images with persistent context
]]--

local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrErrors = import 'LrErrors'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrExportSession = import 'LrExportSession'
local LrTasks = import 'LrTasks'
local JSON = require 'JSON'
local Defaults = require 'Defaults'

local AssistantAPI = {}

-- Configuration
local OPENAI_API_BASE = "https://api.openai.com/v1"
local MAX_FILE_SIZE = 20 * 1024 * 1024 -- 20MB limit for OpenAI

-- Initialize Assistant API with settings
function AssistantAPI.initialize(apiKey, assistantId)
    AssistantAPI.apiKey = apiKey
    AssistantAPI.assistantId = assistantId
    AssistantAPI.headers = {
        { field = "Authorization", value = "Bearer " .. apiKey },
        { field = "Content-Type", value = "application/json" },
        { field = "OpenAI-Beta", value = "assistants=v2" }
    }
end

-- Create a new thread for batch processing
function AssistantAPI.createThread()
    local url = OPENAI_API_BASE .. "/threads"
    local body = JSON:encode({})
    
    local response, headers = LrHttp.post(url, body, AssistantAPI.headers)
    
    if headers.status == 200 then
        local threadData = JSON:decode(response)
        return threadData.id
    else
        LrErrors.throwUserError("Failed to create Assistant thread: " .. (response or "Unknown error"))
    end
end

-- Upload image file to OpenAI
function AssistantAPI.uploadFile(filePath)
    local fileSize = LrFileUtils.fileAttributes(filePath).fileSize
    if fileSize > MAX_FILE_SIZE then
        LrErrors.throwUserError("Image file too large: " .. filePath)
    end
    
    -- Read file as binary data
    local file = io.open(filePath, "rb")
    if not file then
        LrErrors.throwUserError("Cannot read file: " .. filePath)
    end
    
    local fileData = file:read("*all")
    file:close()
    
    -- Prepare multipart form data
    local boundary = "----LightroomAssistantUpload" .. os.time()
    local body = "--" .. boundary .. "\r\n"
    body = body .. "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n"
    body = body .. "vision\r\n"
    body = body .. "--" .. boundary .. "\r\n"
    body = body .. "Content-Disposition: form-data; name=\"file\"; filename=\"" .. LrPathUtils.leafName(filePath) .. "\"\r\n"
    body = body .. "Content-Type: image/jpeg\r\n\r\n"
    body = body .. fileData .. "\r\n"
    body = body .. "--" .. boundary .. "--\r\n"
    
    local uploadHeaders = {
        { field = "Authorization", value = "Bearer " .. AssistantAPI.apiKey },
        { field = "Content-Type", value = "multipart/form-data; boundary=" .. boundary }
    }
    
    local response, headers = LrHttp.post(OPENAI_API_BASE .. "/files", body, uploadHeaders)
    
    if headers.status == 200 then
        local fileData = JSON:decode(response)
        return fileData.id
    else
        LrErrors.throwUserError("Failed to upload file: " .. (response or "Unknown error"))
    end
end

-- Add message with images to thread
function AssistantAPI.addMessage(threadId, content, fileIds)
    local messageContent = {}
    
    -- Add text content
    table.insert(messageContent, {
        type = "text",
        text = content
    })
    
    -- Add image files
    if fileIds then
        for _, fileId in ipairs(fileIds) do
            table.insert(messageContent, {
                type = "image_file",
                image_file = {
                    file_id = fileId
                }
            })
        end
    end
    
    local body = JSON:encode({
        role = "user",
        content = messageContent
    })
    
    local url = OPENAI_API_BASE .. "/threads/" .. threadId .. "/messages"
    local response, headers = LrHttp.post(url, body, AssistantAPI.headers)
    
    if headers.status == 200 then
        local messageData = JSON:decode(response)
        return messageData.id
    else
        LrErrors.throwUserError("Failed to add message: " .. (response or "Unknown error"))
    end
end

-- Run assistant on thread
function AssistantAPI.runAssistant(threadId, instructions)
    local body = JSON:encode({
        assistant_id = AssistantAPI.assistantId,
        instructions = instructions
    })
    
    local url = OPENAI_API_BASE .. "/threads/" .. threadId .. "/runs"
    local response, headers = LrHttp.post(url, body, AssistantAPI.headers)
    
    if headers.status == 200 then
        local runData = JSON:decode(response)
        return runData.id
    else
        LrErrors.throwUserError("Failed to run assistant: " .. (response or "Unknown error"))
    end
end

-- Poll for run completion
function AssistantAPI.waitForCompletion(threadId, runId, progressScope)
    local maxAttempts = 60 -- 5 minutes max
    local attempt = 0
    
    while attempt < maxAttempts do
        if progressScope then
            progressScope:setCaption("Processing with AI Assistant... (attempt " .. (attempt + 1) .. ")")
        end
        
        local url = OPENAI_API_BASE .. "/threads/" .. threadId .. "/runs/" .. runId
        local response, headers = LrHttp.get(url, AssistantAPI.headers)
        
        if headers.status == 200 then
            local runData = JSON:decode(response)
            
            if runData.status == "completed" then
                return true
            elseif runData.status == "failed" or runData.status == "cancelled" or runData.status == "expired" then
                LrErrors.throwUserError("Assistant run failed: " .. runData.status)
            end
        end
        
        -- Wait 5 seconds before next check
        LrTasks.sleep(5)
        attempt = attempt + 1
    end
    
    LrErrors.throwUserError("Assistant run timed out")
end

-- Get messages from thread
function AssistantAPI.getMessages(threadId)
    local url = OPENAI_API_BASE .. "/threads/" .. threadId .. "/messages"
    local response, headers = LrHttp.get(url, AssistantAPI.headers)
    
    if headers.status == 200 then
        local messagesData = JSON:decode(response)
        return messagesData.data
    else
        LrErrors.throwUserError("Failed to get messages: " .. (response or "Unknown error"))
    end
end

-- Main batch processing function
function AssistantAPI.processBatch(selectedPhotos, progressScope)
    local results = {}
    
    LrFunctionContext.callWithContext("AssistantAPI.processBatch", function(context)
        -- Create thread
        if progressScope then progressScope:setCaption("Creating AI session...") end
        local threadId = AssistantAPI.createThread()
        
        -- Export and upload images
        local fileIds = {}
        for i, photo in ipairs(selectedPhotos) do
            if progressScope then 
                progressScope:setCaption("Uploading image " .. i .. " of " .. #selectedPhotos)
                progressScope:setPortionComplete(i / (#selectedPhotos * 2)) -- First half for upload
            end
            
            -- Export photo to temporary file
            local tempPath = AssistantAPI.exportTempImage(photo)
            
            -- Upload to OpenAI
            local fileId = AssistantAPI.uploadFile(tempPath)
            table.insert(fileIds, fileId)
            
            -- Clean up temp file
            LrFileUtils.delete(tempPath)
        end
        
        -- Create batch processing prompt
        local prompt = AssistantAPI.createBatchPrompt(selectedPhotos)
        
        -- Add message with all images
        if progressScope then progressScope:setCaption("Sending images to AI Assistant...") end
        AssistantAPI.addMessage(threadId, prompt, fileIds)
        
        -- Run assistant with HNS-specific system instruction
        local systemInstruction = "You are a soccer skills analyst trained in the Croatian Football Federation (HNS) skill assessment rubric. " ..
            "Analyze soccer images and identify specific skills demonstrated by players. " ..
            "Only return the requested JSON format with HNS skill codes. Do not include any other metadata or descriptions."
        local runId = AssistantAPI.runAssistant(threadId, systemInstruction)
        
        -- Wait for completion
        AssistantAPI.waitForCompletion(threadId, runId, progressScope)
        
        -- Get results
        if progressScope then progressScope:setCaption("Retrieving AI analysis...") end
        local messages = AssistantAPI.getMessages(threadId)
        
        -- Parse results for each photo
        results = AssistantAPI.parseMetadataResults(messages, selectedPhotos)
        
        if progressScope then progressScope:setPortionComplete(1.0) end
    end)
    
    return results
end

-- Export photo to temporary file for upload
function AssistantAPI.exportTempImage(photo)
    local tempDir = LrPathUtils.getStandardFilePath("temp")
    local tempName = "lr_assistant_" .. os.time() .. "_" .. math.random(1000, 9999) .. ".jpg"
    local tempPath = LrPathUtils.child(tempDir, tempName)
    
    -- Export settings for API upload
    local exportSettings = {
        LR_size = "1024", -- Reasonable size for analysis
        LR_format = "JPEG",
        LR_jpeg_quality = 0.8,
        LR_export_destinationType = "specificFolder",
        LR_export_destinationPathPrefix = tempDir,
        LR_export_useSubfolder = false,
        LR_renamingTokensOn = true,
        LR_tokens = tempName:gsub("%.jpg$", ""),
        LR_tokenCustomString = "",
        LR_collisionHandling = "overwrite"
    }
    
    -- Perform export
    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = exportSettings
    })
    
    exportSession:doExportOnCurrentTask()
    
    return tempPath
end

-- Create batch processing prompt using HNS system
function AssistantAPI.createBatchPrompt(selectedPhotos)
    -- Use the HNS-specific task directly from Defaults
    local prompt = "I'm uploading " .. #selectedPhotos .. " related images for batch processing. "
    prompt = prompt .. Defaults.defaultTask
    
    -- Temporary debug logging
    if log then
        log:info("AssistantAPI prompt: " .. prompt)
    end
    
    return prompt
end

-- Parse AI response into metadata for each photo
function AssistantAPI.parseMetadataResults(messages, selectedPhotos)
    local results = {}
    
    -- Find the assistant's response (first message from assistant)
    local assistantResponse = nil
    for _, message in ipairs(messages) do
        if message.role == "assistant" then
            assistantResponse = message
            break
        end
    end
    
    if not assistantResponse then
        LrErrors.throwUserError("No response from AI Assistant")
    end
    
    -- Extract text content
    local responseText = ""
    for _, content in ipairs(assistantResponse.content) do
        if content.type == "text" then
            responseText = responseText .. content.text.value
        end
    end
    
    -- Try to parse JSON response
    local success, metadata = pcall(JSON.decode, JSON, responseText)
    if not success then
        -- Try to extract JSON from markdown code blocks
        local codeStart = responseText:find("```json")
        local codeEnd = responseText:find("```", codeStart and codeStart + 1)
        if codeStart and codeEnd then
            -- Extract content between the code block markers
            local startPos = responseText:find("\n", codeStart) or codeStart + 7 -- Skip "```json"
            local jsonText = responseText:sub(startPos + 1, codeEnd - 1):match("^%s*(.-)%s*$")
            if jsonText and jsonText ~= "" then
                success, metadata = pcall(JSON.decode, JSON, jsonText)
            end
        end
        
        -- Fallback: extract JSON array from response text with proper bracket matching
        if not success then
            local jsonStart = responseText:find("%[")
            if jsonStart then
                local bracketCount = 0
                local jsonEnd = nil
                for i = jsonStart, #responseText do
                    local char = responseText:sub(i, i)
                    if char == "[" then
                        bracketCount = bracketCount + 1
                    elseif char == "]" then
                        bracketCount = bracketCount - 1
                        if bracketCount == 0 then
                            jsonEnd = i
                            break
                        end
                    end
                end
                
                if jsonEnd then
                    local jsonText = responseText:sub(jsonStart, jsonEnd)
                    success, metadata = pcall(JSON.decode, JSON, jsonText)
                end
            end
        end
    end
    
    if success and type(metadata) == "table" then
        for i, photo in ipairs(selectedPhotos) do
            if metadata[i] then
                results[photo] = metadata[i]
            end
        end
    else
        LrErrors.throwUserError("Could not parse AI response: " .. responseText)
    end
    
    return results
end

return AssistantAPI