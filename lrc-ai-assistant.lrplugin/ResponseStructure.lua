
require 'Defaults'
local Util = require 'Util'

ResponseStructure = {}
ResponseStructure.__index = ResponseStructure

function ResponseStructure:readKeywordStructureRecurse(parent)
    local result = {}
    local children = parent:getChildren()
    if #children > 0 then
        for _, child in pairs(children) do
            if #(child:getChildren()) > 0 then
                log:trace(#(child:getChildren()))
                table.insert(result, child:getName())
                local nextLevelChildren = ResponseStructure:readKeywordStructureRecurse(child)
                if #nextLevelChildren > 0 then
                    table.insert(result, nextLevelChildren)
                end
            end
        end
    end
    return result
end

function ResponseStructure:new()
    local instance = setmetatable({}, ResponseStructure)

    if string.sub(prefs.ai, 1, 6) == 'gemini' then
        self.strArray = "ARRAY"
        self.strObject = "OBJECT"
        self.strString = "STRING"
        self.ai = 'gemini'
    elseif string.sub(prefs.ai, 1, 3) == 'gpt' or string.sub(prefs.ai, 1, 8) == 'lmstudio' then
        self.strArray = "array"
        self.strObject = "object"
        self.strString = "string"
        self.ai = "chatgpt"
    elseif string.sub(prefs.ai, 1, 6) == 'ollama' then
        self.strArray = "array"
        self.strObject = "object"
        self.strString = "string"
        self.ai = "ollama"
    else
        Util.handleError('Configuration error: No valid AI model selected, check Module Manager for Configuration', LOC("$$$/lrc-ai-assistant/ResponseStructure/NoModelSelectedError=No AI model selected, check Configuration in Add-Ons manager"))
    end

    return instance
end


function ResponseStructure:generateResponseStructure()

    -- Check if we're using soccer jersey detection mode
    local isJerseyDetectionMode = (prefs.prompt == "Soccer Single Image Analysis")

    if isJerseyDetectionMode then
        -- Return jersey detection schema with confidence scores
        local result = {
            type = self.strObject,
            properties = {
                detections = {
                    type = "array",
                    items = {
                        type = self.strObject,
                        properties = {
                            number = { type = self.strString },
                            confidence = { type = "number" },
                            face_visible = { type = "boolean" },
                            face_in_focus = { type = "boolean" },
                            jersey_in_focus = { type = "boolean" },
                            reasoning = { type = self.strString }
                        },
                        required = {"number", "confidence", "face_visible", "face_in_focus", "jersey_in_focus", "reasoning"},
                        additionalProperties = false
                    }
                },
                jersey_numbers = {
                    type = "array",
                    items = {
                        type = self.strString
                    }
                }
            },
            required = {"detections", "jersey_numbers"}
        }
        
        if self.ai == 'chatgpt' then
            result.additionalProperties = false
            return {
                type = "json_schema",
                json_schema = {
                    name = "results",
                    strict = true,
                    schema = result,
                },
            }
        elseif self.ai == 'gemini' then
            return {
                response_mime_type = "application/json",
                response_schema = result,
                temperature = prefs.temperature,
            }
        elseif self.ai == 'ollama' then
            return result
        end
    end

    -- Default behavior for non-jersey detection modes
    local keywords = Defaults.defaultKeywordCategories
    if prefs.keywordCategories ~= nil then
        if type(prefs.keywordCategories) == "table" then
            keywords = prefs.keywordCategories
        end
    end

    local result = {}
    result.properties = {}
    result.type = self.strObject
    if self.ai == 'chatgpt' then
        result.required = {}
        result.additionalProperties = false
    elseif self.ai == 'ollama' then
        result.required = {}
    end

    if prefs.generateCaption then
        result.properties[LOC("$$$/lrc-ai-assistant/Defaults/ResponseStructure/ImageCaption=Image caption")] = { type = self.strString }
        if self.ai == 'chatgpt' or self.ai == 'ollama' then
            table.insert(result.required, LOC("$$$/lrc-ai-assistant/Defaults/ResponseStructure/ImageCaption=Image caption"))
        end
    end

    if prefs.generateTitle then
        result.properties[LOC("$$$/lrc-ai-assistant/Defaults/ResponseStructure/ImageTitle=Image title")] = { type = self.strString }
        if self.ai == 'chatgpt' or self.ai == 'ollama' then
            table.insert(result.required, LOC("$$$/lrc-ai-assistant/Defaults/ResponseStructure/ImageTitle=Image title"))
        end
    end

    if prefs.generateAltText then
        result.properties[LOC("$$$/lrc-ai-assistant/Defaults/ResponseStructure/ImageAltText=Image Alt Text")] = { type = self.strString }
        if self.ai == 'chatgpt' or self.ai == 'ollama' then
            table.insert(result.required, LOC("$$$/lrc-ai-assistant/Defaults/ResponseStructure/ImageAltText=Image Alt Text"))
        end
    end

    if self.ai == 'chatgpt' or self.ai == 'ollama' then
        table.insert(result.required, "keywords")
    end

    result.properties.keywords =  ResponseStructure:keywordTableToResponseStructureRecurse(keywords)
    
    if self.ai == 'chatgpt' then
        return {
            type = "json_schema",
            json_schema = {
                name = "results",
                strict = true,
                schema = result,
            },
        }
    elseif self.ai == 'gemini' then
        return {
            response_mime_type = "application/json",
            response_schema = result,
            temperature = prefs.temperature, -- Dirty -- FIXME probably
        }
    elseif self.ai == 'ollama' then
        return result
    end
end

-- Convert table into proper formatted table before converting it to JSON
function ResponseStructure:keywordTableToResponseStructureRecurse(table)
    local responseStructure = {}
    if prefs.useKeywordHierarchy then
        responseStructure.properties = {}
        responseStructure.type = self.strObject
        if self.ai == 'chatgpt' then
            responseStructure.required = table
            responseStructure.additionalProperties = false
        elseif self.ai == 'ollama' then
            responseStructure.required = table
        end

        for _, v in pairs(table) do
            local child = {}
            if type(v) == "string" then
                child.type = self.strArray
                child.items = {}
                child.items.type = self.strString
            elseif type(v) == "table" then
                child.type = self.strObject
                child.properties = ResponseStructure:keywordTableToResponseStructureRecurse(v)
            end
            responseStructure.properties[v] = child
        end
    else
        responseStructure.type = self.strArray
        responseStructure.items = {}
        responseStructure.items.type = self.strString
    end

    return responseStructure
end

return ResponseStructure
