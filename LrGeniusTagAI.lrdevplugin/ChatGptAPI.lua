ChatGptAPI = {}
ChatGptAPI.__index = ChatGptAPI

function ChatGptAPI:new()
    local o = setmetatable({}, ChatGptAPI)

    if Util.nilOrEmpty(prefs.chatgptApiKey) then
        ErrorHandler.handleError('ChatGPT API key not configured', "No ChatGPT API key configured in plug-in manager.")
        return nil
    else
        self.apiKey = prefs.chatgptApiKey
    end

    self.model = prefs.ai

    self.url = Defaults.baseUrls[self.model]

    return o
end

function ChatGptAPI:doRequest(filePath, task, systemInstruction, generationConfig)
    local temperature = prefs.temperature
    if string.sub(self.model, 1, 5) == "gpt-5" then
        temperature = 1 -- ChatGPT 5 models do not support temperature
    end

    local body = {
        model = self.model,
        response_format = generationConfig,
        messages = {
            {
                role = "system",
                content = systemInstruction,
            },
            {
                role = "user",
                content = task,
            },
            {
                role = "user",
                content = {
                    {
                        type = "image_url",
                        image_url = {
                            url = "data:image/jpeg;base64," .. Util.encodePhotoToBase64(filePath)
                        }
                    }
                }
            }
        },
        temperature = temperature,
    }

    if string.sub(self.model, 1, 5) == "gpt-5" then
        body.reasoning_effort = "low" -- gpt-5 models require reasoning_effort to be set
    end

    log:trace(Util.dumpTable(body))

    local response, headers = LrHttp.post(self.url, JSON:encode(body), {{ field = 'Content-Type', value = 'application/json' },  { field = 'Authorization', value = 'Bearer ' .. self.apiKey }}, 'POST', 720)

    if headers.status == 200 then
        if response ~= nil then
            log:trace(response)
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                if decoded.choices ~= nil then
                    if decoded.choices[1].finish_reason == 'stop' then
                        local text = decoded.choices[1].message.content
                        local inputTokenCount = decoded.usage.prompt_tokens
                        local outputTokenCount = decoded.usage.completion_tokens
                        log:trace(text)
                        return true, text, inputTokenCount, outputTokenCount
                    end
                else
                    -- log:error('Blocked: ' .. decoded.choices[1].finish_reason .. Util.dumpTable(decoded.choices[1]))
                    ErrorHandler.handleError('ChatGPT API request failed', 'Finish reason: ' .. decoded.choices[1].finish_reason)
                    local inputTokenCount = decoded.usage.prompt_tokens
                    local outputTokenCount = decoded.usage.completion_tokens
                    return false,  decoded.choices[1].finish_reason, inputTokenCount, outputTokenCount
                end
            else
                ErrorHandler.handleError('ChatGPT API request failed', 'Response from ChatGPT could not be decoded: ' .. response)
                return false, 'Response from ChatGPT could not be decoded', 0, 0
            end
        else
            --log:error('Got empty response from ChatGPT')
            ErrorHandler.handleError('ChatGPT API request failed', 'Got empty response from ChatGPT')
            return false, 'ChatGPT API request failed: Got empty response', 0, 0
        end
    else
        ErrorHandler.handleError('ChatGPT API POST request failed', 'HTTP headers: ' .. Util.dumpTable(headers) .. ' HTTP Response: ' .. (response or 'nil'))
        return false, 'ChatGptAPI POST request failed. ' .. self.url, 0, 0 
    end
end


function ChatGptAPI:analyzeImage(filePath, metadata)
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

    local success, result, inputTokenCount, outputTokenCount = self:doRequest(filePath, task, systemInstruction, ResponseStructure:new():generateResponseStructure())
    if success then
        if prefs.replaceSS then
            result = string.gsub(result, "ß", "ss")
        end
        return success, JSON:decode(result), inputTokenCount, outputTokenCount
    end
    return false, "", inputTokenCount, outputTokenCount
end
