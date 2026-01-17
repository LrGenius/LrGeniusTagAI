AnalyzeImageProvider = {}


function AnalyzeImageProvider.addKeywordRecursively(photo, keywordSubTable, parent)
    for key, value in pairs(keywordSubTable) do
        local keyword
        if type(key) == 'string' and key ~= "" then
            photo.catalog:withWriteAccessDo("Create category keyword", function()
                -- Some ollama models return "None" or "none" if a keyword category is empty.
                if prefs.useKeywordHierarchy and key ~= "None" and key ~= "none" then
                    keyword = photo.catalog:createKeyword(key, {}, false, parent, true)
                end
            end)
        elseif type(key) == 'number' and value ~= nil and value ~= "" then
            photo.catalog:withWriteAccessDo("Create and add keyword", function()
                -- Some ollama models return "None" or "none" if a keyword category is empty.
                if not prefs.useKeywordHierarchy then
                    parent = nil
                end
                if value ~= "None" and value ~= "none" then
                    keyword = photo.catalog:createKeyword(value, {}, true, parent, true)
                    photo:addKeyword(keyword)
                end
            end)
        end
        if type(value) == 'table' then
            AnalyzeImageProvider.addKeywordRecursively(photo, value, keyword)
        end
    end
end


function AnalyzeImageProvider.showValidationDialog(ctx, keywords, title, caption, altText)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local propertyTable = LrBinding.makePropertyTable(ctx)
    propertyTable.skipFromHere = false
    propertyTable.keywordsVal = Util.extractAllKeywords(keywords or {})
    propertyTable.keywordsSel = {}
    propertyTable.title = title or ""
    propertyTable.caption = caption or ""
    propertyTable.altText = altText or ""

    propertyTable.saveKeywords = keywords ~= nil and type(keywords) == 'table'
    propertyTable.saveTitle = title ~= nil and title ~= ""
    propertyTable.saveCaption = caption ~= nil and caption ~= ""
    propertyTable.saveAltText = altText ~= nil and altText ~= ""
    -- propertyTable.keywordWidth = 50

    local keywordRows = {}
    local keywordLabels = {}

    local keywordCount = 0
    for _, keyword in pairs(propertyTable.keywordsVal) do
        if propertyTable.keywordsSel[_] == nil then -- Prevent duplicates
            propertyTable.keywordsSel[_] = true
            keywordCount = keywordCount + 1
            table.insert(keywordLabels, f:checkbox { value = bind('keywordsSel.' .. _), visible = bind 'saveKeywords' })
            table.insert(keywordLabels, f:edit_field { value = bind('keywordsVal.' .. _), width_in_chars = 15, immediate = true, enabled = bind 'saveKeywords' })
        end
    end

    local rowCount = #keywordLabels / 10 + 1

    for i = 1, rowCount do
        local row = {}
        for j = 1, 10 do
            local index = (i - 1) * 10 + j
            if index <= #keywordLabels then
                table.insert(row, keywordLabels[index])
            end
        end
        table.insert(keywordRows, f:row(row))
    end

    local dialogView = f:column {
        bind_to_object = propertyTable,
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveKeywords',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveKeywords=Save keywords",
                width = share 'labelWidth',
            },
            f:column(keywordRows),
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveTitle',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveTitle=Save title",
                width = share 'labelWidth',
            },
            f:edit_field {
                value = bind 'title',
                -- width_in_chars = 40,
                fill_horizontal = 1,
                height_in_lines = 1,
                enabled = bind 'saveTitle',  -- Enable only if the checkbox is checked
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveCaption',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveCaption=Save caption",
                width = share 'labelWidth',
            },
            f:edit_field {
                value = bind 'caption',
                fill_horizontal = 1,
                height_in_lines = 10,
                enabled = bind 'saveCaption',  -- Enable only if the checkbox is checked
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'saveAltText',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SaveAltText=Save alt text",
                width = share 'labelWidth',
            },
            f:edit_field {
                value = bind 'altText',
                fill_horizontal = 1,
                height_in_lines = 10,
                enabled = bind 'saveAltText',  -- Enable only if the checkbox is checked
            },
        },
        f:row {
            margin_vertical = 10,
            f:checkbox {
                value = bind 'skipFromHere'
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SkipFromHere=Save following without reviewing.",
            },
        },
    }

    local result = LrDialogs.presentModalDialog({
        title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/ReviewWindowTitle=Review results",
        -- otherVerb = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/discard=Discard",
        contents = dialogView,
    })

    local validatedKeywords = {}
    if propertyTable.saveKeywords then
        validatedKeywords = Util.rebuildTableFromKeywords(keywords, propertyTable.keywordsVal, propertyTable.keywordsSel)
    end

    return result, propertyTable.saveKeywords, validatedKeywords,
            propertyTable.saveTitle, propertyTable.title,
            propertyTable.saveCaption, propertyTable.caption,
            propertyTable.saveAltText, propertyTable.altText,
            propertyTable.skipFromHere
