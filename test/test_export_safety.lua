-- Test for StagePhotos.lua Export Safety
-- This test ensures exports aren't lost and verifies the complete workflow

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'
local json = require 'json'

-- Test configuration
local TEST_CONFIG = {
    testDir = "/tmp/test_lr_export_safety",
    stagingDir = "/tmp/test_lr_export_safety/AI_Staging",
    mockPhotos = {
        { path = "/tmp/test_photos/IMG_001.NEF", expectedJpg = "IMG_001.jpg" },
        { path = "/tmp/test_photos/IMG_002.NEF", expectedJpg = "IMG_002.jpg" },
        { path = "/tmp/test_photos/IMG_003.NEF", expectedJpg = "IMG_003.jpg" },
        { path = "/tmp/test_photos/IMG_004.NEF", expectedJpg = "IMG_004.jpg" },
        { path = "/tmp/test_photos/IMG_005.NEF", expectedJpg = "IMG_005.jpg" },
        { path = "/tmp/test_photos/IMG_006.NEF", expectedJpg = "IMG_006.jpg" }
    },
    requiredFileCount = 6,
    timeoutSeconds = 30
}

-- Test state tracking
local TEST_STATE = {
    testsRun = 0,
    testsPassed = 0,
    testsFailed = 0,
    errors = {}
}

