ErrorHandler = {}

function ErrorHandler.handleError(errorMessage, detailedInfo)
    -- Log the error message
    log:error("Error: " .. errorMessage)
    log:error("Details: " .. (detailedInfo or "No additional details provided."))

    -- Show a dialog to the user with the error message
    -- LrDialogs.message(errorMessage, detailedInfo, "critical")
    ErrorHandler.customErrorDialog(errorMessage, detailedInfo)
end


function ErrorHandler.customErrorDialog(errorMessage, detailedInfo)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local dialogView = f:column {
        f:row {
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/ErrorHandler/Error=Error",
                alignment = 'left',
                font = "<system/bold>",
                width = share "labelWidth",
            },
            f:static_text {
                title = errorMessage,
                alignment = 'left',
                font = "<system/bold>",
            },
        },
        f:row {
            margin_top = 10,
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/ErrorHandler/Details=Details",
                alignment = 'left',
                width = share "labelWidth",
            },
            f:static_text {
                title = detailedInfo or "No additional details provided.",
                alignment = 'left',
                size = 'small',
            },
        },
    }

    local result = LrDialogs.presentModalDialog({
        title = LOC "$$$/lrc-ai-assistant/ErrorHandler/Error=Error",
        contents = dialogView,
        cancelVerb = LOC "$$$/lrc-ai-assistant/ErrorHandler/gatherLogs=Generate report",
    })

    if result == "cancel" then
        Util.copyLogfilesToDesktop()
    end
end