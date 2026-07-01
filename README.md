# LrGeniusTagAI

A Lightroom Classic plugin that uses AI vision models to automatically generate
**titles, captions, alt text, and keywords** for your photos — directly inside
Lightroom, on the Library grid or during export.

## Features

- **Batch analysis** — select any number of photos in the Library grid (or run it
  as an export action) and let an AI model describe them all in one pass.
- **Multiple AI providers** — choose per-install which model does the work:
  - Google Gemini (Flash Lite, Flash, Pro) via the Gemini API
  - OpenAI ChatGPT (Nano, Mini, standard) via the OpenAI API
  - [Ollama](https://ollama.com) — run a local vision model, no cloud/API key needed
  - [LM Studio](https://lmstudio.ai) — run a local vision model, no cloud/API key needed
- **Configurable output** — independently enable/disable generation of title,
  caption, alt text (for accessibility), and keywords.
- **Keyword hierarchy** — optionally sort generated keywords into categories
  (Activities, Buildings, Location, Objects, People, Moods, Sceneries, Animals,
  Vehicles, ...) and/or nest them under a top-level keyword per provider
  (e.g. "Google Gemini").
- **Custom prompts** — edit the system prompt/instructions and save multiple
  named prompt presets to switch between.
- **Multi-language output** — generate results in English, German, French,
  Spanish, or Italian.
- **Context-aware** — optionally submit existing GPS coordinates, keywords, or
  folder names to the AI as extra context, or add free-text photo context
  per-batch via a dialog before analysis.
- **Review before save** — optional validation dialog lets you approve, edit,
  or reject AI-generated results before they're written to the catalog.
- **Preflight & cost estimate** — an optional preflight dialog shows what will
  be sent before a batch runs, and a running token/cost estimate is shown
  afterwards (Gemini/ChatGPT pricing tables included; no warranty on accuracy).
- **Debug & performance logging** — built-in log file plus optional per-photo
  CSV performance logging (model, duration, settings) for tuning your setup.
- **Update checks** — optional periodic check for new plugin releases, or check
  manually from the plugin settings.

## How it works

1. The plugin exports a temporary, resized JPEG copy of each selected photo
   (configurable long-edge size and quality — smaller/lower-quality exports
   cost less and process faster).
2. The image (plus any opted-in metadata like GPS/keywords/folder name) is
   sent to the configured AI provider's vision API along with your prompt.
3. The AI's structured response is parsed into title/caption/alt text/keywords.
4. After optional review, the results are written back to the photo's
   Lightroom metadata, and the temp export file is deleted.

## Requirements

- Adobe Lightroom Classic (SDK 11.0+, i.e. Lightroom Classic 11 / 2022 or later)
- One of:
  - a Google AI Studio API key (for Gemini models)
  - an OpenAI API key (for ChatGPT models)
  - a local [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai)
    install running a vision-capable model

## Installation

1. Download `LrGeniusTagAI.lrdevplugin` from the
   [Releases](https://github.com/LrGenius/LrGeniusTagAI/releases) page (or clone this repository).
2. In Lightroom Classic, go to **File → Plug-in Manager**, click **Add**, and
   select the `LrGeniusTagAI.lrdevplugin` folder.
3. Open the plugin's settings (still in the Plug-in Manager) to configure your
   AI provider and API key(s) — see [Configuration](#configuration) below.

## Configuration

All settings live under **File → Plug-in Manager → LrGeniusTagAI**:

- **AI model** — pick the provider/model to use; local Ollama/LM Studio models
  are auto-discovered if those services are running.
- **API keys** — enter your Gemini and/or ChatGPT API key, or set the base URL
  for a local Ollama/LM Studio server (defaults to `localhost:11434` /
  `localhost:1234`).
- **Prompts** — edit the default system prompt or add/delete named presets.
- **Result language** — choose the output language.
- **Generate** — toggle which fields to generate (caption, alt text, title,
  keywords) and whether to review results before saving.
- **Submit existing metadata** — opt in to sending GPS, existing keywords, or
  folder names as extra context to the AI.
- **Keyword hierarchy** — enable/disable categorized keywords and edit the
  category list; optionally nest keywords under a top-level, per-provider
  keyword.
- **Export settings** — long-edge size (px) and JPEG quality used for the
  temporary image sent to the AI.

## Usage

1. Select one or more photos in the Library grid.
2. Run **Library → Plug-in Extras → Analyze photos with AI** (also available
   as an export action).
3. Review the preflight dialog (if enabled), wait for the batch to process,
   and optionally confirm/edit each result in the validation dialog.
4. Generated title/caption/alt text/keywords are written to the catalog.

## Supported AI providers

| Provider   | Models                                              | Requires        |
|------------|------------------------------------------------------|-----------------|
| Gemini     | 2.5 Flash-Lite/Flash/Pro, 3.1/3.5 Flash-Lite/Flash/Pro| Google API key  |
| ChatGPT    | 5.4 Nano/Mini, 5.4, 5.5                               | OpenAI API key  |
| Ollama     | any locally installed vision model                    | Ollama running locally |
| LM Studio  | any locally installed vision model                    | LM Studio running locally |

Cloud provider usage is billed by the provider according to your own API plan;
local Ollama/LM Studio models are free but require sufficient local hardware.

## Links

- Website & docs: https://lrgenius.com
- Configuration docs: https://lrgenius.com/configuration
- Ollama setup guide: https://lrgenius.com/help/docs/help-ollama-setup/
