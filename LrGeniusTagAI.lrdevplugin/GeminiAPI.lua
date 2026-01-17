GeminiAPI = {}


GeminiAPI.__index = GeminiAPI

function GeminiAPI:new()
    local o = setmetatable({}, GeminiAPI)
    self.rateLimitHit = 0

    if Util.nilOrEmpty(prefs.geminiApiKey) then
        ErrorHandler.handleError('Gemini API key not configured', "No Gemini API key configured in plug-in manager.")
        return nil
    else
        self.apiKey = prefs.geminiApiKey
    end

    self.url = Defaults.baseUrls[prefs.ai] .. self.apiKey
    self.model = prefs.ai

    return o
end

function GeminiAPI:doRequest(filePath, task, systemInstruction, generationConfig)
    if systemInstruction == nil then
        systemInstruction = Defaults.defaultSystemInstruction
    end

    local body = {
        system_instruction = {
            parts = {
                { text = systemInstruction },
            },
        },
        contents = {
            parts = {
                { text = task },
                {
                    inline_data = {
                        data = Util.encodePhotoToBase64(filePath),
                        mime_type = 'image/jpeg'
                    },
                }
            },
        },
        safety_settings = {
            {
                category = "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                threshold = "BLOCK_NONE"
            },
            {
                category = "HARM_CATEGORY_HATE_SPEECH",
                threshold = "BLOCK_NONE"
            },
            {
                category = "HARM_CATEGORY_HARASSMENT",
                threshold = "BLOCK_NONE"
            },
            {
                category = "HARM_CATEGORY_DANGEROUS_CONTENT",
                threshold = "BLOCK_NONE"
            },
        },
    }

    if generationConfig ~= nil then
        body.generationConfig = generationConfig
    end

    log:trace(Util.dumpTable(body))

    local response, headers = LrHttp.post(self.url, JSON:encode(body), {{ field = 'Content-Type', value = 'application/json' },}, 'POST', 720)

    if headers.status == 200 then
        self.rateLimitHit = 0
        if response ~= nil then
            log:trace(response)
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                if decoded.promptFeedback ~= nil then
                    -- log:error('Request blocked: ' .. decoded.promptFeedback.blockReason)
                    ErrorHandler.handleError('Gemini API request blocked', 'Block reason: ' .. decoded.promptFeedback.blockReason)
                    return false, decoded.promptFeedback.blockReason, decoded.usageMetadata.promptTokenCount, decoded.usageMetadata.candidatesTokenCount
                else
                    if decoded.candidates[1].finishReason == 'STOP' then
                        local text = decoded.candidates[1].content.parts[1].text
                        log:trace(text)
                        log:trace(decoded.usageMetadata.promptTokenCount)
                        log:trace(decoded.usageMetadata.candidatesTokenCount)
                        return true, text, decoded.usageMetadata.promptTokenCount, decoded.usageMetadata.candidatesTokenCount
                    else
                        -- log:error('Blocked: ' .. decoded.candidates[1].finishReason .. Util.dumpTable(decoded.candidates[1].safetyRatings))
                        ErrorHandler.handleError('Gemini API request failed', 'Finish reason: ' .. decoded.candidates[1].finishReason)
                        return false, decoded.candidates[1].finishReason, decoded.usageMetadata.promptTokenCount, decoded.usageMetadata.candidatesTokenCount
                    end
                end
            else
                ErrorHandler.handleError('Gemini API request failed', 'Response from Gemini could not be decoded: ' .. response)
                return false, 'Response from Gemini could not be decoded', 0, 0
            end
        else
            -- log:error('Got empty response from Google')
            ErrorHandler.handleError('Gemini API request failed', 'Got empty response from Gemini API')
            return false, 'Gemini API request failed: Got empty response', 0, 0
        end
    elseif headers.status == 429 then
        -- log:error('Rate limit exceeded for ' .. tostring(self.rateLimitHit) .. ' times')
        LrTasks.sleep(5)
        self.rateLimitHit = self.rateLimitHit + 1
        if self.rateLimitHit >= 10 then
            -- log:error('Rate Limit hit 10 times, giving up')
            ErrorHandler.handleError('Gemini API rate limit exhausted', 'Rate limit exceeded for ' .. tostring(self.rateLimitHit) .. ' times. Please consider pay as you go for Gemini.')
            return false, 'RATE_LIMIT_EXHAUSTED', 0, 0
        end
        self:doRequest(filePath, task, systemInstruction, generationConfig)
    else
        ErrorHandler.handleError('Gemini API POST request failed', 'HTTP headers: ' .. Util.dumpTable(headers) .. ' HTTP Response: ' .. (response or 'nil'))
        return false, 'GeminiAPI POST request failed. ' .. self.url, 0, 0
    end
end


function GeminiAPI:analyzeImage(filePath, metadata)
    local task = AiModelAPI.generatePromptFromConfiguration()
    if metadata ~= nil then
        if prefs.submitGPS and metadata.gps ~= nil then
            task = task .. " " .. "\nThis photo was taken at the following coordinates:" .. metadata.gps.latitude .. ", " .. metadata.gps.longitude
        end
        if prefs.submitKeywords and metadata.keywords ~= nil then
            task = task .. " " .. "\nSome keywords are:" .. metadata.keywords
        end
        if metadata.context ~= nil and metadata.context ~= "" then
            log:trace("Preflight context given")
            task = task .. "\nSome context for this photo: " .. metadata.context
        end
        if metadata.folderNames ~= nil and prefs.submitFolderName and string.find(metadata.folderNames, "%a") then
            log:trace("Submit folder names enabled")
            task = task .. "\nThis photo is located in the following folders: " .. metadata.folderNames
        end
    end

    local systemInstruction = AiModelAPI.addKeywordHierarchyToSystemInstruction()

    local success, result, inputTokenCount, outputTokenCount = GeminiAPI:doRequest(filePath, task, systemInstruction, ResponseStructure:new():generateResponseStructure())
    if success and result ~= nil then
        result = string.gsub(result, Defaults.geminiKeywordsGarbageAtStart, '')
        result = string.gsub(result, Defaults.geminiKeywordsGarbageAtEnd, '')
        if prefs.replaceSS then
            result = string.gsub(result, "ß", "ss")
        end
        return success, JSON:decode(result), inputTokenCount, outputTokenCount
    end
    return false, result, inputTokenCount, outputTokenCount
end
