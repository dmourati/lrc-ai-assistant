local LrHttp = import 'LrHttp'
local LrDialogs = import 'LrDialogs'
local JSON = require 'JSON'

UpdateCheck = {}

-- Version info - keep in sync with Info.lua
local MAJOR = 3
local MINOR = 8
local REVISION = 1

UpdateCheck.releaseTagName = "v" .. tostring(MAJOR) .. "." .. tostring(MINOR) .. "." .. tostring(REVISION)
UpdateCheck.updateCheckUrl = "https://api.github.com/repos/bmachek/lrc-ai-assistant/releases/latest"
UpdateCheck.latestReleaseUrl = "https://github.com/bmachek/lrc-ai-assistant/releases/latest"

function UpdateCheck.checkForNewVersion()
    local response, headers = LrHttp.get(UpdateCheck.updateCheckUrl)

    if headers.status == 200 then
        if response ~= nil then
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                if decoded.tag_name ~= UpdateCheck.releaseTagName then
                    LrHttp.openUrlInBrowser(UpdateCheck.latestReleaseUrl)
                else
                    LrDialogs.message("You're on the latest plugin version: " .. UpdateCheck.releaseTagName)
                end
            end
        else
            log:error('Could not run update check. Empty response')
        end
    else
        log:error('Update check failed. ' .. UpdateCheck.updateCheckUrl)
        log:error(Util.dumpTable(headers))
        log:error(response)
        return nil
    end
    return nil
end