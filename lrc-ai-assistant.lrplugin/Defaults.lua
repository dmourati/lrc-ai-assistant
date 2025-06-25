-- lrc-ai-assistant.lrplugin/Defaults.lua

Defaults = {}

Defaults.openai_api_key = ""
Defaults.assistant_id = ""
Defaults.auto_run = false

Defaults.defaultTask = [[
Analyze each photo of a youth soccer game and identify the specific technical actions being demonstrated, using the Croatian Football Federation's (HNS) player development rubric.

Return only a JSON array, with one object per image:
[
  {
    "skills": ["HNS3", "HNS17", "HNS21"]
  },
  ...
]

Do not include any explanation, descriptions, titles, or non-HNS keywords. Only use official rubric codes from HNS1 to HNS104.
]]

Defaults.defaultSystemInstruction = [[
You are a professional soccer scout using the HNS (Croatian Football Federation) technical skill rubric. Your task is to assign objective HNS rubric codes (HNS1 to HNS104) to each photo based on what technical skills the player is executing.
Do not include non-HNS keywords or descriptive text.
]]

-- Enhanced system instruction for single-image analysis with jersey number detection
Defaults.singleImageSystemInstruction = [[
You are a professional sports photographer and analyst. Your task is to:

1. Analyze the soccer photo and identify the action, players, and context
2. Detect ONLY jersey numbers that are IN FOCUS and clearly readable
3. Generate descriptive metadata for the photo

CRITICAL JERSEY DETECTION RULES:
- Only include jersey numbers that are sharp, in focus, and clearly readable
- Do NOT include blurry, out-of-focus, or partially visible numbers
- The player wearing the jersey should be in the focal plane of the image
- If a jersey number is even slightly blurry or hard to read, exclude it
- Background players or motion-blurred players should be ignored

Return a JSON object with this exact structure:
{
  "Image title": "Brief descriptive title of the action",
  "Image caption": "Detailed description of what's happening in the photo", 
  "Image Alt Text": "Accessibility description",
  "keywords": ["relevant soccer and action keywords"],
  "jersey_numbers": ["list of IN-FOCUS jersey numbers only as strings"]
}

Example:
{
  "Image title": "Player executing a pass during youth soccer match",
  "Image caption": "Young soccer player in blue jersey demonstrating proper passing technique during a competitive match",
  "Image Alt Text": "Soccer player in blue uniform kicking ball to teammate",
  "keywords": ["passing", "youth soccer", "blue jersey", "ball control"],
  "jersey_numbers": ["86"]
}
Note: Even if multiple players are visible, only include jersey numbers that are sharply in focus.
]]

Defaults.defaultGenerateLanguage = "English"

Defaults.generateLanguages = {
    { title = "English", value = "English" },
    { title = "German", value = "German" },
    { title = "French", value = "French" },
}

Defaults.defaultTemperature = 0.1

Defaults.defaultKeywordCategories = {
    "Activities",
    "Buildings",
    "Location",
    "Objects",
    "People",
    "Moods",
    "Sceneries",
    "Texts",
    "Companies",
    "Weather",
    "Plants",
    "Animals",
    "Vehicles",
}

Defaults.targetDataFields = {
    { title = "Keywords", value = "keyword" },
    { title = "Image title", value = "title" },
    { title = "Image caption", value = "caption" },
    { title = "Image Alt Text", value = "altTextAccessibility" },
}

local aiModels = {
    { title = "Google Gemini Pro 1.5", value = "gemini-1.5-pro" },
    { title = "Google Gemini Flash 2.0", value = "gemini-2.0-flash" },
    { title = "Google Gemini Flash 2.0 Lite", value = "gemini-2.0-flash-lite" },
    { title = "Google Gemini Pro 2.5 (experimental)", value = "gemini-2.5-pro-exp-03-25" },
    { title = "ChatGPT-4", value = "gpt-4o" },
    { title = "ChatGPT-4 Mini", value = "gpt-4o-mini" },
    { title = "ChatGPT 4.1", value = "gpt-4.1" },
    { title = "ChatGPT 4.1 Mini", value = "gpt-4.1-mini" },
    { title = "ChatGPT 4.1 Nano", value = "gpt-4.1-nano" },
    -- { title = "LMStudio gemma-3-12b-it-qat", value = "lmstudio-gemma-3-12b-it-qat" },
}