end

function AnalyzeImageProvider.showUsedTokensDialog(totalInputTokens, totalOutputTokens)
    if Defaults.pricing[prefs.ai] == nil then
        log:trace("No cost information for selected AI model, not showing usedTokenDialog.")
        return nil
    end

    if prefs.showCosts then
        local inputCostPerToken = 0
        if Defaults.pricing[prefs.ai].input ~= nil then
            inputCostPerToken = Defaults.pricing[prefs.ai].input
        else
            return nil
        end

        local outputCostPerToken = 0
        if Defaults.pricing[prefs.ai].output ~= nil then
            outputCostPerToken = Defaults.pricing[prefs.ai].output
        else
            return nil
        end

        local inputCosts = totalInputTokens * inputCostPerToken
        local outputCosts = totalOutputTokens * outputCostPerToken
        local totalCosts = inputCosts + outputCosts

        local f = LrView.osFactory()
        local share = LrView.share
        local dialog = {}
        dialog.title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/UsedTokenDialog/Title=Generation costs"
        dialog.resizable = false
        dialog.contents = f:column {
            f:row {
                size = "small",
                f:column {
                    f:group_box {
                        width = share 'groupBoxWidth',
                        title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/UsedTokenDialog/UsedTokens=Used Tokens",
                        f:spacer {
                            width = share 'spacerWidth',
                        },
                        f:static_text {
                            title = 'Input:',
                            font = "<system/bold>",
                        },
                        f:static_text {
                            title = tostring(totalInputTokens),
                            width = share 'valWidth',
                        },
                        f:static_text {
                            title = 'Output:',
                            font = "<system/bold>",
                        },
                        f:static_text {
                            title = tostring(totalOutputTokens),
                            width = share 'valWidth',
                        },
                    },
                },
                f:column {
                    size = "small",
                    f:group_box {
                        width = share 'groupBoxWidth',
                        title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/UsedTokenDialog/GeneratedCosts=Generated costs",
                        f:spacer {
                            width = share 'spacerWidth',
                        },
                        f:static_text {
                            title = 'Input:',
                            font = "<system/bold>",
                        },
                        f:static_text {
                            title = tostring(inputCosts) .. " USD",
                            width = share 'valWidth',
                        },
                        f:static_text {
                            title = 'Output:',
                            font = "<system/bold>",
                        },
                        f:static_text {
                            title = tostring(outputCosts) .. " USD",
                            width = share 'valWidth',
                        },
                    },
                },
            },
            f:row {
                f:spacer {
                    height = 20,
                },
            },
            f:row {
                font = "<system/bold>",
                f:static_text {
                    title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/UsedTokenDialog/TotalCosts=Total costs:",
                },
                f:static_text {
                    title = tostring(totalCosts) .. " USD",
                },
            },
        }


        LrDialogs.presentModalDialog(dialog)
    end
end


