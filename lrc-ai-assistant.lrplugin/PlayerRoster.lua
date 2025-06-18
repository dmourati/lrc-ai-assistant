-- PlayerRoster.lua - Jersey number to player name mapping for soccer team
-- This module handles the mapping between jersey numbers and player names

PlayerRoster = {}

-- Team roster - jersey numbers to player names
PlayerRoster.defaultRoster = {
    ["7"] = "Luca Nasrabadi",
    ["10"] = "Austin Ivancic",
    ["11"] = "Luke Cheng",
    ["19"] = "Yianni Mouratis",
    ["39"] = "Dean Huddy",
    ["64"] = "Luke Forster",
    ["67"] = "Ismail Elghazi",
    ["68"] = "Victor Smith",
    ["74"] = "Cullen Evanson",
    ["76"] = "Mason Roach",
    ["86"] = "Zachary Kerr",
    ["90"] = "Stefen Edelstein",
}

-- Function to get player name from jersey number
function PlayerRoster.getPlayerName(jerseyNumber)
    -- Remove any non-numeric characters and leading zeros
    local cleanNumber = tostring(jerseyNumber):match("%d+")
    if not cleanNumber then
        return nil
    end
    
    -- Look up player name
    local playerName = PlayerRoster.defaultRoster[cleanNumber]
    if playerName then
        return playerName, cleanNumber
    end
    
    return nil, cleanNumber
end

-- Function to extract jersey numbers from text
function PlayerRoster.extractJerseyNumbers(text)
    local jerseyNumbers = {}
    
    if not text or type(text) ~= "string" then
        return jerseyNumbers
    end
    
    -- Pattern to match jersey numbers: #number, number, jersey number, etc.
    local patterns = {
        "#(%d+)",           -- #86
        "jersey (%d+)",     -- jersey 86
        "number (%d+)",     -- number 86
        "(%d+)%s*jersey",   -- 86 jersey
        "#?(%d%d?)",        -- single or double digit numbers
    }
    
    for _, pattern in ipairs(patterns) do
        for number in text:gmatch(pattern) do
            -- Convert to number and back to string to normalize
            local num = tonumber(number)
            if num and num >= 1 and num <= 99 then -- Valid jersey number range
                jerseyNumbers[tostring(num)] = true
            end
        end
    end
    
    -- Convert to array
    local result = {}
    for number, _ in pairs(jerseyNumbers) do
        table.insert(result, number)
    end
    
    return result
end

-- Function to generate hierarchical keywords for jersey number and player
-- Structure: Fusion > 2016BN5 > Player Name > Jersey Number
function PlayerRoster.generateKeywords(jerseyNumber)
    local keywords = {}
    
    local playerName, cleanNumber = PlayerRoster.getPlayerName(jerseyNumber)
    
    if playerName and cleanNumber then
        -- Create hierarchical keyword structure
        local hierarchicalKeyword = {
            category = "Fusion",
            keywords = {
                {
                    category = "2016BN5",
                    keywords = {
                        {
                            category = playerName,
                            keywords = {"#" .. cleanNumber}
                        }
                    }
                }
            }
        }
        
        table.insert(keywords, hierarchicalKeyword)
    end
    
    return keywords
end

-- Function to update roster (for future configuration)
function PlayerRoster.updateRoster(newRoster)
    if newRoster and type(newRoster) == "table" then
        PlayerRoster.defaultRoster = newRoster
        return true
    end
    return false
end

return PlayerRoster