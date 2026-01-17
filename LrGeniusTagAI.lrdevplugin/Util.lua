-- Helper functions

Util = {}

-- Utility function to check if table contains a value
function Util.table_contains(tbl, x)
    local found = false
    for _, v in pairs(tbl) do
        if v == x then
            found = true
        end
    end
    return found
end

-- Utility function to dump tables as JSON scrambling the API key and removing base64 strings.
function Util.dumpTable(t)
    local s = inspect(t)
    local pattern = '(data = )"([A-Za-z0-9+/=]+)"'
    local result, count = s:gsub(pattern, '%1 base64 removed')
    pattern = '(url = "data:image/jpeg;base64,)([A-Za-z0-9+/]+=?=?)"'
    result, count = result:gsub(pattern, '%1 base64 removed')
    return result
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

function Util.trim(s)
    return trim(s)
end

function Util.nilOrEmpty(val)
    if type(val) == 'string' then
        return val == nil or trim(val) == ''
    else
        return val == nil
    end
end

function Util.string_split(s, delimiter)
    local t = {}
    for str in string.gmatch(s, "([^" .. delimiter .. "]+)") do
        table.insert(t, trim(str))
    end
    return t
end


function Util.encodePhotoToBase64(filePath)
    local file = io.open(filePath, "rb")
    if not file then
        return nil
    end

    local data = file:read("*all")
    file:close()

    local base64 = LrStringUtils.encodeBase64(data)
    return base64
end

function Util.getStringsFromRelativePath(absolutePath)
    local catalog = LrApplication.activeCatalog()
    local rootFolders = catalog:getFolders()

    for _, folder in ipairs(rootFolders) do
        local rootFolder = folder:getPath()
        log:trace("Root folder: " .. rootFolder)
        local relativePath = LrPathUtils.parent(LrPathUtils.makeRelative(absolutePath, rootFolder))
        if relativePath ~= nil and string.len(relativePath) > 0 and string.len(relativePath) < string.len(absolutePath) then
            log:trace("Relative path: " .. relativePath)
            relativePath = string.gsub(relativePath, "[/\\\\]", " ")
            relativePath = string.gsub(relativePath, "[^%a%säöüÄÖÜ]", "")
            log:trace("Processed relative path: " .. relativePath)
            return relativePath
        end
    end
end

function Util.getLogfilePath()
    local filename = "LrGeniusTagAI.log"
    local macPath14 = LrPathUtils.getStandardFilePath('home') .. "/Library/Logs/Adobe/Lightroom/LrClassicLogs/"
    local winPath14 = LrPathUtils.getStandardFilePath('home') .. "\\AppData\\Local\\Adobe\\Lightroom\\Logs\\LrClassicLogs\\"
    local macPathOld = LrPathUtils.getStandardFilePath('documents') .. "/LrClassicLogs/"
    local winPathOld = LrPathUtils.getStandardFilePath('documents') .. "\\LrClassicLogs\\"

    local lightroomVersion = LrApplication.versionTable()

    if lightroomVersion.major >= 14 then
        if MAC_ENV then
            return macPath14 .. filename
        else
            return winPath14 .. filename
        end
    else
        if MAC_ENV then
            return macPathOld .. filename
        else
            return winPathOld .. filename
        end
    end
end

