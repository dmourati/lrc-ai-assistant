
require 'Defaults'
local GeminiAPI = require 'GeminiAPI'
local ChatGptAPI = require 'ChatGptAPI'
local OllamaAPI = require 'OllamaAPI'
local LmStudioAPI = require 'LmStudioAPI'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'

AiModelAPI = {}
AiModelAPI.__index = AiModelAPI

function AiModelAPI:new()
    local instance = setmetatable({}, AiModelAPI)

    if string.sub(prefs.ai, 1, 6) == 'gemini' then
        self.usedApi = GeminiAPI:new()
        self.topKeyword = Defaults.googleTopKeyword
    elseif string.sub(prefs.ai, 1, 3) == 'gpt' then
        self.usedApi = ChatGptAPI:new()
        self.topKeyword = Defaults.chatgptTopKeyword
    elseif string.sub(prefs.ai, 1, 6) == 'ollama' then
        self.usedApi = OllamaAPI:new()
        self.topKeyword = Defaults.ollamaTopKeyWord
    elseif string.sub(prefs.ai, 1, 8) == 'lmstudio' then
        self.usedApi = LmStudioAPI:new()
        self.topKeyword = Defaults.lmStudioTopKeyWord
    else
        Util.handleError('Configuration error: No valid AI model selected, check Module Manager for Configuration', LOC("$$$/lrc-ai-assistant/AiModelAPI/NoModelSelectedError=No AI model selected, check Configuration in Add-Ons manager"))
    end

    

    if self.usedApi == nil then
        return nil
    end
    
    return instance
end

function AiModelAPI:analyzeImage(filePath, metadata)
    return self.usedApi:analyzeImage(filePath, metadata)
end


function AiModelAPI.addKeywordHierarchyToSystemInstruction()
    local keywords = Defaults.defaultKeywordCategories
    if prefs.keywordCategories ~= nil then
        if type(prefs.keywordCategories) == "table" then
            keywords = prefs.keywordCategories
        end
    end

    -- Check if we should use version-controlled prompt for soccer jersey detection
    local systemInstruction
    
    if prefs.prompt == "Soccer Single Image Analysis" then
        -- Try to load from version-controlled file
        local promptFile = LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), "prompts/soccer-jersey-detection.txt")
        
        if LrFileUtils.exists(promptFile) then
            local file = io.open(promptFile, "r")
            if file then
                systemInstruction = file:read("*all")
                file:close()
                log:trace("Using version-controlled soccer prompt from: " .. promptFile)
            else
                -- Fallback to UI prompt if file can't be read
                systemInstruction = prefs.prompts[prefs.prompt] or Defaults.singleImageSystemInstruction
            end
        else
            -- Fallback to UI prompt if file doesn't exist
            systemInstruction = prefs.prompts[prefs.prompt] or Defaults.singleImageSystemInstruction
        end
    else
        -- Use UI prompt for non-soccer prompts
        systemInstruction = prefs.prompts[prefs.prompt] or Defaults.singleImageSystemInstruction
    end
    
    if prefs.useKeywordHierarchy and #keywords >= 1 then
        systemInstruction = systemInstruction .. "\nPut the keywords in the following categories:"
        for _, keyword in ipairs(keywords) do
            systemInstruction = systemInstruction .. "\n * " .. keyword
        end
    end

    return systemInstruction
end

function AiModelAPI.generatePromptFromConfiguration()
    local result = Defaults.defaultTask
    if prefs.generateAltText then
        result = result .. "* Alt text (with context for screen readers)\n"
    end
    if prefs.generateCaption then
        result = result .. "* Image caption\n"
    end
    if prefs.generateTitle then
        result = result .. "* Image title\n"
    end
    if prefs.generateKeywords then
        result = result .. "* Keywords\n"
    end

    result = result .. "\nAll results should be generated in " .. prefs.generateLanguage

    return result
end

return AiModelAPI