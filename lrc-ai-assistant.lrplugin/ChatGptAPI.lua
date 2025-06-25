require 'Defaults'
local LrHttp = import 'LrHttp'
local JSON = require 'JSON'
local ResponseStructure = require 'ResponseStructure'

ChatGptAPI = {}

-- Lazy load Util to avoid loading order issues
local Util
ChatGptAPI.__index = ChatGptAPI

function ChatGptAPI:new()
    local o = setmetatable({}, ChatGptAPI)

    -- Simple nil/empty check instead of Util.nilOrEmpty
    if not prefs.chatgptApiKey or prefs.chatgptApiKey == "" then
        -- Simple error handling instead of Util.handleError
        if log then log:error('ChatGPT API key not configured.') end
        error("No ChatGPT API key configured in Add-Ons manager.")
        return nil
    else
        self.apiKey = prefs.chatgptApiKey
    end

    self.model = prefs.ai

    self.url = Defaults.baseUrls[self.model]

    return o
end

function ChatGptAPI:doRequestWithRetry(filePath, task, systemInstruction, generationConfig, maxRetries)
    maxRetries = maxRetries or 3
    
    for attempt = 1, maxRetries do
        local success, result, inputTokens, outputTokens = self:doRequest(filePath, task, systemInstruction, generationConfig)
        
        if success then
            return success, result, inputTokens, outputTokens
        elseif result == 'RATE_LIMIT_EXCEEDED' then
            if attempt < maxRetries then
                local waitTime = math.min(2 ^ attempt, 60) -- Exponential backoff, max 60 seconds
                log:warn('[RETRY] Rate limited, waiting ' .. waitTime .. ' seconds before retry ' .. attempt .. '/' .. maxRetries)
                
                -- Simple sleep implementation for Lua
                local startTime = os.time()
                while os.time() - startTime < waitTime do
                    -- Busy wait (not ideal but works in Lightroom context)
                end
            else
                log:warn('[RETRY] Max retries reached, giving up on this request')
                return false, result, inputTokens, outputTokens
            end
        else
            -- Non-rate-limit error, don't retry
            return false, result, inputTokens, outputTokens
        end
    end
    
    return false, 'RETRY_EXHAUSTED', 0, 0
end

function ChatGptAPI:doRequest(filePath, task, systemInstruction, generationConfig)
    local body = {
        model = self.model,
        response_format = generationConfig,
        messages = {
            {
                role = "system",
                content = systemInstruction,
            },
            {
                role = "user",
                content = task,
            },
            {
                role = "user",
                content = {
                    {
                        type = "image_url",
                        image_url = {
                            url = "data:image/jpeg;base64," .. (function()
                                if not Util then Util = require 'Util' end
                                return Util.encodePhotoToBase64(filePath)
                            end)()
                        }
                    }
                }
            }
        },
        temperature = prefs.temperature,
    }

    if log then 
        if not Util then Util = require 'Util' end
        log:trace(Util.dumpTable(body))
    end

    local response, headers = LrHttp.post(self.url, JSON:encode(body), {{ field = 'Content-Type', value = 'application/json' },  { field = 'Authorization', value = 'Bearer ' .. self.apiKey }})

    if headers.status == 200 then
        if response ~= nil then
            log:trace(response)
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                    if decoded.choices ~= nil then
                        if decoded.choices[1].finish_reason == 'stop' then
                            local text = decoded.choices[1].message.content
                            local inputTokenCount = decoded.usage.prompt_tokens
                            local outputTokenCount = decoded.usage.completion_tokens
                            log:trace(text)
                            return true, text, inputTokenCount, outputTokenCount
                        end
                    else
                        if not Util then Util = require 'Util' end
                        log:error('Blocked: ' .. decoded.choices[1].finish_reason .. Util.dumpTable(decoded.choices[1]))
                        local inputTokenCount = decoded.usage.prompt_tokens
                        local outputTokenCount = decoded.usage.completion_tokens
                        return false,  decoded.choices[1].finish_reason, inputTokenCount, outputTokenCount
                    end
            end
        else
            log:error('Got empty response from ChatGPT')
        end
    elseif headers.status == 429 then
        -- Rate limit handling
        local retryAfter = headers['retry-after'] or headers['retry-after-ms'] or "unknown"
        local decoded = JSON:decode(response)
        local errorMessage = "Rate limit exceeded"
        
        if decoded and decoded.error and decoded.error.message then
            errorMessage = decoded.error.message
        end
        
        log:warn('[RATE_LIMIT] Skipping image analysis due to rate limit (Status: 429, Retry-After: ' .. retryAfter .. ')')
        log:warn('[RATE_LIMIT] Error: ' .. errorMessage)
        
        return false, 'RATE_LIMIT_EXCEEDED', 0, 0
    else
        log:error('ChatGptAPI POST request failed. ' .. self.url)
        if not Util then Util = require 'Util' end
        log:error(Util.dumpTable(headers))
        log:error(response)
        return false, 'ChatGptAPI POST request failed. ' .. self.url, 0, 0 
    end
end


function ChatGptAPI:analyzeImage(filePath, metadata)
    -- For single-image analysis, use only the selected prompt as system instruction
    -- Don't use the additional task prompt which is meant for batch processing
    local task = ""
    if metadata ~= nil then
        if prefs.submitGPS and metadata.gps ~= nil then
            task = task .. "\nThis photo was taken at the following coordinates:" .. metadata.gps.latitude .. ", " .. metadata.gps.longitude
        end
        if prefs.submitKeywords and metadata.keywords ~= nil then
            task = task .. "\nSome keywords are:" .. metadata.keywords
        end
        if metadata.context ~= nil and metadata.context ~= "" then
            log:trace("Preflight context given")
            task = task .. "\nSome context for this photo: " .. metadata.context
        end
    end

    local systemInstruction = AiModelAPI.addKeywordHierarchyToSystemInstruction()

    -- Use retry wrapper for better rate limit handling
    local success, result, inputTokenCount, outputTokenCount = self:doRequestWithRetry(filePath, task, systemInstruction, ResponseStructure:new():generateResponseStructure(), 3)
    if success then
        return success, JSON:decode(result), inputTokenCount, outputTokenCount
    end
    return false, result, inputTokenCount, outputTokenCount
end

return ChatGptAPI
