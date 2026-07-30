import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    static var systemDefault: AppLanguage {
        Locale.current.language.languageCode?.identifier == "zh" ? .chinese : .english
    }
}

enum L10n {
    static var currentLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "")
            ?? AppLanguage.systemDefault
    }

    static func text(_ english: String, _ chinese: String) -> String {
        currentLanguage == .chinese ? chinese : english
    }

    static func text(
        _ english: String,
        _ chinese: String,
        language: AppLanguage
    ) -> String {
        language == .chinese ? chinese : english
    }

    static var general: String { text("General", "通用") }
    static var about: String { text("About", "关于") }
    static var activation: String { text("Activation", "快捷操作") }
    static var showPesty: String { text("Show Pesty", "显示 Pesty") }
    static var searchClipboard: String { text("Search", "搜索") }
    static var historyLimit: String { text("History limit", "历史记录上限") }
    static var unlimited: String { text("Unlimited", "无限") }
    static var historyLimitDelayDescription: String {
        text(
            "If a lower limit would remove existing items, deletion waits 10 seconds so you can undo it.",
            "如果降低上限会删除已有记录，Pesty 将等待 10 秒再清理，期间可以调高或切回无限。"
        )
    }
    static var storageUsed: String { text("Current storage used", "当前占用空间") }
    static func items(_ count: Int) -> String {
        currentLanguage == .chinese ? "\(count) 项" : "\(count) items"
    }
    static var behavior: String { text("Behavior", "行为") }
    static var pasteDirectly: String {
        text("Paste directly into the active app", "直接粘贴到当前应用")
    }
    static var ignorePasswords: String {
        text("Ignore passwords (concealed clips)", "忽略密码（隐藏的剪贴板内容）")
    }
    static var playSound: String { text("Play sound on paste", "粘贴时播放声音") }
    static var launchAtLogin: String { text("Launch at login", "登录时启动") }
    static var showMenuBarIcon: String { text("Show menu bar icon", "显示菜单栏图标") }
    static var showMenuBarIconDescription: String {
        text("When hidden, open Pesty again from Applications to show Settings.",
             "隐藏后，从“应用程序”中再次打开 Pesty 即可显示设置。")
    }
    static var barHeight: String { text("Bar height", "面板高度") }
    static var px: String { text("px", "像素") }
    static var selectClip: String {
        text("Select a clip to copy it, then press ⌘V to paste it into your app.",
             "选择一条剪贴内容进行复制，然后按 ⌘V 粘贴到当前应用。")
    }
    static var sync: String { text("Sync", "同步") }
    static var syncClipboard: String {
        text("Sync clipboard via iCloud Drive", "通过 iCloud Drive 同步剪贴板")
    }
    static var syncAvailable: String {
        text("Keeps your history, pinboards, and history limit in sync across your Macs through iCloud Drive.",
             "通过 iCloud Drive 在你的 Mac 之间同步历史记录、Pinboard 和历史记录上限。")
    }
    static var syncUnavailable: String {
        text("Sign in to iCloud and enable iCloud Drive to use sync.",
             "请登录 iCloud 并启用 iCloud Drive 以使用同步功能。")
    }
    static var permissions: String { text("Permissions", "权限") }
    static var accessibility: String { text("Accessibility", "辅助功能") }
    static var accessibilityGranted: String {
        text("Granted — direct paste is enabled.", "已授权 — 直接粘贴已启用。")
    }
    static var accessibilityWaiting: String {
        text("Waiting… toggle Pesty on in System Settings.",
             "等待中……请在系统设置中打开 Pesty。")
    }
    static var accessibilityRequired: String {
        text("Required to paste directly into other apps.",
             "直接粘贴到其他应用需要此权限。")
    }
    static var accessibilitySetupTitle: String {
        text("Finish Setting Up Pesty", "完成 Pesty 设置")
    }
    static var accessibilityFirstInstallDescription: String {
        text(
            "Pesty needs Accessibility access to paste a selected clip directly into another app. macOS requires you to approve this once, then restart Pesty.",
            "Pesty 需要辅助功能权限，才能把选中的内容直接粘贴到其他应用。macOS 要求你先完成一次授权，然后重启 Pesty。"
        )
    }
    static var accessibilityUpdateDescription: String {
        text(
            "This update replaces the Pesty app, so macOS requires Accessibility access to be approved again. Your clipboard history and settings are unchanged.",
            "本次更新替换了 Pesty 应用，因此 macOS 要求重新授权辅助功能。你的剪贴板历史和设置不会受到影响。"
        )
    }
    static var accessibilityStepOpen: String {
        text(
            "Open Privacy & Security > Accessibility.",
            "打开“隐私与安全性”>“辅助功能”。"
        )
    }
    static var accessibilityStepEnable: String {
        text(
            "Turn on Pesty in the app list.",
            "在应用列表中打开 Pesty。"
        )
    }
    static var accessibilityStepRestart: String {
        text(
            "Return here and click Restart Pesty.",
            "返回这里并点击“重启 Pesty”。"
        )
    }
    static var openAccessibilitySettings: String {
        text("Open Accessibility Settings", "打开辅助功能设置")
    }
    static var openAccessibilitySettingsAgain: String {
        text("Open System Settings Again", "再次打开系统设置")
    }
    static func accessibilityGuideListPrompt(
        language: AppLanguage
    ) -> String {
        text(
            "Find Pesty.app in this list, then turn on the switch on the right.",
            "在列表中找到 Pesty.app，然后打开右侧开关完成授权。",
            language: language
        )
    }
    static var accessibilityReadyToRestart: String {
        text(
            "Access granted. Restart Pesty to finish.",
            "授权成功。重启 Pesty 即可完成。"
        )
    }
    static var repairAccessibility: String {
        text("Repair Access", "修复权限")
    }
    static var accessibilityRepairing: String {
        text("Removing the old authorization…", "正在移除旧授权……")
    }
    static func accessibilityRepairFailed(_ detail: String) -> String {
        text("Couldn’t reset the old authorization: \(detail)",
             "无法重置旧授权：\(detail)")
    }
    static var restartPesty: String { text("Restart Pesty", "重启 Pesty") }
    static var data: String { text("Data", "数据") }
    static var clearClipboardHistory: String {
        text("Clear Clipboard History", "清除剪贴板历史记录")
    }
    static var clearHistoryConfirmationTitle: String {
        text(
            "Clear all clipboard history?",
            "确定清除全部剪贴板历史记录吗？"
        )
    }
    static var clearHistoryConfirmationMessage: String {
        text(
            "This permanently deletes all clipboard history and its stored images. This action cannot be undone. Pinboards will not be deleted.",
            "这会永久删除全部剪贴板历史记录及其图片，且无法撤销。Pinboard 中的内容不会被删除。"
        )
    }
    static var languageLabel: String { text("Language", "语言") }
    static var languageDescription: String {
        text("Choose the language used by Pesty.", "选择 Pesty 使用的语言。")
    }
    static var settingsWindowTitle: String { text("Pesty Settings", "Pesty 设置") }
    static var translation: String { text("Translation", "翻译") }
    static var translationAndExplanation: String {
        text("Translate & Explain", "翻译&解释")
    }
    static var translate: String { text("Translate", "翻译") }
    static var automatic: String { text("Automatic", "自动") }
    static var english: String { text("English", "英语") }
    static var simplifiedChinese: String { text("Chinese (Simplified)", "中文（简体）") }
    static var japanese: String { text("Japanese", "日语") }
    static var korean: String { text("Korean", "韩语") }
    static var french: String { text("French", "法语") }
    static var german: String { text("German", "德语") }
    static var spanish: String { text("Spanish", "西班牙语") }
    static var sourceLanguage: String { text("Source language", "原文语言") }
    static var targetLanguage: String { text("Target language", "目标语言") }
    static var swapTranslationLanguages: String {
        text("Swap languages", "交换语言")
    }
    static var swapTranslationLanguagesShortcut: String {
        text("Swap source and target languages (T)", "交换原文和目标语言（T）")
    }
    static var translationService: String { text("Translation service", "翻译服务") }
    static var translationSettings: String { text("Translation Settings…", "翻译设置…") }
    static var openTranslationSettings: String { text("Open Translation Settings", "打开翻译设置") }
    static var closeTranslation: String { text("Close translation", "关闭翻译") }
    static var moreTranslationOptions: String { text("More translation options", "更多翻译选项") }
    static var translating: String { text("Translating…", "正在翻译…") }
    static var copyTranslation: String { text("Copy translation", "复制译文") }
    static var retryTranslation: String { text("Retry", "重试") }
    static var translationFailed: String { text("Translation failed. Please try again.", "翻译失败，请重试。") }
    static var noTranslatableText: String {
        text("Select a text clip to translate.", "请选择一条文本剪贴内容进行翻译。")
    }
    static var selectTextToTranslate: String {
        text(
            "Select some text, then use the global translation shortcut.",
            "请先选中需要翻译的文字，然后使用全局翻译快捷键。"
        )
    }
    static var selectTextToExplain: String {
        text(
            "Select some text, then use the global explanation shortcut.",
            "请先选中需要解释的文字，然后使用全局解释快捷键。"
        )
    }
    static var globalTranslationAccessibilityRequired: String {
        text(
            "Accessibility access is required to read selected text. Enable Pesty in System Settings.",
            "读取选中文字需要辅助功能权限，请在系统设置中为 Pesty 开启权限。"
        )
    }
    static var secureTextCannotBeTranslated: String {
        text(
            "Pesty does not read or translate text selected in secure fields.",
            "Pesty 不会读取或翻译安全输入框中选中的内容。"
        )
    }
    static var secureTextCannotBeExplained: String {
        text(
            "Pesty does not read or explain text selected in secure fields.",
            "Pesty 不会读取或解释安全输入框中选中的内容。"
        )
    }
    static var selectedTextLocationUnavailable: String {
        text(
            "This app exposes the selected text but not its screen position, so Pesty cannot anchor the translation window accurately.",
            "当前应用提供了选中文字，但没有提供它的屏幕位置，因此 Pesty 无法准确定位翻译窗口。"
        )
    }
    static var targetLanguageRequired: String {
        text("Choose a target language before translating.", "请先选择目标语言。")
    }
    static var translationServiceReturnedInvalidResponse: String {
        text("The translation service returned an invalid response.", "翻译服务返回了无效响应。")
    }
    static var appleLanguagePairUnavailable: String {
        text("Apple Translate does not support this language pair.", "Apple 翻译不支持此语言组合。")
    }
    static func translationAlreadyInTargetLanguage(_ language: String) -> String {
        text(
            "This content is already in \(language), so no translation is needed.",
            "当前内容已经是\(language)，无需翻译。"
        )
    }
    static var appleTranslationSourceLanguageUnidentified: String {
        text(
            "Apple Translate couldn’t identify the source language. Choose it manually and try again.",
            "Apple 翻译无法识别原文语言，请手动选择原文语言后重试。"
        )
    }
    static var appleTranslationTimedOut: String {
        text(
            "Apple Translate didn’t respond in time. Please try again.",
            "Apple 翻译响应超时，请重试。"
        )
    }
    static var appleTranslationRequiresMacOS15: String {
        text("Apple Translate requires macOS 15 or later.", "Apple 翻译需要 macOS 15 或更高版本。")
    }
    static var appleTranslationLanguagePacks: String {
        text("Apple Translate language packs", "Apple 翻译语言包")
    }
    static var appleTranslationBaselinePack: String {
        text("Required baseline", "默认必备")
    }
    static var appleTranslationSelectedPack: String {
        text("Current language selection", "当前语言选择")
    }
    static var appleTranslationLanguagePacksChecking: String {
        text("Checking download status…", "正在检查下载状态…")
    }
    static var appleTranslationLanguagePacksInstalled: String {
        text("Downloaded and ready", "已下载，可以使用")
    }
    static var appleTranslationLanguagePacksNotInstalled: String {
        text(
            "The required Apple Translate language packs are not downloaded. Download them in Translation Settings.",
            "所需的 Apple 翻译语言包尚未下载，请在“翻译设置”中下载。"
        )
    }
    static var appleTranslationCurrentlyUnavailable: String {
        text(
            "Apple Translate is currently unavailable. Open Translation Settings to review language packs or choose another service.",
            "Apple 翻译当前不可用，请打开“翻译设置”检查语言包或选择其他服务。"
        )
    }
    static var appleTranslationLanguagePacksDownloadRequired: String {
        text("Not downloaded", "尚未下载")
    }
    static var appleTranslationLanguagePacksDownloading: String {
        text(
            "Downloading… Keep this settings window open.",
            "正在下载…请保持设置窗口打开。"
        )
    }
    static var appleTranslationLanguagePacksDownload: String {
        text("Download", "下载")
    }
    static var appleTranslationLanguagePacksRetry: String {
        text("Try Again", "重试")
    }
    static func appleTranslationLanguagePacksDownloadFailed(
        _ reason: String
    ) -> String {
        text(
            "Could not download the language packs: \(reason)",
            "无法下载语言包：\(reason)"
        )
    }
    static var appleTranslationLanguagePacksAutomaticSourceNote: String {
        text(
            "Automatic source detection may require another source-language pack. Choose a specific source language above to download it in advance.",
            "自动识别可能还需要其他来源语言包；如需提前下载，请在上方选择明确的来源语言。"
        )
    }
    static var appleTranslationLanguagePacksDescription: String {
        text(
            "English and Simplified Chinese are always checked. Pesty also checks the language pair selected above.",
            "始终检查英语和简体中文基础包，并同时检查上方选择的语言组合。"
        )
    }
    static var checkingTranslationService: String {
        text("Checking translation service…", "正在检查翻译服务…")
    }
    static var doubaoTranslation: String { text("Doubao (Volcengine Ark)", "豆包（火山方舟）") }
    static var doubaoTranslationDisclosure: String {
        text("Doubao sends only text you explicitly translate or explain to Volcengine Ark. The API key is stored in macOS Keychain; the model ID stays only on this Mac.",
             "豆包只会向火山方舟发送你明确点击翻译或解释的文本。API Key 保存在 macOS 钥匙串中；模型 ID 仅保存在本机。")
    }
    static var doubaoTranslationAPIKey: String { text("Volcengine Ark API key", "火山方舟 API Key") }
    static var openDoubaoAPIKeyPage: String {
        text("Get an API key", "获取 API Key")
    }
    static var credentialStoredInKeychain: String {
        text("API key is securely saved in macOS Keychain and is not displayed.", "API Key 已安全保存在 macOS 钥匙串中，不会显示。")
    }
    static var replaceAPIKey: String { text("Replace API Key", "更换 API Key") }
    static var doubaoTranslationModelID: String { text("Ark model ID", "方舟模型 ID") }
    static var doubaoModelIDExample: String {
        text("Example: doubao-seed-evolving", "示例：doubao-seed-evolving")
    }
    static var doubaoTranslationConfigured: String { text("Doubao is ready", "豆包翻译已就绪") }
    static var doubaoTranslationNotConfigured: String { text("Add an API key and model ID", "请配置 API Key 和模型 ID") }
    static var doubaoTranslationNeedsConfiguration: String {
        text("Add your Volcengine Ark API key and model ID in Translation Settings.",
             "请在“翻译设置”中配置火山方舟 API Key 和模型 ID。")
    }
    static func doubaoTranslationRequestFailed(_ statusCode: Int) -> String {
        text("Doubao request failed (HTTP \(statusCode)).", "豆包请求失败（HTTP \(statusCode)）。")
    }
    static var doubaoModelSaved: String { text("Model ID saved.", "模型 ID 已保存。") }
    static var translationNeedsService: String {
        text("No translation service is ready. Use macOS 15 or later for Apple Translate, or configure Doubao.",
             "当前没有可用的翻译服务：Apple 翻译需要 macOS 15 或更高版本；也可以配置豆包。")
    }
    static var translationServiceUnavailable: String {
        text("Translation service unavailable", "翻译服务暂不可用")
    }
    static var translationPreferences: String { text("Translation preferences", "翻译偏好") }
    static var translationServiceDescription: String {
        text("Automatic prefers Apple Translate on macOS 15 or later, then your configured Doubao service.",
             "自动模式会优先使用 macOS 15 及以上的 Apple 翻译，其次使用你配置的豆包服务。")
    }
    static var translationShortcut: String { text("Translation shortcut", "翻译快捷键") }
    static var showTranslationBoard: String {
        text("Translate selected text", "翻译选中文字")
    }
    static var translationShortcutDescription: String {
        text(
            "Works globally in any app that exposes its text selection. Default: ⇧⌘T.",
            "可在支持读取文本选区的任意应用中全局使用。默认：⇧⌘T。"
        )
    }
    static var explanation: String { text("Explain", "解释") }
    static var usageTips: String { text("Quick tips", "使用小技巧") }
    static func usageTipTranslation(_ translationShortcut: String, _ explanationShortcut: String) -> String {
        text(
            "Select a text card, then press \(translationShortcut) to translate or \(explanationShortcut) to explain.",
            "选中文本卡片后，按 \(translationShortcut) 翻译、按 \(explanationShortcut) 解释。"
        )
    }
    static var usageTipPinboard: String {
        text(
            "Right-click a card to save it to a new or existing Pinboard—for fields you reuse, such as UID.",
            "右键卡片可新建或保存到 Pinboard，适合归类 UID 等常用字段。"
        )
    }
    static var usageTipQuickPaste: String {
        text("Double-click a card to paste it right away.", "双击卡片，即可快速粘贴。")
    }
    static var usageTipSearch: String {
        text("Start typing to search; press Return to paste the selected card.", "直接输入即可搜索；按回车粘贴选中卡片。")
    }
    static var explanationShortcut: String { text("Explanation shortcut", "解释快捷键") }
    static var showExplanationBoard: String { text("Explain selected content", "解释选中内容") }
    static var explanationShortcutDescription: String {
        text("Works globally with selected text in any app. Requires a configured AI model. Default: ⇧⌘D.",
             "可在任意应用中全局解释选中文字；需要配置大模型。默认：⇧⌘D。")
    }
    static var explaining: String { text("Explaining…", "正在解释…") }
    static var closeExplanation: String { text("Close explanation", "关闭解释") }
    static var moreExplanationOptions: String { text("More explanation options", "更多解释选项") }
    static var copyExplanation: String { text("Copy explanation", "复制解释") }
    static var retryExplanation: String { text("Retry", "重试") }
    static var noExplainableText: String { text("Select a text clip to explain.", "请选择一条文本剪贴内容进行解释。") }
    static var explanationNeedsConfiguration: String {
        text("Configure an AI model before using explanation. Add a Doubao model or an AI provider in Translation Settings.",
             "使用解释前请先配置大模型：可配置豆包模型，或在“翻译设置”中添加 AI 服务商。")
    }
    static var explanationFailed: String { text("Explanation failed. Please try again.", "解释失败，请重试。") }
    static var explanationInvalidResponse: String { text("The AI model returned an invalid response.", "大模型返回了无效响应。") }
    static func explanationRequestFailed(_ statusCode: Int) -> String {
        text("Explanation request failed (HTTP \(statusCode)).", "解释请求失败（HTTP \(statusCode)）。")
    }
    static var aiProviderInvalidEndpoint: String { text("The AI provider endpoint is invalid.", "AI 服务商接口地址无效。") }
    static var aiProviders: String { text("AI providers", "AI 服务商") }
    static var aiProvidersDescription: String {
        text("These profiles can power content explanation and future AI-native features. Their endpoint and model metadata stay local; API keys are stored separately in macOS Keychain.",
             "这些配置可用于内容解释和后续 AI 原生功能。接口地址和模型信息仅保存在本机；API Key 单独存储在 macOS 钥匙串中。")
    }
    static var noAIProviders: String { text("No AI provider configured", "尚未配置 AI 服务商") }
    static var addAIProvider: String { text("Add AI provider", "添加 AI 服务商") }
    static var openAICompatible: String { text("OpenAI compatible", "OpenAI 兼容接口") }
    static var aiProviderEditorDescription: String {
        text("Use an OpenAI-compatible endpoint. This version stores the profile securely for future AI features and does not send translation requests to it yet.",
             "请使用 OpenAI 兼容接口。本版本会安全保存该配置供后续 AI 功能使用，暂不会向它发送翻译请求。")
    }
    static var aiProviderName: String { text("Provider name", "服务商名称") }
    static var apiEndpoint: String { text("API endpoint", "API 接口地址") }
    static var modelName: String { text("Model name", "模型名称") }
    static var apiKey: String { text("API key", "API Key") }
    static var save: String { text("Save", "保存") }
    static var remove: String { text("Remove", "移除") }
    static var credentialSaved: String { text("Saved in macOS Keychain.", "已保存到 macOS 钥匙串。") }
    static var credentialRemoved: String { text("Credential removed.", "凭据已移除。") }
    static var credentialSaveFailed: String { text("Could not save the credential in macOS Keychain.", "无法将凭据保存到 macOS 钥匙串。") }
    static var credentialRemoveFailed: String { text("Could not remove the credential from macOS Keychain.", "无法从 macOS 钥匙串移除凭据。") }

    static var openPesty: String { text("Open Pesty", "打开 Pesty") }
    static var settings: String { text("Settings…", "设置…") }
    static var checkForUpdates: String { text("Check for Updates…", "检查更新…") }
    static var clearHistory: String { text("Clear History", "清除历史记录") }
    static var aboutPesty: String { text("About Pesty", "关于 Pesty") }
    static var quitPesty: String { text("Quit Pesty", "退出 Pesty") }
    static var iCloudUnavailable: String { text("iCloud Drive Unavailable", "iCloud Drive 不可用") }
    static var iCloudUnavailableMessage: String {
        text("Sign in to iCloud and enable iCloud Drive in System Settings to sync your clipboard across your Macs.",
             "请登录 iCloud 并在系统设置中启用 iCloud Drive，以在你的 Mac 之间同步剪贴板。")
    }
    static var aboutDescription: String {
        text("A free, open-source clipboard manager for macOS.\nInspired by Paste.",
             "一款免费、开源的 macOS 剪贴板管理工具。\n灵感来自 Paste。")
    }
    static func version(_ value: String) -> String {
        text("Version \(value)", "版本 \(value)")
    }
    static var reportIssue: String { text("Report an Issue", "反馈问题") }
    static var licenseDescription: String {
        text("MIT Licensed · Made with SwiftUI", "MIT 许可 · 使用 SwiftUI 制作")
    }
    static var updateAvailable: String { text("Update Available", "发现新版本") }
    static var updateProgressTitle: String {
        text("Pesty Update", "Pesty 更新")
    }
    static var updateProgressDescription: String {
        text("You can keep using Pesty while this finishes. Pesty will restart automatically when installation begins.",
             "更新完成前你仍可继续使用 Pesty。开始安装后，Pesty 会自动重启。")
    }
    static func updateAvailableMessage(_ version: String) -> String {
        text("Pesty \(version) is ready to install.",
             "Pesty \(version) 已可安装。")
    }
    static func updateToVersion(_ version: String) -> String {
        text("Update to Pesty \(version)", "更新到 Pesty \(version)")
    }
    static var checkingForUpdates: String {
        text("Checking for updates…", "正在检查更新…")
    }
    static var downloadingUpdate: String {
        text("Downloading update…", "正在下载更新…")
    }
    static func downloadingUpdate(_ version: String) -> String {
        text("Downloading Pesty \(version)…", "正在下载 Pesty \(version)…")
    }
    static func downloadingUpdate(_ version: String, percentage: Int) -> String {
        text("Downloading Pesty \(version)… \(percentage)%",
             "正在下载 Pesty \(version)… \(percentage)%")
    }
    static var verifyingUpdate: String {
        text("Verifying update…", "正在校验更新…")
    }
    static func verifyingUpdate(_ version: String) -> String {
        text("Verifying Pesty \(version)…", "正在校验 Pesty \(version)…")
    }
    static var preparingUpdate: String {
        text("Preparing update…", "正在准备更新…")
    }
    static func preparingUpdate(_ version: String) -> String {
        text("Preparing Pesty \(version)…", "正在准备 Pesty \(version)…")
    }
    static var installingUpdate: String {
        text("Installing and restarting…", "正在安装并重启…")
    }
    static func installingUpdate(_ version: String) -> String {
        text("Installing and restarting Pesty \(version)…",
             "正在安装并重启 Pesty \(version)…")
    }
    static var installAndRestart: String {
        text("Install and Restart", "安装并重启")
    }
    static var later: String { text("Later", "稍后") }
    static var upToDate: String { text("Pesty Is Up to Date", "Pesty 已是最新版本") }
    static func upToDateMessage(_ version: String) -> String {
        text("You are running Pesty \(version).",
             "你正在使用 Pesty \(version)。")
    }
    static var updateCheckFailed: String {
        text("Unable to Check for Updates", "无法检查更新")
    }
    static var updateInstallFailed: String {
        text("Unable to Install Update", "无法安装更新")
    }
    static var updateRestoredPreviousVersion: String {
        text("The update could not be completed. Pesty restored and reopened the previous version.",
             "更新未能完成。Pesty 已恢复并重新打开之前的版本。")
    }
    static var updateAlreadyInProgress: String {
        text("An update operation is already in progress.", "更新操作正在进行中。")
    }
    static var updateInvalidResponse: String {
        text("The update server returned an invalid response.", "更新服务器返回了无效响应。")
    }
    static var updateInvalidRelease: String {
        text("The latest release metadata is invalid.", "最新版本的元数据无效。")
    }
    static func updateMissingAsset(_ name: String) -> String {
        text("The release is missing \(name).", "该版本缺少 \(name)。")
    }
    static var updateMissingDigest: String {
        text("The release does not include a valid SHA-256 digest.",
             "该版本未提供有效的 SHA-256 摘要。")
    }
    static var updateUntrustedURL: String {
        text("The release download URL is not trusted.", "版本下载地址不受信任。")
    }
    static var updateDownloadFailed: String {
        text("The update could not be downloaded.", "无法下载更新。")
    }
    static var updateChecksumFailed: String {
        text("The downloaded update failed SHA-256 verification.",
             "下载的更新未通过 SHA-256 校验。")
    }
    static func updateDiskImageFailed(_ detail: String) -> String {
        text("The update disk image could not be opened: \(detail)",
             "无法打开更新磁盘映像：\(detail)")
    }
    static var updateMissingApp: String {
        text("The update does not contain Pesty.app.", "更新包中没有 Pesty.app。")
    }
    static var updateInvalidBundle: String {
        text("The update has an invalid application identity.", "更新的应用身份无效。")
    }
    static func updateVersionMismatch(_ version: String) -> String {
        text("The update contains unexpected version \(version).",
             "更新包中的版本 \(version) 与预期不符。")
    }
    static var updateInvalidArchitecture: String {
        text("The update is not a Universal Apple Silicon and Intel build.",
             "更新不是同时支持 Apple Silicon 和 Intel 的通用构建。")
    }
    static func updateSignatureFailed(_ detail: String) -> String {
        text("The update failed code-signature verification: \(detail)",
             "更新未通过代码签名校验：\(detail)")
    }
    static var updateAppNotWritable: String {
        text("Pesty cannot replace its current application. Reinstall it in Applications using your user account.",
             "Pesty 无法替换当前应用。请使用当前用户将它重新安装到“应用程序”。")
    }
    static var updateHelperFailed: String {
        text("The update installer could not be prepared.", "无法准备更新安装程序。")
    }
    static var updateMountPointMissing: String {
        text("The mounted update has no readable volume.", "挂载的更新没有可读取的卷。")
    }
    static var updateUnknownError: String {
        text("Unknown update error", "未知更新错误")
    }

    static var clipboard: String { text("Clipboard", "剪贴板") }
    static var rename: String { text("Rename…", "重命名…") }
    static var deletePinboard: String { text("Delete Pinboard", "删除 Pinboard") }
    static var newPinboard: String { text("New Pinboard", "新建 Pinboard") }
    static var enterNewName: String { text("Enter a new name", "输入新名称") }
    static var ok: String { text("OK", "好") }
    static var cancel: String { text("Cancel", "取消") }

    static var nothingCopied: String { text("Nothing copied yet", "还没有复制内容") }
    static func noMatches(_ query: String) -> String {
        text("No matches for “\(query)”", "没有匹配“\(query)”的内容")
    }
    static var iCloudSyncOn: String { text("iCloud sync on", "iCloud 同步已开启") }
    static var turnOnICloudSync: String { text("Turn on iCloud sync", "开启 iCloud 同步") }

    static var paste: String { text("Paste", "粘贴") }
    static var copy: String { text("Copy", "复制") }
    static var saveToPinboard: String { text("Save to Pinboard", "保存到 Pinboard") }
    static var saveToNewPinboard: String { text("Save to New Pinboard…", "保存到新 Pinboard…") }
    static var name: String { text("Name", "名称") }
    static var editTitle: String { text("Edit Title…", "编辑标题…") }
    static var cardTitle: String { text("Card title", "卡片标题") }
    static var delete: String { text("Delete", "删除") }
    static var file: String { text("File", "文件") }
    static func fileCount(_ count: Int) -> String {
        currentLanguage == .chinese ? "\(count) 个文件" : "\(count) file\(count == 1 ? "" : "s")"
    }
    static var image: String { text("Image", "图片") }
    static var color: String { text("Color", "颜色") }
    static var previewUnavailable: String {
        text(
            "A preview is not available for this clipboard item.",
            "无法预览这条剪贴板内容。"
        )
    }
    static var previewFileUnavailable: String {
        text(
            "The original file is no longer available.",
            "原始文件已不存在或暂时无法访问。"
        )
    }
    static var revealInFinder: String {
        text("Show in Finder", "在 Finder 中显示")
    }
    static func characterCount(_ count: Int) -> String {
        currentLanguage == .chinese ? "\(count) 个字符" : "\(count) characters"
    }
    static var pressKeys: String { text("Press keys…", "请按下快捷键…") }

    static func clipType(_ type: ClipType) -> String {
        switch type {
        case .text: return text("Text", "文本")
        case .richText: return text("Rich Text", "富文本")
        case .link: return text("Link", "链接")
        case .image: return text("Image", "图片")
        case .file: return text("File", "文件")
        case .color: return text("Color", "颜色")
        }
    }

    static var now: String { text("Now", "刚刚") }
    static var justNow: String { text("Just now", "刚刚") }
    static var localeIdentifier: String { currentLanguage == .chinese ? "zh_CN" : "en_US" }
}

extension Notification.Name {
    static let pestyLanguageDidChange = Notification.Name("PestyLanguageDidChange")
    static let pestyMenuBarIconVisibilityDidChange =
        Notification.Name("PestyMenuBarIconVisibilityDidChange")
    static let pestyUpdateStateDidChange =
        Notification.Name("PestyUpdateStateDidChange")
}
