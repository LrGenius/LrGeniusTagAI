Info = {}

Info.MAJOR = 1
Info.MINOR = 8
Info.REVISION = 0
Info.VERSION = { major = Info.MAJOR, minor = Info.MINOR, revision = Info.REVISION, build = 1, }


return {

	LrSdkVersion = 11.0,
	LrSdkMinimumVersion = 11.0,
	LrToolkitIdentifier = 'LrGeniusTagAI',
	LrPluginName = "LrGeniusTagAI",
	LrInitPlugin = "Init.lua",
	LrPluginInfoProvider = 'PluginInfo.lua',
	LrPluginInfoURL = 'https://lrgenius.com',

	VERSION = Info.VERSION,

	LrMetadataProvider = "AIMetadataProvider.lua",


	LrLibraryMenuItems = {
		{
			title = LOC "$$$/lrc-ai-assistant/Info/Title=Analyze photos with AI",
			file = "AnalyzeImageTask.lua",
		},
	},

	LrExportMenuItems = {
		{
			title = LOC "$$$/lrc-ai-assistant/Info/Title=Analyze photos with AI",
			file = "AnalyzeImageTask.lua",
		},
	},
}
