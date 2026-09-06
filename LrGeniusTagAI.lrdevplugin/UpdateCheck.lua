require "Info"

UpdateCheck = {}

UpdateCheck.releaseTagName = "v" .. tostring(Info.MAJOR) .. "." .. tostring(Info.MINOR) .. "." .. tostring(Info.REVISION)
UpdateCheck.updateCheckUrl = "https://api.github.com/repos/LrGenius/LrGeniusTagAI/releases/latest"
UpdateCheck.latestReleaseUrl = "https://github.com/LrGenius/LrGeniusTagAI/releases/latest"

-- silentIfCurrent: when true, no message is shown if the installed version is already the latest.
function UpdateCheck.checkForNewVersion(silentIfCurrent)
    local response, headers = LrHttp.get(UpdateCheck.updateCheckUrl)

    if headers.status == 200 then
        if response ~= nil then
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                if decoded.tag_name ~= UpdateCheck.releaseTagName then
                    LrHttp.openUrlInBrowser(UpdateCheck.latestReleaseUrl)
                elseif not silentIfCurrent then
                    LrDialogs.message(LOC "$$$/lrc-ai-assistant/UpdateCheck/onCurrentVersion=You're running the current version of LrGeniusTagAI", UpdateCheck.releaseTagName)
                else
                    log:trace("Update check: already on latest version " .. UpdateCheck.releaseTagName .. ", message suppressed.")
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

function UpdateCheck.checkForNewVersionInBackground(silentIfCurrent)
    return UpdateCheck.checkForNewVersion(silentIfCurrent)
end