function AnalyzeImageProvider.showPhotoContextDialog(photo)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local propertyTable = {}
    propertyTable.skipFromHere = SkipPhotoContextDialog
    local photoContextFromCatalog = photo:getPropertyForPlugin(_PLUGIN, 'photoContext')
    if photoContextFromCatalog ~= nil then
        PhotoContextData = photoContextFromCatalog
    end
    propertyTable.photoContextData = PhotoContextData

    local tempDir = LrPathUtils.getStandardFilePath('temp')
    local exportSettings = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = tempDir,
        LR_export_useSubfolder = false,
        LR_format = 'JPEG',
        LR_jpeg_quality = 60,
        LR_minimizeEmbeddedMetadata = true,
        LR_outputSharpeningOn = false,
        LR_size_doConstrain = true,
        LR_size_maxHeight = 460,
        LR_size_resizeType = 'longEdge',
        LR_size_units = 'pixels',
        LR_collisionHandling = 'rename',
        LR_includeVideoFiles = false,
        LR_removeLocationMetadata = true,
        LR_embeddedMetadataOption = "copyrightOnly",
    }

    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = exportSettings
    })

    local photoPath = ""
    local renderSuccess = false
    for _, rendition in exportSession:renditions() do
        local success, path = rendition:waitForRender()
        if success then
            photoPath = path
            renderSuccess = success
        end
    end

    local dialogView = f:column {
        bind_to_object = propertyTable,
        f:row {
            f:static_text {
                title = photo:getFormattedMetadata('fileName'),
            },
        },
        f:row {
            f:spacer {
                height = 10,
            },
        },
        f:row {
            alignment = "center",
            f:picture {
                alignment = "center",
                value = photoPath,
                frame_width = 0,
            },
        },
        f:row {
            f:spacer {
                height = 10,
            },
        },
        f:row {
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/PhotoContextDialogData=Photo Context",
            },
        },
        f:row {
            f:spacer {
                height = 10,
            },
        },
        f:row {
            f:edit_field {
                value = bind 'photoContextData',
                width_in_chars = 40,
                height_in_lines = 10,
            },
        },
        f:row {
            f:spacer {
                height = 10,
            },
        },
        f:row {
            f:checkbox {
                value = bind 'skipFromHere'
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/SkipPreflightFromHere=Use for all following pictures.",
            },
        },
    }

    local result = LrDialogs.presentModalDialog({
        title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/PhotoContextDialogData=Photo Context",
        contents = dialogView,
    })

    if renderSuccess then LrFileUtils.delete(photoPath) end

    SkipPhotoContextDialog = propertyTable.skipFromHere

    if result == "ok" then
        PhotoContextData = propertyTable.photoContextData
        return true
    elseif result == "cancel" then
        PhotoContextData = ""
        return false
    end
end

