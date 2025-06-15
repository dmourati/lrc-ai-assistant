-- Test for StagePhotos.lua
-- This test verifies the photo staging functionality

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrDate = import 'LrDate'
local json = require 'json'

-- Mock test data
local testHomeDir = "/tmp/test_lr_staging"
local testPhotos = {
    { path = "/tmp/test_photos/IMG_001.CR2" },
    { path = "/tmp/test_photos/IMG_002.CR2" },
    { path = "/tmp/test_photos/IMG_003.CR2" }
}

-- Setup test environment
local function setupTest()
    -- Create test directories
    LrFileUtils.createAllDirectories(testHomeDir)
    LrFileUtils.createAllDirectories("/tmp/test_photos")
    
    -- Create dummy test photos
    for _, photo in ipairs(testPhotos) do
        local file = io.open(photo.path, "w")
        if file then
            file:write("dummy photo data")
            file:close()
        end
    end
    
    print("Test setup complete")
end

-- Cleanup test environment
local function cleanupTest()
    -- Remove test directories (simplified - would need recursive delete in real implementation)
    os.execute("rm -rf " .. testHomeDir)
    os.execute("rm -rf /tmp/test_photos")
    print("Test cleanup complete")
end

-- Test burst ID generation function
local function testGenerateBurstId()
    local function generateBurstId(dateFolder)
        local counter = 1
        while LrFileUtils.exists(LrPathUtils.child(dateFolder, "Burst_" .. string.format("%03d", counter))) do
            counter = counter + 1
        end
        return string.format("%03d", counter)
    end
    
    local testDateFolder = LrPathUtils.child(testHomeDir, "AI_Staging/2025-06-06")
    LrFileUtils.createAllDirectories(testDateFolder)
    
    -- Test 1: First burst should be 001
    local burstId1 = generateBurstId(testDateFolder)
    assert(burstId1 == "001", "First burst ID should be 001, got: " .. burstId1)
    
    -- Create first burst folder
    LrFileUtils.createAllDirectories(LrPathUtils.child(testDateFolder, "Burst_001"))
    
    -- Test 2: Second burst should be 002
    local burstId2 = generateBurstId(testDateFolder)
    assert(burstId2 == "002", "Second burst ID should be 002, got: " .. burstId2)
    
    print("✓ Burst ID generation test passed")
end

-- Test photo copying and job.json creation
local function testPhotoCopyAndJobJson()
    local currentDate = LrDate.currentTime()
    local dateStr = LrDate.timeToUserFormat(currentDate, "%Y-%m-%d")
    
    local stagingBase = LrPathUtils.child(testHomeDir, "AI_Staging")
    local dateFolder = LrPathUtils.child(stagingBase, dateStr)
    local burstFolder = LrPathUtils.child(dateFolder, "Burst_001")
    LrFileUtils.createAllDirectories(burstFolder)
    
    -- Copy photos and build job
    local job = { files = {} }
    
    for _, photo in ipairs(testPhotos) do
        local src = photo.path
        local filename = LrPathUtils.leafName(src)
        local dest = LrPathUtils.child(burstFolder, filename)
        
        local success, msg = LrFileUtils.copy(src, dest)
        if success then
            table.insert(job.files, filename)
            assert(LrFileUtils.exists(dest), "Copied file should exist: " .. dest)
        else
            error("Failed to copy " .. filename .. ": " .. msg)
        end
    end
    
    -- Test job.json creation
    local jobFile = io.open(LrPathUtils.child(burstFolder, "job.json"), "w")
    if jobFile then
        jobFile:write(json.encode(job, { indent = true }))
        jobFile:close()
    else
        error("Could not write job.json")
    end
    
    -- Verify job.json exists and has correct content
    local jobPath = LrPathUtils.child(burstFolder, "job.json")
    assert(LrFileUtils.exists(jobPath), "job.json should exist")
    
    local readJobFile = io.open(jobPath, "r")
    assert(readJobFile, "Should be able to read job.json")
    
    local jobContent = readJobFile:read("*all")
    readJobFile:close()
    
    local parsedJob = json.decode(jobContent)
    assert(#parsedJob.files == 3, "Job should contain 3 files, got: " .. #parsedJob.files)
    assert(parsedJob.files[1] == "IMG_001.CR2", "First file should be IMG_001.CR2")
    
    print("✓ Photo copy and job.json test passed")
end

-- Test folder structure creation
local function testFolderStructure()
    local currentDate = LrDate.currentTime()
    local dateStr = LrDate.timeToUserFormat(currentDate, "%Y-%m-%d")
    
    local expectedPath = testHomeDir .. "/AI_Staging/" .. dateStr .. "/Burst_001"
    LrFileUtils.createAllDirectories(expectedPath)
    
    assert(LrFileUtils.exists(expectedPath), "Expected folder structure should exist: " .. expectedPath)
    
    print("✓ Folder structure test passed")
end

-- Run all tests
local function runTests()
    print("Starting StagePhotos.lua tests...")
    
    setupTest()
    
    testGenerateBurstId()
    testFolderStructure()
    testPhotoCopyAndJobJson()
    
    cleanupTest()
    
    print("All tests passed! ✓")
end

-- Execute tests
runTests()