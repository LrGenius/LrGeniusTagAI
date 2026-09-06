---
name: lrgeniustagai-dev
description: Develop and maintain LrGeniusTagAI, a Lightroom Classic plugin (Lua, Lightroom SDK 11+) that sends photos to AI vision models (Gemini, ChatGPT, Ollama, LM Studio) to generate titles, captions, alt text and keywords. Use when adding an AI provider or model, adding a plugin preference or dialog field, changing prompts or the JSON response schema, adding translations, fixing Lightroom SDK issues, or preparing a release.
---

# LrGeniusTagAI development

A Lightroom Classic plugin written in Lua against the Lightroom Classic SDK. All
source lives in `LrGeniusTagAI.lrdevplugin/`. There is no build step, no
package manager, and no test runner: the folder is loaded directly by Lightroom's
Plug-in Manager and zipped as-is for releases.

## Runtime constraints (read first)

- **Lua 5.1 semantics** inside Lightroom. No `goto`, no integer division `//`,
  no `table.unpack` (use `unpack`), no bit operators. `string.gsub` patterns are
  Lua patterns, not regex.
- **Only the Lightroom SDK is available.** No LuaSocket, no OS libs, no `os.execute`.
  HTTP goes through `LrHttp`, files through `LrFileUtils`/`LrPathUtils`, JSON
  through the bundled `JSON.lua` (`JSON:encode` / `JSON:decode`).
- **Blocking work must run in an async task.** Menu entry files (`AnalyzeImageTask.lua`,
  `KeywordConfigTask.lua`) wrap everything in
  `LrTasks.startAsyncTask(function() LrFunctionContext.callWithContext(...) end)`.
  `LrHttp`, `LrExportSession`, `LrTasks.sleep`, and modal dialogs need this context.
- **Catalog writes need a write-access block.** Public metadata (title, caption,
  alt text, keywords) uses `catalog:withWriteAccessDo(name, fn)`. Plugin-private
  fields (`aiModel`, `aiLastRun`, `photoContext`) use
  `catalog:withPrivateWriteAccessDo(fn)` + `photo:setPropertyForPlugin(_PLUGIN, id, value)`.
  Never nest these blocks.
- **The plugin cannot be executed outside Lightroom.** Verify changes by
  reloading the plugin in *File → Plug-in Manager* (select the plugin, click
  *Reload Plug-in*) and reading the log file (see Debugging).

## Architecture

Load order and globals are defined in `Init.lua`. It imports every `Lr*`
namespace into `_G`, requires every module, creates the global `prefs`
(`LrPrefs.prefsForPlugin()`) and `log` (`LrLogger 'LrGeniusTagAI'`), and
fills missing preferences with values from `Defaults.lua`. Because of this,
**modules are plain global tables**, not `require`-returned locals:

```lua
MyModule = {}
MyModule.__index = MyModule
function MyModule:new() local o = setmetatable({}, MyModule) ... return o end
```

| File | Role |
|------|------|
| `Info.lua` | Plugin manifest: version (`Info.MAJOR/MINOR/REVISION`), SDK version, menu items, metadata provider |
| `Init.lua` | Global imports, module loading, preference defaults, background update check |
| `Defaults.lua` | Model list, API base URLs, pricing tables, prompt defaults, keyword categories, top-level keyword names |
| `AiModelAPI.lua` | Facade: picks the provider from the `prefs.ai` prefix and builds prompt/system instruction |
| `GeminiAPI.lua`, `ChatGptAPI.lua`, `OllamaAPI.lua`, `LmStudioAPI.lua` | One provider each; same public contract (below) |
| `ResponseStructure.lua` | Builds the provider-specific JSON schema for structured output |
| `AnalyzeImageTask.lua` | Menu entry point: export temp JPEG → call AI → validate → write metadata |
| `AnalyzeImageProvider.lua` | Dialogs for the task: preflight, photo context, validation, token/cost summary; recursive keyword writer |
| `PluginInfo.lua` + `PluginInfoDialogSections.lua` | Plug-in Manager settings UI (bindings to `prefs`) |
| `PromptConfigProvider.lua`, `KeywordConfigProvider.lua` | Sub-dialogs for prompt presets and keyword categories |
| `AIMetadataProvider.lua` | Custom per-photo metadata fields (`aiLastRun`, `aiModel`, `photoContext`) |
| `ErrorHandler.lua` | `ErrorHandler.handleError(msg, details)`: logs and shows a modal with a "Generate report" button |
| `UpdateCheck.lua` | Compares `Info` version to the latest GitHub release tag |
| `Util.lua` | Helpers: base64 photo encoding, table dump, log-file paths, keyword table flatten/rebuild |
| `JSON.lua`, `inspect.lua` | Vendored third-party libs, do not edit |
| `TranslatedStrings_*.txt` | Localization tables (en, de, fr) |

### Analysis flow

1. `AnalyzeImageTask.lua` gets `catalog:getTargetPhotos()`, shows the preflight
   dialog, opens an `LrProgressScope`.
2. For each photo: export a temporary JPEG via `LrExportSession` using
   `prefs.exportSize` (long edge px) and `prefs.exportQuality`.
