-- Lightroom Plugin: StagePhotos.lua
-- Exports selected photos as JPEGs to ~/AI_Staging/yyyy-mm-dd/Burst_###/ and writes job.json for external OpenAI analysis

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrDate = import 'LrDate'
local LrView = import 'LrView'
local LrExportSession = import 'LrExportSession'
local LrExportSettings = import 'LrExportSettings'
local LrTasks = import 'LrTasks'

local json = require 'json'

-- Logging function
local function writeLog(level, message)
    local homeDir = LrPathUtils.getStandardFilePath('home')
    local logFile = io.open(LrPathUtils.child(homeDir, "AI_Staging/stage_photos.log"), "a")
    if logFile then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        logFile:write(string.format("[%s] %s: %s\n", timestamp, level, message))
        logFile:close()
    end
end

local catalog = LrApplication.activeCatalog()
local photos = catalog:getTargetPhotos()

-- Check if photos are selected
if not photos or #photos == 0 then
    writeLog("ERROR", "No photos selected for staging")
    return
end

-- Configuration
local MAX_FILES_PER_BURST = 9

-- Break photos into chunks
local function chunkPhotos(photos, chunkSize)
    local chunks = {}
    for i = 1, #photos, chunkSize do
        local chunk = {}
        for j = i, math.min(i + chunkSize - 1, #photos) do
            table.insert(chunk, photos[j])
        end
        table.insert(chunks, chunk)
    end
    return chunks
end

local photoChunks = chunkPhotos(photos, MAX_FILES_PER_BURST)
local totalChunks = #photoChunks

writeLog("INFO", "Starting export of " .. #photos .. " photos in " .. totalChunks .. " burst(s)")

-- Get current date for folder structure
local currentDate = LrDate.currentTime()
local dateStr = LrDate.timeToUserFormat(currentDate, "%Y-%m-%d")

-- Generate burst ID automatically
local function generateBurstId(dateFolder)
    local counter = 1
    while LrFileUtils.exists(LrPathUtils.child(dateFolder, "Burst_" .. string.format("%03d", counter))) do
        counter = counter + 1
    end
    return string.format("%03d", counter)
end

local homeDir = LrPathUtils.getStandardFilePath('home')
local stagingBase = LrPathUtils.child(homeDir, "AI_Staging")
local dateFolder = LrPathUtils.child(stagingBase, dateStr)

-- Export photos as JPEGs using Lightroom's export functionality
LrTasks.startAsyncTask(function()
    catalog:withWriteAccessDo("Export photos for AI analysis", function()
        
        -- Process each chunk as a separate burst
        for chunkIndex, photoChunk in ipairs(photoChunks) do
            local burstId = generateBurstId(dateFolder)
            local burstFolder = LrPathUtils.child(dateFolder, "Burst_" .. burstId)
            LrFileUtils.createAllDirectories(burstFolder)
            
            writeLog("INFO", "Processing chunk " .. chunkIndex .. "/" .. totalChunks .. " (" .. #photoChunk .. " photos)")
            writeLog("INFO", "Created staging folder: " .. burstFolder)
            
            -- Configure JPEG export settings for this burst
            local exportSettings = {
                LR_export_destinationType = "specificFolder",
                LR_export_destinationPathPrefix = burstFolder,
                LR_format = "JPEG",
                LR_jpeg_quality = 0.8,
                LR_size_doConstrain = true,
                LR_size_doNotEnlarge = true,
                LR_size_maxHeight = 1024,
                LR_size_maxWidth = 1024,
                LR_size_resizeType = "longEdge",
                LR_reimportExportedPhoto = false,
                LR_export_useSubfolder = false,
                LR_renamingTokensOn = false,
            }
            
            -- Create export session for this chunk
            local exportSession = LrExportSession {
                photosToExport = photoChunk,
                exportSettings = exportSettings,
            }
            
            -- Execute the export
            writeLog("INFO", "Starting JPEG export to " .. burstFolder)
            exportSession:doExportOnCurrentTask()
            writeLog("INFO", "Export completed for chunk " .. chunkIndex)
            
            -- Add ExportID and Workflow keywords to photos before generating job.json
            -- No nested withWriteAccessDo needed - we're already in a write access block
            -- Create or find the Workflow|Exported keyword once for all photos
            local workflowExportedKeyword = catalog:createKeyword("Workflow|Exported", {}, false, nil, true)
            
            for _, photo in ipairs(photoChunk) do
                -- Generate the exported filename (typically the same as original but with .jpg extension)
                local originalPath = photo.path
                local baseName = LrPathUtils.removeExtension(LrPathUtils.leafName(originalPath))
                local exportId = "ExportID|" .. baseName
                
                -- Create or find the ExportID keyword and add it to the photo
                local exportIdKeyword = catalog:createKeyword(exportId, {}, false, nil, true)
                photo:addKeyword(exportIdKeyword)
                
                -- Add Workflow|Exported keyword to the photo
                photo:addKeyword(workflowExportedKeyword)
                
                writeLog("INFO", "Added keywords: " .. exportId .. " and Workflow|Exported to photo: " .. baseName)
            end
            
            -- Generate list of exported filenames for job.json
            local job = {
                files = {}
            }
            
            for _, photo in ipairs(photoChunk) do
                -- Generate the exported filename (typically the same as original but with .jpg extension)
                local originalPath = photo.path
                local baseName = LrPathUtils.removeExtension(LrPathUtils.leafName(originalPath))
                local exportedFilename = baseName .. ".jpg"
                table.insert(job.files, exportedFilename)
            end
            
            -- Write job.json
            local jobFile = io.open(LrPathUtils.child(burstFolder, "job.json"), "w")
            if jobFile then
                jobFile:write(json.encode(job, { indent = true }))
                jobFile:close()
                writeLog("SUCCESS", "Exported " .. #job.files .. " JPEGs to " .. burstFolder)
                writeLog("INFO", "Created job.json with files: " .. table.concat(job.files, ", "))
            else
                writeLog("ERROR", "Could not write job.json to " .. burstFolder)
            end
        end
        
        writeLog("INFO", "Completed all " .. totalChunks .. " burst(s) - total " .. #photos .. " photos exported")
    end)
end)

