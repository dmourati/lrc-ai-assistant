local log = require 'Logger'

local RateLimitManager = {}

-- Token tracking for rate limiting
RateLimitManager.tokenUsage = {
    lastReset = os.time(),
    tokensUsed = 0,
    tokenLimit = 200000,  -- OpenAI's TPM limit for gpt-4o-mini
    resetInterval = 60    -- 60 seconds (1 minute)
}

-- Request tracking
RateLimitManager.requestTracking = {
    lastRequestTime = 0,
    minDelayBetweenRequests = 0.5,  -- 500ms minimum between requests
    backoffMultiplier = 1.0
}

function RateLimitManager:resetIfNeeded()
    local currentTime = os.time()
    local timeSinceReset = currentTime - self.tokenUsage.lastReset
    
    if timeSinceReset >= self.tokenUsage.resetInterval then
        self.tokenUsage.tokensUsed = 0
        self.tokenUsage.lastReset = currentTime
        self.requestTracking.backoffMultiplier = 1.0  -- Reset backoff
        log:trace("[RATE_LIMIT] Token usage reset. New minute started.")
    end
end

function RateLimitManager:canMakeRequest(estimatedTokens)
    self:resetIfNeeded()
    
    -- Check token limits
    if self.tokenUsage.tokensUsed + estimatedTokens > self.tokenUsage.tokenLimit then
        local timeUntilReset = self.tokenUsage.resetInterval - (os.time() - self.tokenUsage.lastReset)
        log:warn(string.format("[RATE_LIMIT] Would exceed token limit. Used: %d, Requested: %d, Limit: %d. Wait %d seconds.", 
                               self.tokenUsage.tokensUsed, estimatedTokens, self.tokenUsage.tokenLimit, timeUntilReset))
        return false, timeUntilReset
    end
    
    -- Check time-based rate limiting
    local timeSinceLastRequest = os.time() - self.requestTracking.lastRequestTime
    local requiredDelay = self.requestTracking.minDelayBetweenRequests * self.requestTracking.backoffMultiplier
    
    if timeSinceLastRequest < requiredDelay then
        local waitTime = requiredDelay - timeSinceLastRequest
        log:trace(string.format("[RATE_LIMIT] Too soon since last request. Wait %.2f seconds.", waitTime))
        return false, waitTime
    end
    
    return true, 0
end

function RateLimitManager:recordRequest(tokensUsed)
    self.tokenUsage.tokensUsed = self.tokenUsage.tokensUsed + tokensUsed
    self.requestTracking.lastRequestTime = os.time()
    log:trace(string.format("[RATE_LIMIT] Recorded %d tokens. Total this minute: %d/%d", 
                            tokensUsed, self.tokenUsage.tokensUsed, self.tokenUsage.tokenLimit))
end

function RateLimitManager:handleRateLimitError(errorMessage)
    -- Increase backoff multiplier
    self.requestTracking.backoffMultiplier = math.min(self.requestTracking.backoffMultiplier * 2, 10)
    
    -- Try to extract wait time from error message
    local waitTimeMs = errorMessage:match("Please try again in (%d+)ms")
    if waitTimeMs then
        local waitTimeSec = tonumber(waitTimeMs) / 1000
        log:warn(string.format("[RATE_LIMIT] Rate limited. Increasing backoff to %.1fx. API suggests waiting %.2f seconds.", 
                               self.requestTracking.backoffMultiplier, waitTimeSec))
        return waitTimeSec
    end
    
    -- Default wait time if not specified
    return self.requestTracking.minDelayBetweenRequests * self.requestTracking.backoffMultiplier
end

function RateLimitManager:estimateTokens(prompt, imagePath)
    -- More accurate token estimation for gpt-4o-mini
    -- Text: ~1 token per 4 characters (conservative estimate)
    local promptTokens = math.ceil(#prompt / 3)  -- Conservative: ~3 chars per token
    
    -- Image tokens depend on resolution
    -- For 1024px images at 50% quality: ~1000-1500 tokens
    local imageTokens = 0
    if imagePath then
        -- Conservative estimate for vision models
        imageTokens = 1500  -- Assume worst case for safety
    end
    
    return promptTokens + imageTokens
end

return RateLimitManager