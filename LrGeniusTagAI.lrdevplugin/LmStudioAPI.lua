LmStudioAPI = {}
LmStudioAPI.__index = LmStudioAPI

function LmStudioAPI:new()
    local o = setmetatable({}, LmStudioAPI)

    self.model = string.sub(prefs.ai, 10, -1)
    self.url = Defaults.baseUrls['lmstudio']

    return o
end


function LmStudioAPI.getLocalVisionModels()
    local response, headers = LrHttp.get(Defaults.baseUrls['lmstudio'] .. Defaults.lmStudioListModelUrl)

    if headers.status == 200 then
        if response ~= nil then
            log:trace(response)
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                local models = {}
                if decoded.data ~= nil and type(decoded.data) == "table" then
                    for _, model in ipairs(decoded.data) do
                        local name = model.id
                        local type = model.type
                        log:trace("Found local installed LmStudio model: " .. name)
                        
                        if type ~= nil and type == "vlm" then
                            log:trace(name .. " has type vlm. Adding it to the list of available models.")
                            table.insert(models, { title = "LMStudio " .. name , value = 'lmstudio-' .. name })
                        else
                            log:trace(name .. " does not have type vlm! Not Adding it to the list of available models.")
                        end
                    end
                end
                return models
            end
        else
            log:error('Got empty response from LmStudioAPI')
        end
    else
        log:error('LmStudioAPI GET request failed. ' .. Defaults.baseUrls['lmstudio'] .. Defaults.lmStudioListModelUrl)
        log:error(Util.dumpTable(headers))
        log:error(response)
        return nil
    end
    return nil
end

function LmStudioAPI:doRequestViaLmStudio(filePath, task, systemInstruction, generationConfig)

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
                            url = "data:image/jpeg;base64," .. Util.encodePhotoToBase64(filePath),
                            detail = "high",
                        }
                    }
                }
            }
        },
        temperature = prefs.temperature,
        top_p = 0.95,
        top_k = 32,
        max_tokens = -1,
    }

    local response, headers = LrHttp.post(self.url .. Defaults.lmStudioChatUrl, JSON:encode(body), {{ field = 'Content-Type', value = 'application/json' }}, 'POST', 720)

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
                    else
                        ErrorHandler.handleError('Error in LmStudioAPI', 'Finish reason: ' .. decoded.choices[1].finish_reason .. ', Response: ' .. Util.dumpTable(decoded))
                        local inputTokenCount = decoded.usage.prompt_tokens
                        local outputTokenCount = decoded.usage.completion_tokens
                        return false,  decoded.choices[1].finish_reason, inputTokenCount, outputTokenCount
                    end
                else
                    ErrorHandler.handleError('Error in LmStudioAPI', Util.dumpTable(decoded))
                    return false, 'LmStudioAPI POST request failed. No choices in response', 0, 0
                end
            else
                ErrorHandler.handleError('LmStudioAPI POST request failed. Error decoding response', 'HTTP headers: ' .. Util.dumpTable(headers) .. ' HTTP Response: ' .. (response or 'nil'))
                return false, 'LmStudioAPI POST request failed. No response', 0, 0
            end
        else
            ErrorHandler.handleError('LmStudioAPI POST request failed. No response', Util.dumpTable(headers))
            return false, 'LmStudioAPI POST request failed. No response', 0, 0
        end
    else
        ErrorHandler.handleError('LmStudioAPI POST request failed', 'HTTP headers: ' .. Util.dumpTable(headers) .. ' HTTP Response: ' .. (response or 'nil'))
        return false, 'LmStudioAPI POST request failed. ' .. self.url, 0, 0 
    end
end

function LmStudioAPI:doRequestViaOpenAI(filePath, task, systemInstruction, generationConfig)

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
                            url = "data:image/jpeg;base64," .. Util.encodePhotoToBase64(filePath),
                            detail = "high",
                        }
                    }
                }
            }
        },
        temperature = prefs.temperature,
        top_p = 0.95,
        top_k = 64,
        max_tokens = -1,
    }

    local response, headers = LrHttp.post(self.url .. Defaults.lmStudioOpenAiChatUrl, JSON:encode(body), {{ field = 'Content-Type', value = 'application/json' }}, 'POST', 720)

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
                    else
                        ErrorHandler.handleError('Error in LmStudioAPI', 'Finish reason: ' .. decoded.choices[1].finish_reason .. ', Response: ' .. Util.dumpTable(decoded))
                        local inputTokenCount = decoded.usage.prompt_tokens
                        local outputTokenCount = decoded.usage.completion_tokens
                        return false,  decoded.choices[1].finish_reason, inputTokenCount, outputTokenCount
                    end
                else
                    ErrorHandler.handleError('Error in LmStudioAPI', Util.dumpTable(decoded))
                    return false, 'LmStudioAPI POST request failed. No choices in response', 0, 0
                end
            else
                ErrorHandler.handleError('LmStudioAPI POST request failed. Error decoding response', 'HTTP headers: ' .. Util.dumpTable(headers) .. ' HTTP Response: ' .. (response or 'nil'))
                return false, 'LmStudioAPI POST request failed. No response', 0, 0
            end
        else
            ErrorHandler.handleError('LmStudioAPI POST request failed. No response', Util.dumpTable(headers))
            return false, 'LmStudioAPI POST request failed. No response', 0, 0
        end
    else
        ErrorHandler.handleError('LmStudioAPI POST request failed', 'HTTP headers: ' .. Util.dumpTable(headers) .. ' HTTP Response: ' .. (response or 'nil'))
        return false, 'LmStudioAPI POST request failed. ' .. self.url, 0, 0 
    end
end


function LmStudioAPI:analyzeImage(filePath, metadata)
    local task = AiModelAPI.generatePromptFromConfiguration()
    if metadata ~= nil then
        if prefs.submitGPS and metadata.gps ~= nil then
            task = task .. " " .. "\nThis photo was taken at the following coordinates:" .. metadata.gps.latitude .. ", " .. metadata.gps.longitude
        end
        if prefs.submitKeywords and metadata.keywords ~= nil then
            task = task .. " " .. "\nSome keywords are:" .. metadata.keywords
        end
        if metadata.context ~= nil and metadata.context ~= "" then
            log:trace("User context given")
            task = task .. "\nSome context for this photo: " .. metadata.context
        end
        if metadata.folderNames ~= nil and prefs.submitFolderNam and string.find(metadata.folderNames, "%a") then
            log:trace("Submit folder names enabled")
            task = task .. "\nThis photo is located in the following folders: " .. metadata.folderNames
        end
    end

    local systemInstruction = AiModelAPI.addKeywordHierarchyToSystemInstruction()

    local success, result, inputTokenCount, outputTokenCount = self:doRequestViaLmStudio(filePath, task, systemInstruction, ResponseStructure:new():generateResponseStructure())
    if success then
        if prefs.replaceSS then
            result = string.gsub(result, "ß", "ss")
        end
        return success, JSON:decode(result), inputTokenCount, outputTokenCount
    end
    return false, "", inputTokenCount, outputTokenCount
end
