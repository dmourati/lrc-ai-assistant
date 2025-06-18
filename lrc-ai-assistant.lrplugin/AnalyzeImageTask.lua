
-- Required imports
local LrTasks = import 'LrTasks'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrPathUtils = import 'LrPathUtils'
local LrApplication = import 'LrApplication'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'

-- Required modules
local AiModelAPI = require 'AiModelAPI'
local Util = require 'Util'
local PlayerRoster = require 'PlayerRoster'

-- Module will be loaded when needed to avoid initialization issues
local AnalyzeImageProvider

SkipReviewCaptions = false
SkipReviewTitles = false
SkipReviewAltText = false
SkipReviewKeywords = false
SkipPhotoContextDialog = false
PhotoContextData = ""
PerfLogFile = nil


local function exportAndAnalyzePhoto(photo, progressScope)
    local tempDir = LrPathUtils.getStandardFilePath('temp')
    local photoName = LrPathUtils.leafName(photo:getFormattedMetadata('fileName'))
    local catalog = LrApplication.activeCatalog()

    local exportSettings = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = tempDir,
        LR_export_useSubfolder = false,
        LR_format = 'JPEG',
        LR_jpeg_quality = tonumber(prefs.exportQuality) / 100,
        LR_minimizeEmbeddedMetadata = false,
        LR_outputSharpeningOn = false,
        LR_size_doConstrain = true,
        LR_size_maxHeight = tonumber(prefs.exportSize),
        LR_size_resizeType = 'longEdge',
        LR_size_units = 'pixels',
        LR_collisionHandling = 'rename',
        LR_includeVideoFiles = false,
        LR_removeLocationMetadata = false,
        LR_embeddedMetadataOption = "all",
    }

    log:trace('Export settings are: ' .. prefs.exportSize .. "px (long edge) and " .. prefs.exportQuality .. "% JPEG quality")

    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = exportSettings
    })

    local ai
    ai = AiModelAPI:new()

    if ai == nil then
        return false, 0, 0, "fatal"
    end

    for _, rendition in exportSession:renditions() do
        local success, path = rendition:waitForRender()
        local metadata = {}

        metadata.gps = photo:getRawMetadata("gps")
        metadata.keywords = photo:getFormattedMetadata("keywordTagsForExport")

        if success then -- Export successful
            
            log:trace("Export file size: " .. (LrFileUtils.fileAttributes(path).fileSize / 1024) .. "kB")

            -- Photo Context Dialog
            if prefs.showPhotoContextDialog then
                if not SkipPhotoContextDialog then
                    local contextResult = AnalyzeImageProvider.showPhotoContextDialog(photo)
                    if not contextResult then
                        return false, 0, 0, "canceled", "Canceled by user in context dialog."
                    end
                end
                metadata.context = PhotoContextData
                catalog:withPrivateWriteAccessDo(function(context)
                        log:trace("Saving photo context data to metadata.")
                        photo:setPropertyForPlugin(_PLUGIN, 'photoContext', PhotoContextData)
                    end
                )
            end

            local startTimeAnalyze = LrDate.currentTime()
            local analyzeSuccess, result, inputTokens, outputTokens = ai:analyzeImage(path, metadata)
            local stopTimeAnalyze = LrDate.currentTime()

            log:trace("Analyzing " .. photoName .. " with " .. prefs.ai .. " took " .. (stopTimeAnalyze - startTimeAnalyze) .. " seconds.")

            if not analyzeSuccess then -- AI API request failed.
                if result == 'RATE_LIMIT_EXHAUSTED' then
                    LrDialogs.showError("Quota exhausted, set up pay as you go at Google, or wait for some hours.")
                    return false, inputTokens, outputTokens, "fatal", result
                end
                return false, inputTokens, outputTokens, "non-fatal", result
            end

            local title, caption, keywords, altText, jerseyNumbers
            if result ~= nil and analyzeSuccess then
                keywords = result.keywords or {}
                title = result["Image title"]
                caption = result["Image caption"]
                altText = result["Image Alt Text"]
                jerseyNumbers = result["jersey_numbers"] or {}
                
                -- Process jersey numbers and generate hierarchical player keywords
                local playerHierarchicalKeywords = {}
                if jerseyNumbers and #jerseyNumbers > 0 then
                    log:trace("Found jersey numbers: " .. table.concat(jerseyNumbers, ", "))
                    
                    for _, jerseyNum in ipairs(jerseyNumbers) do
                        -- Generate hierarchical keywords for this jersey number
                        local playerKeywords = PlayerRoster.generateKeywords(jerseyNum)
                        
                        -- Add to hierarchical keywords list
                        if playerKeywords and next(playerKeywords) then
                            table.insert(playerHierarchicalKeywords, playerKeywords)
                        end
                        
                        -- Also add flat keywords for easier searching (separate from regular keywords)
                        local playerName, cleanNumber = PlayerRoster.getPlayerName(jerseyNum)
                        if playerName and cleanNumber then
                            -- Add individual flat keywords directly to photo (not under ChatGPT hierarchy)
                            photo.catalog:withWriteAccessDo("Add flat player keywords", function()
                                local playerNameKeyword = photo.catalog:createKeyword(playerName, {}, true, nil, true)
                                local jerseyKeyword = photo.catalog:createKeyword("#" .. cleanNumber, {}, true, nil, true)
                                local fusionKeyword = photo.catalog:createKeyword("Fusion", {}, true, nil, true)
                                local ageGroupKeyword = photo.catalog:createKeyword("2016BN5", {}, true, nil, true)
                                
                                photo:addKeyword(playerNameKeyword)
                                photo:addKeyword(jerseyKeyword)
                                photo:addKeyword(fusionKeyword)
                                photo:addKeyword(ageGroupKeyword)
                            end)
                        end
                        
                        log:trace("Added hierarchical keywords for jersey #" .. jerseyNum)
                    end
                end
                
                -- Also check caption and title for jersey numbers (fallback)
                local fallbackNumbers = {}
                if caption then
                    local captionNumbers = PlayerRoster.extractJerseyNumbers(caption)
                    for _, num in ipairs(captionNumbers) do
                        table.insert(fallbackNumbers, num)
                    end
                end
                if title then
                    local titleNumbers = PlayerRoster.extractJerseyNumbers(title)
                    for _, num in ipairs(titleNumbers) do
                        table.insert(fallbackNumbers, num)
                    end
                end
                
                -- Add fallback jersey number keywords if any were found
                if #fallbackNumbers > 0 then
                    log:trace("Found additional jersey numbers in text: " .. table.concat(fallbackNumbers, ", "))
                    for _, jerseyNum in ipairs(fallbackNumbers) do
                        local playerKeywords = PlayerRoster.generateKeywords(jerseyNum)
                        for _, keyword in ipairs(playerKeywords) do
                            table.insert(playerHierarchicalKeywords, keyword)
                        end
                    end
                end
                
                log:trace("Final keywords: " .. (keywords and table.concat(keywords, ", ") or "none"))
            end

            local canceledByUser = false
            photo.catalog:withWriteAccessDo("Save AI generated title and caption", function()
                local saveCaption = true
                if prefs.generateCaption and prefs.reviewCaption and not SkipReviewCaptions then
                    -- local existingCaption = photo:getFormattedMetadata('caption')
                    local prop = AnalyzeImageProvider.showTextValidationDialog("Image caption", caption)
                    caption = prop.reviewedText
                    SkipReviewCaptions = prop.skipFromHere
                    if prop.result == 'cancel' then
                        log:trace("Canceled by caption validation dialog.")
                        canceledByUser = true
                    end
                end
                if saveCaption and caption ~=nil then
                    photo:setRawMetadata('caption', caption)
                end

                local saveTitle = true
                if prefs.generateTitle and prefs.reviewTitle and not SkipReviewTitles then
                    -- local existingTitle = photo:getFormattedMetadata('title')
                    local prop = AnalyzeImageProvider.showTextValidationDialog("Image title", title)
                    title = prop.reviewedText
                    SkipReviewTitles = prop.skipFromHere
                    if prop.result == 'cancel' then
                        log:trace("Canceled by title validation dialog.")
                        canceledByUser = true
                    end
                end

                if saveTitle and title ~= nil then
                    photo:setRawMetadata('title', title)
                end

                local saveAltText = true
                if prefs.generateAltText and prefs.reviewAltText and not SkipReviewAltText then
                    -- local existingTitle = photo:getFormattedMetadata('title')
                    local prop = AnalyzeImageProvider.showTextValidationDialog("Image Alt Text", altText)
                    if prop.result == 'cancel' then
                        log:trace("Canceled by Alt-Text validation dialog.")
                        canceledByUser = true
                    end
                    altText = prop.reviewedText
                    SkipReviewAltText = prop.skipFromHere
                    if prop.result == 'cancel' then
                        saveAltText = false
                    end
                end

                if saveAltText and altText ~= nil then
                    photo:setRawMetadata('altTextAccessibility', altText)
                end
                
            end)

            if keywords ~= nil and type(keywords) == 'table' then
                local topKeyword = nil
                if prefs.useKeywordHierarchy and prefs.useTopLevelKeyword then
                    photo.catalog:withWriteAccessDo("$$$/lrc-ai-assistant/AnalyzeImageTask/saveTopKeyword=Save AI generated keywords", function()
                        topKeyword = photo.catalog:createKeyword(ai.topKeyword, {}, false, nil, true)
                        photo:addKeyword(topKeyword)
                    end)
                end
                AnalyzeImageProvider.addKeywordRecursively(photo, keywords, topKeyword)
            end
            
            -- Add hierarchical player keywords (Fusion > 2016BN5 > Player > Jersey#)
            if jerseyNumbers and #jerseyNumbers > 0 then
                photo.catalog:withWriteAccessDo("Create player hierarchy", function()
                    -- Create Fusion root keyword
                    local fusionKeyword = photo.catalog:createKeyword("Fusion", {}, false, nil, true)
                    
                    -- Create 2016BN5 under Fusion
                    local ageGroupKeyword = photo.catalog:createKeyword("2016BN5", {}, false, fusionKeyword, true)
                    
                    -- For each detected jersey number, create player hierarchy
                    for _, jerseyNum in ipairs(jerseyNumbers) do
                        local playerName, cleanNumber = PlayerRoster.getPlayerName(jerseyNum)
                        if playerName and cleanNumber then
                            -- Create player name under age group
                            local playerKeyword = photo.catalog:createKeyword(playerName, {}, false, ageGroupKeyword, true)
                            
                            -- Create jersey number under player name and add to photo
                            local jerseyKeyword = photo.catalog:createKeyword("#" .. cleanNumber, {}, true, playerKeyword, true)
                            photo:addKeyword(jerseyKeyword)
                            
                            log:trace("Created hierarchy: Fusion > 2016BN5 > " .. playerName .. " > #" .. cleanNumber)
                        end
                    end
                end)
            end

            -- Delete temp file.
            LrFileUtils.delete(path)

            -- Save metadata informations to catalog.
            catalog:withPrivateWriteAccessDo(function(context)
                    log:trace("Save AI run model and date to metadata")
                    photo:setPropertyForPlugin(_PLUGIN, 'aiModel', prefs.ai)
                    local offset, daylight = LrDate.timeZone()
                    local lastRunDateTime = LrDate.timeToW3CDate(LrDate.currentTime() + offset)
                    photo:setPropertyForPlugin(_PLUGIN, 'aiLastRun', lastRunDateTime)
                end
            )

            if prefs.perfLogging and PerfLogFile ~= nil then
                PerfLogFile:write(photoName .. ";" .. math.floor(stopTimeAnalyze - startTimeAnalyze) .. ";" .. prefs.ai .. ";" ..  prefs.prompt .. ";" .. 
                prefs.generateLanguage .. ";" .. tostring(prefs.temperature) .. ";" .. tostring(prefs.generateKeywords) .. ";" .. 
                tostring(prefs.useKeywordHierarchy) .. ";" .. tostring(prefs.generateAltText) .. 
                ";" .. tostring(prefs.generateTitle) .. ";" .. tostring(prefs.generateCaption) .. ";" .. prefs.exportSize .. ";" .. prefs.exportQuality .. "\n")
            end

            if canceledByUser then
               return false, inputTokens, outputTokens, "canceled", "Canceled by user."
            end

            return true, inputTokens, outputTokens, "non-fatal", ""
        else
            return false, 0, 0, "non-fatal", "Photo rendering failed."
        end
    end
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("AnalyzeImageTask", function(context)
        -- Lazy load the module when the task starts
        if not AnalyzeImageProvider then
            AnalyzeImageProvider = require 'AnalyzeImageProvider'
        end
        
        local startTimeBatch = LrDate.currentTime()

        local catalog = LrApplication.activeCatalog()
        local selectedPhotos = catalog:getTargetPhotos()
        
        -- Randomize photo order for better coverage in large batches
        if #selectedPhotos > 1 then
            math.randomseed(os.time())
            for i = #selectedPhotos, 2, -1 do
                local j = math.random(i)
                selectedPhotos[i], selectedPhotos[j] = selectedPhotos[j], selectedPhotos[i]
            end
            log:trace("Randomized order of " .. #selectedPhotos .. " photos")
        end

        log:trace("Starting AnalyzeImageTask")

        if prefs.perfLogging then
            local path = LrPathUtils.child(LrPathUtils.getStandardFilePath("desktop"), "perflog.csv")
            PerfLogFile = io.open(path, "a")
            if PerfLogFile ~= nil then
                PerfLogFile:write("Filename;Duration;Model;Prompt;Language;Temperature;GenKeywords;useKeywordHierarchy;GenAltText;GenTitle;GenCaption;Export size;ExportQuality\n")
            end
        end

        if #selectedPhotos == 0 then
            LrDialogs.showError("Please select at least one photo.")
            return
        end

        if not prefs.generateCaption and not prefs.generateTitle and not prefs.generateKeywords and not prefs.generateAltText then
            LrDialogs.showError("Nothing selected to generate, check add-on manager settings.")
            return
        end

        if prefs.showPreflightDialog then
            local preflightResult = AnalyzeImageProvider.showPreflightDialog(context)
            if not preflightResult then
                log:trace("Canceled by preflight dialog")
                return false
            end
        end

        local progressScope = LrProgressScope({
            title = "Analyzing photos with " .. prefs.ai,
            functionContext = context,
        })

        local totalPhotos = #selectedPhotos
        local totalFailed = 0
        local errorMessages = {}
        local totalSuccess = 0
        local totalInputTokens = 0
        local totalOutputTokens = 0
        for i, photo in ipairs(selectedPhotos) do
            progressScope:setPortionComplete(i - 1, totalPhotos)
            progressScope:setCaption("Analyzing photo with " .. prefs.ai .. ". Photo " .. tostring(i) .. "/" .. tostring(totalPhotos))

            log:trace("Analyzing " .. photo:getFormattedMetadata('fileName'))

            local success, inputTokens, outputTokens, cause, errorMessage = exportAndAnalyzePhoto(photo, progressScope)
            if inputTokens ~= nil then
                totalInputTokens = totalInputTokens + inputTokens
            end
            if outputTokens ~= nil then
                totalOutputTokens = totalOutputTokens + outputTokens
            end
            if not success then
                totalFailed = totalFailed + 1
                errorMessages[photo:getFormattedMetadata('fileName')] = errorMessage
                log:error("Unsuccessful photo analysis: " .. photo:getFormattedMetadata('fileName'))
                if cause == "fatal" then
                    log:trace("Fatal error received. Stopping.")
                    progressScope:setCaption("Failed to analyze photo with AI " .. tostring(i))
                    LrDialogs.showError("Fatal error: Cannot continue. Check logs.")
                    AnalyzeImageProvider.showUsedTokensDialog(totalInputTokens, totalOutputTokens)
                    return false
                elseif cause == "canceled" then
                    log:trace("Canceled by user validation dialog.")
                    AnalyzeImageProvider.showUsedTokensDialog(totalInputTokens, totalOutputTokens)
                    return false
                end
                    
            else
                totalSuccess = totalSuccess + 1
            end
            progressScope:setPortionComplete(i, totalPhotos)
            if progressScope:isCanceled() then
                log:trace("We got canceled.")
                AnalyzeImageProvider.showUsedTokensDialog(totalInputTokens, totalOutputTokens)
                return false
            end
        end

        progressScope:done()
        local stopTimeBatch = LrDate.currentTime()
        log:trace("Analyzing " .. totalPhotos .. " with " .. prefs.ai .. " took " .. (stopTimeBatch - startTimeBatch) .. " seconds.")

        if prefs.perfLogging and PerfLogFile ~= nil then
            PerfLogFile:close()
        end

        AnalyzeImageProvider.showUsedTokensDialog(totalInputTokens, totalOutputTokens)

        if totalFailed > 0 then
            local errorList
            for name, error in pairs(errorMessages) do
                errorList = name .. " : " .. error .. "\n"
            end
            LrDialogs.message("Failed photos:\n" .. (errorList or ""))
        end
    end)
end)