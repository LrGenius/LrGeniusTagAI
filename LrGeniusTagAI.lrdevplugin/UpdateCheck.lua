require "Info"

UpdateCheck = {}

UpdateCheck.releaseTagName = tostring(Info.MAJOR) .. "." .. tostring(Info.MINOR) .. "." .. tostring(Info.REVISION)

function UpdateCheck.checkForNewVersion()
    return nil
end

function UpdateCheck.checkForNewVersionInBackground()
    return nil
end