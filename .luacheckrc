-- Luacheck configuration for Lightroom Classic plugin

-- Ignore line length warnings
max_line_length = false

-- Ignore whitespace warnings and specific code patterns
ignore = {
    "611", -- line contains only whitespace
    "612", -- line contains trailing whitespace
    "613", -- trailing whitespace in a string
    "614", -- trailing whitespace in a comment
}

-- Global variables defined by Lightroom SDK
globals = {
    -- Lightroom SDK globals
    "import",
    "_PLUGIN",
    
    -- Plugin-specific globals defined in Init.lua
    "prefs",
    "log",
    
    -- Global functions/variables from the plugin
    "SkipReviewCaptions",
    "SkipReviewTitles", 
    "SkipReviewAltText",
    "SkipReviewKeywords",
    "SkipPhotoContextDialog",
    "PhotoContextData",
    "PerfLogFile",
    "AnalyzeImageProvider",
    
    -- API classes
    "OllamaAPI",
    "ChatGptAPI",
    "GeminiAPI",
    "LmStudioAPI",
    "AssistantAPI",
    "AiModelAPI",
    
    -- Other globals
    "Defaults",
}

-- Standard Lua globals
read_globals = {
    "math",
    "os",
    "io",
    "table",
    "string",
    "pairs",
    "ipairs",
    "type",
    "tostring",
    "tonumber",
    "next",
    "require",
}

-- Ignore unused self warning for object methods
self = false

-- Files to exclude from checking
exclude_files = {
    "**/test/**",
    "**/JSON.lua",  -- Third-party library
    "**/inspect.lua",  -- Third-party library
}