3. Collect metadata (`gps`, `keywordTagsForExport`, folder names, optional
   free-text context from the photo-context dialog).
4. `AiModelAPI:new():analyzeImage(path, metadata)` dispatches to the provider.
5. Provider returns `success, resultTable, inputTokens, outputTokens`.
   `resultTable` keys are the **localized** field names
   (`LOC "$$$/lrc-ai-assistant/Defaults/ResponseStructure/ImageTitle=Image title"` etc.)
   plus `keywords` (flat array or nested category table).
6. Optional validation dialog, then metadata is written, keywords are created
   recursively under an optional per-provider top keyword, temp file deleted,
   `aiModel`/`aiLastRun` saved.
7. Per-photo failure returns a cause string: `"fatal"` stops the batch,
   `"canceled"` stops silently, `"non-fatal"` continues and is listed at the end.

### Provider contract

Every provider class must implement:

```lua
Provider:new()                      -- returns nil (after ErrorHandler) if not configured
Provider:analyzeImage(filePath, metadata)
  -- returns: success(boolean), result(table or error string), inputTokens, outputTokens
  -- must call AiModelAPI.generatePromptFromConfiguration() for the task text
  -- must call AiModelAPI.addKeywordHierarchyToSystemInstruction() for the system prompt
  -- must append GPS / keywords / context / folder names exactly like GeminiAPI:analyzeImage
  -- must strip ```json fences (Defaults.geminiKeywordsGarbageAtStart/End) and apply prefs.replaceSS
Provider:doRequest(filePath, task, systemInstruction, generationConfig)
  -- returns: success, rawText, inputTokens, outputTokens
```

Local providers (Ollama, LM Studio) additionally expose
`Provider.getLocalVisionModels()` returning `{ {title=..., value='<prefix>-<model>'} }`
which `Defaults.getAvailableAiModels()` appends to the popup list.

Provider selection is **prefix-based on `prefs.ai`** in three places that must
stay in sync: `AiModelAPI:new()`, `ResponseStructure:new()`, and the model
`value` strings in `Defaults.lua` (`gemini-*`, `gpt-*`, `ollama-*`, `lmstudio-*`).

## Common tasks

### Add a cloud model to an existing provider
1. Add `{ title = "...", value = "<model-id>" }` to `aiModels` in `Defaults.lua`.
2. Add `Defaults.baseUrls['<model-id>']`.
3. Add `Defaults.pricing['<model-id>'].input/.output` as USD per token
   (`price_per_million / 1000000`). Missing pricing breaks the cost dialog.
4. If the model needs different request params (e.g. gpt-5 forces
   `temperature = 1` and `reasoning_effort`), branch on the id prefix inside
   the provider's `doRequest`.

### Add a new provider
1. Create `NewProviderAPI.lua` implementing the contract above; mirror
   `GeminiAPI.lua` (cloud, API key) or `OllamaAPI.lua` (local, model discovery).
2. Add `require "NewProviderAPI"` to `Init.lua` next to the other provider
   requires (after `Defaults`, before `ResponseStructure`).
3. Add a prefix branch in `AiModelAPI:new()` and `ResponseStructure:new()`;
   decide whether the schema uses Gemini-style (`OBJECT`/`STRING` upper case,
   `response_schema`), OpenAI-style (`json_schema` + `strict` + `required` +
   `additionalProperties=false`), or Ollama-style (`format` = bare schema).
4. Add `Defaults.<name>TopKeyword` and the preference defaults (API key or
   base URL) in `Init.lua`.
5. Add UI fields in `PluginInfoDialogSections.sectionsForTopOfDialog` bound to
   the new prefs, and a row in the README provider table.

### Add a preference
1. Default it in `Init.lua` (`if prefs.x == nil then prefs.x = ... end`).
2. Bind it in `PluginInfoDialogSections.lua` (`bind 'x'`; `startDialog` copies
   `prefs` into the property table, `endDialog` copies back).
3. If it affects the request, read it in the providers or `AiModelAPI`.
4. If it should appear in the perf CSV, extend the header and the write line in
   `AnalyzeImageTask.lua` together.

### Change generated fields or the response schema
- Field names are localized keys; the same `LOC` string is used to **build** the
  schema (`ResponseStructure.lua`) and to **read** the result
  (`AnalyzeImageTask.lua`). Change both, and add the key to every
  `TranslatedStrings_*.txt` (see the localization rule below).
- Keyword categories come from `prefs.keywordCategories` falling back to
  `Defaults.defaultKeywordCategories`. Nested tables produce nested schema objects.

### Add or change UI strings / translations

**Rule: whenever you add, change, or remove a user-visible text, update every
existing `TranslatedStrings_*.txt` file in the same change. Do this
automatically, without being asked.** Discover the files with
`ls LrGeniusTagAI.lrdevplugin/TranslatedStrings_*.txt` (currently `en`, `de`,
`fr`) so new languages are covered too. A `LOC` key that is missing from a
translation file silently falls back to the English default, so omissions are
not caught by Lightroom.

- Every user-visible string uses `LOC "$$$/lrc-ai-assistant/<File>/<key>=English default"`.
  The `$$$/lrc-ai-assistant/` prefix is historical; keep it, do not rename to the plugin name.
- Placeholders are `^1`, `^2`, passed as extra args: `LOC("$$$/.../caption=Photo ^1/^2", a, b)`.
- File format: one quoted line per key,
  `"$$$/lrc-ai-assistant/<File>/<key>=Übersetzung"`. Keep each file sorted by key.
  `TranslatedStrings_en.txt` mirrors the English defaults exactly.
- Provide real translations for `de` and `fr`. Keep German wording consistent
  with existing entries (e.g. "Zusatzmodul-Manager" for Plug-in Manager). Never
  leave the English text as a placeholder in a non-English file.
- When you **rename or delete** a key, remove or rename it in all files so no
  orphaned entries remain.
- When you **edit an English default** inside a `LOC` call, also review the
  translated wording for that key; the key stays the same, only the text changes.
- Before finishing, verify completeness:
  ```bash
  cd LrGeniusTagAI.lrdevplugin
  grep -oh '\$\$\$/lrc-ai-assistant/[A-Za-z0-9_/]*' *.lua | sort -u > /tmp/keys.txt
  for f in TranslatedStrings_*.txt; do
    echo "== $f"
    grep -oh '\$\$\$/lrc-ai-assistant/[A-Za-z0-9_/]*' "$f" | sort -u | comm -23 /tmp/keys.txt -
  done
  ```
  Any key printed under a file name is missing from that file.
- Translations are only picked up after a plugin reload.

### Error handling and logging
- User-facing failures: `ErrorHandler.handleError('Short title', 'Details ' .. Util.dumpTable(headers))`.
  It logs and shows a modal; do not also call `LrDialogs.showError` for the same error.
- Provider `doRequest` should return `false, '<reason>', 0, 0` after handling the
  error; `analyzeImage` propagates. The sentinel `'RATE_LIMIT_EXHAUSTED'` is
  treated as fatal by the task loop.
- Use `log:trace` for flow details and `log:error` for failures. Avoid tracing
  full base64 bodies or model lists in a loop (bloats the log).
- `LrHttp.post(url, body, headers, 'POST', 720)`: the last arg is the timeout in
  seconds; keep it large for slow local models.

## Debugging

- Log file (always enabled):
  - macOS, Lightroom 14+: `~/Library/Logs/Adobe/Lightroom/LrClassicLogs/LrGeniusTagAI.log`
  - Windows, Lightroom 14+: `%LOCALAPPDATA%\Adobe\Lightroom\Logs\LrClassicLogs\LrGeniusTagAI.log`
  - Older versions: `~/Documents/LrClassicLogs/LrGeniusTagAI.log`
- The error dialog's *Generate report* button copies logs to the Desktop
  (`Util.copyLogfilesToDesktop`).
- Enable *performance logging* in the settings to get `perflog.csv` on the Desktop
  (semicolon separated; one row per photo).
- Local providers: verify the service first with
  `curl http://localhost:11434/api/tags` (Ollama) or
  `curl http://localhost:1234/api/v0/models` (LM Studio); only models reporting
  the `vision` capability are listed.