function AnalyzeImageProvider.showPreflightDialog(ctx)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share

    local propertyTable = LrBinding.makePropertyTable(ctx)

    propertyTable.task = prefs.task
    propertyTable.systemInstruction = prefs.systemInstruction

    propertyTable.generateTitle = prefs.generateTitle
    propertyTable.generateCaption = prefs.generateCaption
    propertyTable.generateKeywords = prefs.generateKeywords
    propertyTable.generateAltText = prefs.generateAltText

    propertyTable.enableValidation = prefs.enableValidation

    propertyTable.ai = prefs.ai
    propertyTable.showCosts = prefs.showCosts
    propertyTable.showPhotoContextDialog = prefs.showPhotoContextDialog

    propertyTable.submitGPS = prefs.submitGPS
    propertyTable.submitKeywords = prefs.submitKeywords
    propertyTable.submitFolderName = prefs.submitFolderName

    propertyTable.temperature = prefs.temperature

    propertyTable.generateLanguage = prefs.generateLanguage
    propertyTable.replaceSS = prefs.replaceSS

    propertyTable.promptTitles = {}
    for title, prompt in pairs(prefs.prompts) do
        table.insert(propertyTable.promptTitles, { title = title, value = title })
    end
    
    propertyTable.prompts = prefs.prompts

    propertyTable.prompt = prefs.prompt

    propertyTable.selectedPrompt = prefs.prompts[prefs.prompt]

    propertyTable:addObserver('prompt', function(properties, key, newValue)
        properties.selectedPrompt = properties.prompts[newValue]
    end)

    propertyTable:addObserver('selectedPrompt', function(properties, key, newValue)
        properties.prompts[properties.prompt] = newValue
    end)

    local dialogView = f:column {
        spacing = 10,
        bind_to_object = propertyTable,
        f:row {
            f:static_text {
                width = share 'labelWidth',
                title = LOC "$$$/lrc-ai-assistant/AIMetadataProvider/aiModel=AI model",
                alignment = "right",
            },
            f:popup_menu {
                value = bind 'ai',
                items = Defaults.getAvailableAiModels(),
            },
        },
        f:row {
            f:static_text {
                width = share 'labelWidth',
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/aiBehavior=AI behavior",
                alignment = "right",
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/beCoherent=Be coherent"
            },
            f:slider {
                value = bind 'temperature',
                min = 0.0,
                max = 0.5,
                immediate = true,
            },
            f:static_text {
                title = bind 'temperature',
                width = 30,
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/beCreative=Be creative",
                alignment = "left",
            },
        },
        f:row {
            f:static_text {
                width = share 'labelWidth',
                alignment = "right",
                title = "Prompt",
            },
            f:popup_menu {
                items = bind 'promptTitles',
                value = bind 'prompt',
            },
        },
        f:row {
            f:static_text {
                width = share 'labelWidth',
                alignment = "right",
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/editPrompt=Edit prompt",
            },
            f:edit_field {
                value = bind 'selectedPrompt',
                width_in_chars = 50,
                height_in_lines = 10,
                -- enabled = false,
            },
        },
        f:row {
            f:static_text {
                width = share 'labelWidth',
                alignment = "right",
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/generateLanguage=Result language",
            },
            f:combo_box {
                value = bind 'generateLanguage',
                items = Defaults.generateLanguages,
            },
            f:checkbox {
                value = bind 'replaceSS',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/replaceSS=Replace ß with ss",
                width = share 'labelWidth',
            },
        },
        f:row {
            f:static_text {
                width = share 'labelWidth',
                alignment = "right",
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/submitMetadata=Submit existing metadata:",
            },
            f:checkbox {
                value = bind 'submitKeywords',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/keywords=Keywords"
            },
            f:checkbox {
                value = bind 'submitGPS',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = "GPS"
            },
            f:checkbox {
                value = bind 'submitFolderName',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/folderNames=Folder names",
            },
        },
        f:row {
            f:static_text {
                width = share 'labelWidth',
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/UsedTokenDialog/GeneratedCosts=Generated costs",
                alignment = "right",
            },
            f:checkbox {
                value = bind 'showCosts',
                width = share 'checkboxWidth'
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/showCosts=Show costs (without any warranty!!!)",
            },
        },
        f:row {
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/generate=Generate the following",
                alignment = 'right',
                width = share 'labelWidth',
            },
            f:checkbox {
                value = bind 'generateCaption',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/caption=Caption",
            },
            f:checkbox {
                value = bind 'generateAltText',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/alttext=Alt Text",
            },
            f:checkbox {
                value = bind 'generateTitle',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/title=Title",
            },
            f:checkbox {
                value = bind 'generateKeywords',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/keywords=Keywords",
            },
        },
        f:row {
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/validateBeforeSaving=Validate before saving",
                width = share 'labelWidth',
            },
            f:checkbox {
                value = bind 'enableValidation',
                width = share 'checkboxWidth',
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/validation=Enable validation",
            },
        },
        f:row {
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/PhotoContextDialogData=Photo Context",
                width = share 'labelWidth',
                alignment = "right",
            },
            f:checkbox {
                value = bind 'showPhotoContextDialog',
                width = share 'checkboxWidth'
            },
            f:static_text {
                title = LOC "$$$/lrc-ai-assistant/PluginInfoDialogSections/showPhotoContextDialog=Show Photo Context dialog",
                width = share 'labelWidth',
            },
        },
    }

    local result = LrDialogs.presentModalDialog({
        title = LOC "$$$/lrc-ai-assistant/AnalyzeImageTask/PreflightDialogTitle=Preflight Dialog",
        contents = dialogView,
    })

    if result == "ok" then
        prefs.task = propertyTable.task
        prefs.systemInstruction = propertyTable.systemInstruction
    
        prefs.generateTitle = propertyTable.generateTitle
        prefs.generateCaption = propertyTable.generateCaption
        prefs.generateKeywords = propertyTable.generateKeywords
        prefs.generateAltText = propertyTable.generateAltText
    
        prefs.enableValidation = propertyTable.enableValidation
    
        prefs.ai = propertyTable.ai
        prefs.showCosts = propertyTable.showCosts
        prefs.showPhotoContextDialog = propertyTable.showPhotoContextDialog

        prefs.submitGPS = propertyTable.submitGPS
        prefs.submitKeywords = propertyTable.submitKeywords
        prefs.submitFolderName = propertyTable.submitFolderName

        prefs.temperature = propertyTable.temperature

        prefs.generateLanguage = propertyTable.generateLanguage
        prefs.replaceSS = propertyTable.replaceSS

        prefs.prompts = propertyTable.prompts
        prefs.prompt = propertyTable.prompt
        
        return true
    elseif result == "cancel" then
        return false
    end
end