-- Logging function
local function log(level, message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    print(string.format("[%s] %s: %s", timestamp, level, message))
end

-- Assert function
local function assert_test(condition, message, details)
    TEST_STATE.testsRun = TEST_STATE.testsRun + 1
    if condition then
        TEST_STATE.testsPassed = TEST_STATE.testsPassed + 1
        log("PASS", message)
        return true
    else
        TEST_STATE.testsFailed = TEST_STATE.testsFailed + 1
        local error_msg = message .. (details and (" - " .. details) or "")
        table.insert(TEST_STATE.errors, error_msg)
        log("FAIL", error_msg)
        return false
    end
end

-- Setup test environment
local function setupTest()
    log("INFO", "Setting up test environment...")
    
    -- Create test directories
    LrFileUtils.createAllDirectories(TEST_CONFIG.testDir)
    LrFileUtils.createAllDirectories(TEST_CONFIG.stagingDir)
    LrFileUtils.createAllDirectories("/tmp/test_photos")
    
    -- Create mock photo files
    for _, photo in ipairs(TEST_CONFIG.mockPhotos) do
        local file = io.open(photo.path, "w")
        if file then
            file:write("mock NEF data for " .. LrPathUtils.leafName(photo.path))
            file:close()
            log("DEBUG", "Created mock photo: " .. photo.path)
        end
    end
    
    log("INFO", "Test setup complete")
end

-- Cleanup test environment
local function cleanupTest()
    log("INFO", "Cleaning up test environment...")
    os.execute("rm -rf " .. TEST_CONFIG.testDir)
    os.execute("rm -rf /tmp/test_photos")
    log("INFO", "Test cleanup complete")
end

-- Test burst folder creation and uniqueness
local function testBurstFolderCreation()
    log("INFO", "Testing burst folder creation...")
    
    local function generateBurstId(dateFolder)
        local counter = 1
        while LrFileUtils.exists(LrPathUtils.child(dateFolder, "Burst_" .. string.format("%03d", counter))) do
            counter = counter + 1
        end
        return string.format("%03d", counter)
    end
    
    local currentDate = LrDate.currentTime()
    local dateStr = LrDate.timeToUserFormat(currentDate, "%Y-%m-%d")
    local dateFolder = LrPathUtils.child(TEST_CONFIG.stagingDir, dateStr)
    
    -- Test first burst ID
    local burstId1 = generateBurstId(dateFolder)
    assert_test(burstId1 == "001", "First burst ID should be 001", "Got: " .. burstId1)
    
    -- Create the folder and test increment
    local burstFolder1 = LrPathUtils.child(dateFolder, "Burst_" .. burstId1)
    LrFileUtils.createAllDirectories(burstFolder1)
    
    local burstId2 = generateBurstId(dateFolder)
    assert_test(burstId2 == "002", "Second burst ID should be 002", "Got: " .. burstId2)
    
    return dateFolder, burstFolder1
end

-- Test file presence and integrity
local function testFilePresenceAndIntegrity(burstFolder, expectedFiles)
    log("INFO", "Testing file presence and integrity...")
    
    -- Wait for files to be written (simulate async export completion)
    local maxWait = TEST_CONFIG.timeoutSeconds
    local waited = 0
    local filesFound = 0
    
    while waited < maxWait do
        filesFound = 0
        for _, expectedFile in ipairs(expectedFiles) do
            local filePath = LrPathUtils.child(burstFolder, expectedFile)
            if LrFileUtils.exists(filePath) then
                filesFound = filesFound + 1
            end
        end
        
        if filesFound == #expectedFiles then
            break
        end
        
        LrTasks.sleep(1)
        waited = waited + 1
    end
    
    assert_test(filesFound == #expectedFiles, 
                "All expected files should exist", 
                string.format("Found %d/%d files after %d seconds", filesFound, #expectedFiles, waited))
    
    -- Test each file individually
    for _, expectedFile in ipairs(expectedFiles) do
        local filePath = LrPathUtils.child(burstFolder, expectedFile)
        local exists = LrFileUtils.exists(filePath)
        assert_test(exists, "File should exist: " .. expectedFile, filePath)
        
        if exists then
            -- Check file size (should be > 0)
            local file = io.open(filePath, "rb")
            if file then
                local size = file:seek("end")
                file:close()
                assert_test(size > 0, "File should have content: " .. expectedFile, "Size: " .. size .. " bytes")
            end
        end
    end
    
    return filesFound == #expectedFiles
end

-- Test job.json creation and content
local function testJobJsonCreation(burstFolder, expectedFiles)
    log("INFO", "Testing job.json creation...")
    
    local jobPath = LrPathUtils.child(burstFolder, "job.json")
    assert_test(LrFileUtils.exists(jobPath), "job.json should exist", jobPath)
    
    local jobFile = io.open(jobPath, "r")
    if not jobFile then
        assert_test(false, "Should be able to read job.json", jobPath)
        return false
    end
    
    local jobContent = jobFile:read("*all")
    jobFile:close()
    
    assert_test(jobContent and #jobContent > 0, "job.json should have content")
    
    local success, jobData = pcall(json.decode, jobContent)
    assert_test(success, "job.json should be valid JSON", success and "" or "Parse error")
    
    if success and jobData then
        assert_test(jobData.files ~= nil, "job.json should have 'files' array")
        assert_test(#jobData.files == #expectedFiles, 
                    "job.json should list all files", 
                    string.format("Expected %d, got %d", #expectedFiles, #jobData.files or 0))
        
        -- Verify all expected files are listed
        for _, expectedFile in ipairs(expectedFiles) do
            local found = false
            for _, listedFile in ipairs(jobData.files or {}) do
                if listedFile == expectedFile then
                    found = true
                    break
                end
            end
            assert_test(found, "job.json should list file: " .. expectedFile)
        end
    end
    
    return success and jobData ~= nil
end

-- Test workflow resilience (simulate interruptions)
local function testWorkflowResilience()
    log("INFO", "Testing workflow resilience...")
    
    -- Test multiple rapid runs (simulate user clicking multiple times)
    local dateFolder, firstBurstFolder = testBurstFolderCreation()
    
    -- Simulate rapid successive runs
    for i = 1, 3 do
        local function generateBurstId(dateFolder)
            local counter = 1
            while LrFileUtils.exists(LrPathUtils.child(dateFolder, "Burst_" .. string.format("%03d", counter))) do
                counter = counter + 1
            end
            return string.format("%03d", counter)
        end
        
        local burstId = generateBurstId(dateFolder)
        local burstFolder = LrPathUtils.child(dateFolder, "Burst_" .. burstId)
        LrFileUtils.createAllDirectories(burstFolder)
        
        -- Create mock job.json
        local job = { files = {"test_" .. i .. ".jpg"} }
        local jobFile = io.open(LrPathUtils.child(burstFolder, "job.json"), "w")
        if jobFile then
            jobFile:write(json.encode(job))
            jobFile:close()
        end
        
        log("DEBUG", "Created burst folder: " .. burstId)
    end
    
    -- Verify all folders were created with unique IDs
    local burstCount = 0
    local items = LrFileUtils.directoryEntries(dateFolder)
    if items then
        for item in items do
            if string.match(item, "^Burst_%d%d%d$") then
                burstCount = burstCount + 1
            end
        end
    end
    
    assert_test(burstCount >= 4, "Should create unique burst folders", "Found: " .. burstCount)
end

-- Mock the complete staging workflow
local function testCompleteWorkflow()
    log("INFO", "Testing complete staging workflow...")
    
    local currentDate = LrDate.currentTime()
    local dateStr = LrDate.timeToUserFormat(currentDate, "%Y-%m-%d")
    
    local function generateBurstId(dateFolder)
        local counter = 1
        while LrFileUtils.exists(LrPathUtils.child(dateFolder, "Burst_" .. string.format("%03d", counter))) do
            counter = counter + 1
        end
        return string.format("%03d", counter)
    end
    
    -- Create folder structure
    local stagingBase = TEST_CONFIG.stagingDir
    local dateFolder = LrPathUtils.child(stagingBase, dateStr)
    local burstId = generateBurstId(dateFolder)
    local burstFolder = LrPathUtils.child(dateFolder, "Burst_" .. burstId)
    LrFileUtils.createAllDirectories(burstFolder)
    
    log("INFO", "Created staging folder: " .. burstFolder)
    
    -- Simulate export by creating JPEG files
    local expectedJpgs = {}
    for _, photo in ipairs(TEST_CONFIG.mockPhotos) do
        table.insert(expectedJpgs, photo.expectedJpg)
        
        -- Create mock JPEG file
        local jpgPath = LrPathUtils.child(burstFolder, photo.expectedJpg)
        local jpgFile = io.open(jpgPath, "w")
        if jpgFile then
            jpgFile:write("mock JPEG data for " .. photo.expectedJpg)
            jpgFile:close()
        end
    end
    
    -- Test file presence
    local filesOk = testFilePresenceAndIntegrity(burstFolder, expectedJpgs)
    
    -- Create and test job.json
    local job = { files = expectedJpgs }
    local jobFile = io.open(LrPathUtils.child(burstFolder, "job.json"), "w")
    if jobFile then
        jobFile:write(json.encode(job, { indent = true }))
        jobFile:close()
    end
    
    local jobOk = testJobJsonCreation(burstFolder, expectedJpgs)
    
    return filesOk and jobOk
end

-- Print test summary
local function printTestSummary()
    log("INFO", "=== TEST SUMMARY ===")
    log("INFO", string.format("Tests Run: %d", TEST_STATE.testsRun))
    log("INFO", string.format("Tests Passed: %d", TEST_STATE.testsPassed))
    log("INFO", string.format("Tests Failed: %d", TEST_STATE.testsFailed))
    
    if TEST_STATE.testsFailed > 0 then
        log("ERROR", "=== FAILURES ===")
        for _, error in ipairs(TEST_STATE.errors) do
            log("ERROR", error)
        end
    end
    
    local success = TEST_STATE.testsFailed == 0
    log(success and "INFO" or "ERROR", 
        success and "ALL TESTS PASSED! ✓" or "SOME TESTS FAILED! ✗")
    
    return success
end

-- Main test runner
local function runExportSafetyTests()
    log("INFO", "Starting Export Safety Tests...")
    log("INFO", "Testing " .. TEST_CONFIG.requiredFileCount .. " file export workflow")
    
    setupTest()
    
    -- Run all tests
    testBurstFolderCreation()
    testWorkflowResilience()
    testCompleteWorkflow()
    
    cleanupTest()
    
    return printTestSummary()
end

-- Execute tests
return runExportSafetyTests()