- Lua diagnostics globals for the editor (`LOC`, `_PLUGIN`, `MAC_ENV`) are
  declared in `.vscode/settings.json`; add new Lightroom globals there rather
  than suppressing warnings inline.

## Release

1. Bump `Info.MAJOR` / `Info.MINOR` / `Info.REVISION` in `Info.lua`.
   `UpdateCheck` compares `"v" .. major.minor.revision` against the latest
   GitHub release tag, so the tag **must** be `vX.Y.Z` matching `Info.lua`.
2. Commit, then run the *Create Release* workflow (`.github/workflows/release.yml`,
   `workflow_dispatch`) with the tag as input. It zips
   `LrGeniusTagAI.lrdevplugin/` and attaches `LrGeniusTagAI.lrdevplugin.zip`
   with auto-generated release notes.
3. The upstream distribution repository is `LrGenius/LrGeniusTagAI`; this repo
   is a development fork. Update checks and README download links point upstream.

## Gotchas

- `prefs.ai` is the single source of truth for provider *and* model. Never
  store the provider separately.
- Gemini returns fenced JSON despite `response_mime_type`; always strip fences.
- ChatGPT strict schemas require every property in `required` and
  `additionalProperties = false` at every nesting level.
- gpt-5 models reject `temperature` other than 1; the plugin forces it.
- Keyword results may be a flat array or a nested category table depending on
  `prefs.useKeywordHierarchy`; `AnalyzeImageProvider.addKeywordRecursively`
  and `Util.extractAllKeywords` handle both. Keep new code table-shape agnostic.
- Dialog property tables are copies of `prefs`; changes take effect only after
  `endDialog` copies them back, so a task started while the dialog is open uses
  old values.
- Do not edit `JSON.lua` or `inspect.lua`; they are vendored.
- Every new `LOC` string must land in all `TranslatedStrings_*.txt` files in the
  same change. Treat a missing translation as an incomplete task.