function Defaults.getAvailableAiModels()
    local result = {}
    for _, model in ipairs(aiModels) do
        table.insert(result, model)
    end

    if OllamaAPI then
        local ollamaModels = OllamaAPI.getLocalVisionModels()
        if ollamaModels ~= nil then
            for _, model in ipairs(ollamaModels) do
                table.insert(result, model)
            end
        end
    end

    if log and Util then
        log:trace("getAvailableAiModels: " .. Util.dumpTable(result))
    end

    return result
end

Defaults.exportSizes = {
    "512", "1024", "2048", "3072", "4096"
}

Defaults.baseUrls = {}
Defaults.baseUrls['gemini-1.5-pro'] = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key='
Defaults.baseUrls['gemini-2.0-flash'] = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key='
Defaults.baseUrls['gemini-2.0-flash-lite'] = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key='
Defaults.baseUrls['gemini-2.5-pro-exp-03-25'] = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro-exp-03-25:generateContent?key='

Defaults.baseUrls['gpt-4o'] = 'https://api.openai.com/v1/chat/completions'
Defaults.baseUrls['gpt-4o-mini'] = 'https://api.openai.com/v1/chat/completions'

Defaults.baseUrls['gpt-4.1'] = 'https://api.openai.com/v1/chat/completions'
Defaults.baseUrls['gpt-4.1-mini'] = 'https://api.openai.com/v1/chat/completions'
Defaults.baseUrls['gpt-4.1-nano'] = 'https://api.openai.com/v1/chat/completions'

Defaults.baseUrls['lmstudio'] = 'http://localhost:1234/v1/chat/completions'

Defaults.baseUrls['ollama'] = 'http://localhost:11434'
Defaults.ollamaGenerateUrl = '/api/generate'
Defaults.ollamaChatUrl = '/api/chat'
Defaults.ollamaListModelUrl = '/api/tags'
Defaults.ollamaModelInfoUrl = '/api/show'

Defaults.pricing = {}
Defaults.pricing["gemini-1.5-pro"] = {}
Defaults.pricing["gemini-1.5-pro"].input = 1.25 / 1000000
Defaults.pricing["gemini-1.5-pro"].output= 5 / 1000000
Defaults.pricing["gemini-2.5-pro-exp-03-25"] = {}
Defaults.pricing["gemini-2.5-pro-exp-03-25"].input = 3.5 / 1000000
Defaults.pricing["gemini-2.5-pro-exp-03-25"].output= 10.5 / 1000000
Defaults.pricing["gemini-2.0-flash"] = {}
Defaults.pricing["gemini-2.0-flash"].input = 0.1 / 1000000
Defaults.pricing["gemini-2.0-flash"].output= 0.4 / 1000000
Defaults.pricing["gemini-2.0-flash-lite"] = {}
Defaults.pricing["gemini-2.0-flash-lite"].input = 0.075 / 1000000
Defaults.pricing["gemini-2.0-flash-lite"].output= 0.3 / 1000000
Defaults.pricing["gpt-4o"] = {}
Defaults.pricing["gpt-4o"].input = 2.5 / 1000000
Defaults.pricing["gpt-4o"].output= 10 / 1000000
Defaults.pricing["gpt-4o-mini"] = {}
Defaults.pricing["gpt-4o-mini"].input = 0.15 / 1000000
Defaults.pricing["gpt-4o-mini"].output= 0.6 / 1000000

Defaults.pricing["gpt-4.1"] = {}
Defaults.pricing["gpt-4.1"].input = 2 / 1000000
Defaults.pricing["gpt-4.1"].output= 8 / 1000000

Defaults.pricing["gpt-4.1-mini"] = {}
Defaults.pricing["gpt-4.1-mini"].input = 0.4 / 1000000
Defaults.pricing["gpt-4.1-mini"].output= 1.6 / 1000000

Defaults.pricing["gpt-4.1-nano"] = {}
Defaults.pricing["gpt-4.1-nano"].input = 0.1 / 1000000
Defaults.pricing["gpt-4.1-nano"].output= 0.4 / 1000000


Defaults.defaultAiModel = "gpt-4.1-nano"

Defaults.defaultExportSize = "2048"
Defaults.defaultExportQuality = 50

Defaults.googleTopKeyword = 'Google Gemini'
Defaults.chatgptTopKeyword = 'ChatGPT'
Defaults.ollamaTopKeyWord = 'Ollama'
Defaults.lmStudioTopKeyWord = 'LMStudio'

Defaults.geminiKeywordsGarbageAtStart = '```json'
Defaults.geminiKeywordsGarbageAtEnd = '```'

-- No `return` at the end!