function Util.copyLogfilesToDesktop()

    local folder = LrPathUtils.child(LrPathUtils.getStandardFilePath('desktop'), "LrGenius_" .. LrDate.timeToIsoDate(LrDate.currentTime()))
    if not LrFileUtils.exists(folder) then
        log:trace("Removing pre-existing report folder: " .. folder)
        LrFileUtils.moveToTrash(folder)
    end
    log:trace("Creating report folder: " .. folder)
    LrFileUtils.createDirectory(folder)

    local filePath = LrPathUtils.child(folder, 'LrGeniusTagAI.log')
    local logFilePath = Util.getLogfilePath()
    if LrFileUtils.exists(logFilePath) then
        LrFileUtils.copy(logFilePath, filePath)
    else
        ErrorHandler.showError(LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/logfileNotFound=Logfile not found", logFilePath)
    end

    local ollamaLogfilePath = Util.getOllamaLogfilePath()
    if LrFileUtils.exists(ollamaLogfilePath) then
        LrFileUtils.copy(ollamaLogfilePath, LrPathUtils.child(folder, 'ollama.log'))
    else
        log:trace("Ollama log file not found at: " .. ollamaLogfilePath)
    end

    if LrFileUtils.exists(filePath) then
        LrShell.revealInShell(filePath)
    else
        ErrorHandler.showError(LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/logfileCopyFailed=Logfile copy failed", filePath)
    end

end

function Util.getOllamaLogfilePath()
    local macPath = LrPathUtils.getStandardFilePath('home') .. "/.ollama/logs/server.log"
    local winPath = LrPathUtils.getStandardFilePath('home') .. "\\AppData\\Local\\ollama\\server.log"

    if MAC_ENV then
        log:trace("Using macOS path for Ollama log: " .. macPath)
        return macPath
    else
        log:trace("Using Windows path for Ollama log: " .. winPath)
        return winPath
    end
end

function Util.deepcopy(o, seen)

    seen = seen or {}
    if o == nil then return nil end
    if seen[o] then return seen[o] end

    local no
    if type(o) == 'table' then
        no = {}
        seen[o] = no

        for k, v in next, o, nil do
            no[Util.deepcopy(k, seen)] = Util.deepcopy(v, seen)
        end
    setmetatable(no, Util.deepcopy(getmetatable(o), seen))
    else
        no = o
    end
    return no

end



---
-- Extracts all keywords (strings) from the inner arrays of the
-- hierarchical table and returns them as a single, flat list.
--
-- @param hierarchicalTable The original table with categories.
-- @return A flat table (array) containing all keywords.
--
function Util.extractAllKeywords(hierarchicalTable)
    local flatList = {}
    -- Iterate through all categories (e.g., "Location", "Plants")
    for _, categoryValues in pairs(hierarchicalTable) do
        -- Iterate through all keywords within a category
        if type(categoryValues) == 'table' then
            -- If the category is a table, we assume it contains keywords
            -- and we add them to the flat list.
            -- This allows for categories with multiple keywords.
            for _, keyword in ipairs(categoryValues) do
                table.insert(flatList, keyword)
            end
        else
            -- If the category is not a table, we assume it's a single keyword
            -- and we add it directly to the flat list.
            flatList = hierarchicalTable
        end
    end

    local result = {}

    for _, keyword in ipairs(flatList) do
        local keywordWoDots = string.gsub(keyword, "%.", "_;_")
        -- Ensure that each keyword is trimmed of whitespace
        result[keywordWoDots] = keyword
    end

    return result
end

---
-- Reconstructs the hierarchical table structure based on a
-- list of selected keywords.
--
-- @param originalTable The original table, used as a structural template.
-- @param selectedKeywords A flat list of keywords to keep.
-- @return A new hierarchical table containing only the selected keywords.
--
function Util.rebuildTableFromKeywords(originalTable, keywordsVal, keywordsSel)
    local newTable = {}
    -- We iterate through the *original* table to preserve the structure.
    for category, oldKeywords in pairs(originalTable) do
        if type(category) == 'string' then
        newTable[category] = {} -- Create the category in the new table
            -- We iterate through the keywords of the original category.
            for _, keyword in ipairs(oldKeywords) do
                local keywordWoDots = string.gsub(keyword, "%.", "_;_")
                -- Only if the keyword exists in our set of selected keywords,
                -- we add it to the new table.
                if keywordsSel[keywordWoDots] then
                    table.insert(newTable[category], keywordsVal[keywordWoDots])
                end
            end
        else
            -- table.insert(newTable, oldKeywords)
            for _, keyword in pairs(keywordsVal) do
                -- local keywordWoDots = string.gsub(keyword, "%.", "_;_")
                if keywordsSel[_] then
                    table.insert(newTable, keywordsVal[_])
                end
            end
        end
    end
    return newTable
end