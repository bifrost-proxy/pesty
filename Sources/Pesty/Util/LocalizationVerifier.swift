import Foundation

enum LocalizationVerifier {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        let key = "language"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        try verify(
            language: .english,
            key: key
        ) {
            [
                (L10n.settings, "Settings…"),
                (L10n.showMenuBarIcon, "Show menu bar icon"),
                (
                    L10n.syncAvailable,
                    "Keeps your history, pinboards, and history limit in sync across your Macs through iCloud Drive."
                ),
                (L10n.searchClipboard, "Search"),
                (L10n.checkForUpdates, "Check for Updates…"),
                (L10n.updateToVersion("1.2.3"), "Update to Pesty 1.2.3"),
                (L10n.checkingForUpdates, "Checking for updates…"),
                (
                    L10n.downloadingUpdate("1.2.3", percentage: 42),
                    "Downloading Pesty 1.2.3… 42%"
                ),
                (L10n.verifyingUpdate("1.2.3"), "Verifying Pesty 1.2.3…"),
                (L10n.preparingUpdate("1.2.3"), "Preparing Pesty 1.2.3…"),
                (
                    L10n.installingUpdate("1.2.3"),
                    "Installing and restarting Pesty 1.2.3…"
                ),
                (L10n.unlimited, "Unlimited"),
                (
                    L10n.historyLimitDelayDescription,
                    "If a lower limit would remove existing items, deletion waits 10 seconds so you can undo it."
                ),
                (L10n.storageUsed, "Current storage used"),
                (L10n.accessibilitySetupTitle, "Finish Setting Up Pesty"),
                (
                    L10n.accessibilityUpdateDescription,
                    "This update replaces the Pesty app, so macOS requires Accessibility access to be approved again. Your clipboard history and settings are unchanged."
                ),
                (
                    L10n.openAccessibilitySettings,
                    "Open Accessibility Settings"
                ),
                (
                    L10n.accessibilityGuideListPrompt(language: .english),
                    "Find Pesty.app in this list, then turn on the switch on the right."
                ),
                (
                    L10n.accessibilityReadyToRestart,
                    "Access granted. Restart Pesty to finish."
                ),
                (L10n.repairAccessibility, "Repair Access"),
                (L10n.accessibilityRepairing, "Removing the old authorization…"),
                (
                    L10n.accessibilityRepairFailed("exit 1"),
                    "Couldn’t reset the old authorization: exit 1"
                ),
                (L10n.clearHistoryConfirmationTitle, "Clear all clipboard history?"),
                (
                    L10n.clearHistoryConfirmationMessage,
                    "This permanently deletes all clipboard history and its stored images. This action cannot be undone. Pinboards will not be deleted."
                ),
                (L10n.items(2), "2 items"),
                (L10n.fileCount(1), "1 file"),
                (L10n.fileCount(2), "2 files"),
                (L10n.version("1.2.3"), "Version 1.2.3"),
                (L10n.translation, "Translation"),
                (L10n.translationAndExplanation, "Translate & Explain"),
                (L10n.sourceLanguage, "Source language"),
                (L10n.targetLanguage, "Target language"),
                (L10n.swapTranslationLanguages, "Swap languages"),
                (
                    L10n.swapTranslationLanguagesShortcut,
                    "Swap source and target languages (T)"
                ),
                (
                    L10n.translationShortcutDescription,
                    "Works globally in any app that exposes its text selection. Default: ⇧⌘T."
                ),
                (
                    L10n.selectTextToTranslate,
                    "Select some text, then use the global translation shortcut."
                ),
                (
                    L10n.selectTextToExplain,
                    "Select some text, then use the global explanation shortcut."
                ),
                (L10n.doubaoTranslation, "Doubao (Volcengine Ark)"),
                (
                    L10n.credentialStoredInKeychain,
                    "API key is securely saved in macOS Keychain and is not displayed."
                ),
                (L10n.replaceAPIKey, "Replace API Key"),
                (L10n.openDoubaoAPIKeyPage, "Get an API key"),
                (L10n.doubaoModelIDExample, "Example: doubao-seed-evolving"),
                (L10n.doubaoTranslationNeedsConfiguration, "Add your Volcengine Ark API key and model ID in Translation Settings."),
                (L10n.translationServiceUnavailable, "Translation service unavailable"),
                (
                    L10n.appleTranslationLanguagePacksDescription,
                    "English and Simplified Chinese are always checked. Pesty also checks the language pair selected above."
                ),
                (
                    L10n.appleTranslationLanguagePacksNotInstalled,
                    "The required Apple Translate language packs are not downloaded. Download them in Translation Settings."
                ),
                (
                    L10n.translationAlreadyInTargetLanguage("Chinese (Simplified)"),
                    "This content is already in Chinese (Simplified), so no translation is needed."
                ),
                (
                    L10n.appleTranslationSourceLanguageUnidentified,
                    "Apple Translate couldn’t identify the source language. Choose it manually and try again."
                ),
                (
                    L10n.appleTranslationTimedOut,
                    "Apple Translate didn’t respond in time. Please try again."
                ),
                (
                    L10n.checkingTranslationService,
                    "Checking translation service…"
                ),
                (L10n.explanation, "Explain"),
                (L10n.usageTips, "Quick tips"),
                (L10n.usageTipTranslation("⌘T", "⌘D"), "Select a text card, then press ⌘T to translate or ⌘D to explain."),
                (L10n.usageTipPinboard, "Right-click a card to save it to a new or existing Pinboard—for fields you reuse, such as UID."),
                (L10n.explanationShortcut, "Explanation shortcut"),
                (L10n.explanationShortcutDescription, "Works globally with selected text in any app. Requires a configured AI model. Default: ⇧⌘D."),
                (L10n.explanationNeedsConfiguration, "Configure an AI model before using explanation. Add a Doubao model or an AI provider in Translation Settings."),
            ]
        }
        guard ClipType.richText.label == "Rich Text" else {
            throw Failure(description: "English clip type label is incomplete")
        }

        try verify(
            language: .chinese,
            key: key
        ) {
            [
                (L10n.settings, "设置…"),
                (L10n.showMenuBarIcon, "显示菜单栏图标"),
                (
                    L10n.syncAvailable,
                    "通过 iCloud Drive 在你的 Mac 之间同步历史记录、Pinboard 和历史记录上限。"
                ),
                (L10n.searchClipboard, "搜索"),
                (L10n.checkForUpdates, "检查更新…"),
                (L10n.updateToVersion("1.2.3"), "更新到 Pesty 1.2.3"),
                (L10n.checkingForUpdates, "正在检查更新…"),
                (
                    L10n.downloadingUpdate("1.2.3", percentage: 42),
                    "正在下载 Pesty 1.2.3… 42%"
                ),
                (L10n.verifyingUpdate("1.2.3"), "正在校验 Pesty 1.2.3…"),
                (L10n.preparingUpdate("1.2.3"), "正在准备 Pesty 1.2.3…"),
                (
                    L10n.installingUpdate("1.2.3"),
                    "正在安装并重启 Pesty 1.2.3…"
                ),
                (L10n.unlimited, "无限"),
                (
                    L10n.historyLimitDelayDescription,
                    "如果降低上限会删除已有记录，Pesty 将等待 10 秒再清理，期间可以调高或切回无限。"
                ),
                (L10n.storageUsed, "当前占用空间"),
                (L10n.accessibilitySetupTitle, "完成 Pesty 设置"),
                (
                    L10n.accessibilityUpdateDescription,
                    "本次更新替换了 Pesty 应用，因此 macOS 要求重新授权辅助功能。你的剪贴板历史和设置不会受到影响。"
                ),
                (
                    L10n.openAccessibilitySettings,
                    "打开辅助功能设置"
                ),
                (
                    L10n.accessibilityGuideListPrompt(language: .chinese),
                    "在列表中找到 Pesty.app，然后打开右侧开关完成授权。"
                ),
                (
                    L10n.accessibilityReadyToRestart,
                    "授权成功。重启 Pesty 即可完成。"
                ),
                (L10n.repairAccessibility, "修复权限"),
                (L10n.accessibilityRepairing, "正在移除旧授权……"),
                (
                    L10n.accessibilityRepairFailed("exit 1"),
                    "无法重置旧授权：exit 1"
                ),
                (L10n.clearHistoryConfirmationTitle, "确定清除全部剪贴板历史记录吗？"),
                (
                    L10n.clearHistoryConfirmationMessage,
                    "这会永久删除全部剪贴板历史记录及其图片，且无法撤销。Pinboard 中的内容不会被删除。"
                ),
                (L10n.items(2), "2 项"),
                (L10n.fileCount(2), "2 个文件"),
                (L10n.version("1.2.3"), "版本 1.2.3"),
                (L10n.translation, "翻译"),
                (L10n.translationAndExplanation, "翻译&解释"),
                (L10n.sourceLanguage, "原文语言"),
                (L10n.targetLanguage, "目标语言"),
                (L10n.swapTranslationLanguages, "交换语言"),
                (
                    L10n.swapTranslationLanguagesShortcut,
                    "交换原文和目标语言（T）"
                ),
                (
                    L10n.translationShortcutDescription,
                    "可在支持读取文本选区的任意应用中全局使用。默认：⇧⌘T。"
                ),
                (
                    L10n.selectTextToTranslate,
                    "请先选中需要翻译的文字，然后使用全局翻译快捷键。"
                ),
                (
                    L10n.selectTextToExplain,
                    "请先选中需要解释的文字，然后使用全局解释快捷键。"
                ),
                (L10n.doubaoTranslation, "豆包（火山方舟）"),
                (
                    L10n.credentialStoredInKeychain,
                    "API Key 已安全保存在 macOS 钥匙串中，不会显示。"
                ),
                (L10n.replaceAPIKey, "更换 API Key"),
                (L10n.openDoubaoAPIKeyPage, "获取 API Key"),
                (L10n.doubaoModelIDExample, "示例：doubao-seed-evolving"),
                (L10n.doubaoTranslationNeedsConfiguration, "请在“翻译设置”中配置火山方舟 API Key 和模型 ID。"),
                (L10n.translationServiceUnavailable, "翻译服务暂不可用"),
                (
                    L10n.appleTranslationLanguagePacksDescription,
                    "始终检查英语和简体中文基础包，并同时检查上方选择的语言组合。"
                ),
                (
                    L10n.appleTranslationLanguagePacksNotInstalled,
                    "所需的 Apple 翻译语言包尚未下载，请在“翻译设置”中下载。"
                ),
                (
                    L10n.translationAlreadyInTargetLanguage("中文（简体）"),
                    "当前内容已经是中文（简体），无需翻译。"
                ),
                (
                    L10n.appleTranslationSourceLanguageUnidentified,
                    "Apple 翻译无法识别原文语言，请手动选择原文语言后重试。"
                ),
                (
                    L10n.appleTranslationTimedOut,
                    "Apple 翻译响应超时，请重试。"
                ),
                (
                    L10n.checkingTranslationService,
                    "正在检查翻译服务…"
                ),
                (L10n.explanation, "解释"),
                (L10n.usageTips, "使用小技巧"),
                (L10n.usageTipTranslation("⌘T", "⌘D"), "选中文本卡片后，按 ⌘T 翻译、按 ⌘D 解释。"),
                (L10n.usageTipPinboard, "右键卡片可新建或保存到 Pinboard，适合归类 UID 等常用字段。"),
                (L10n.explanationShortcut, "解释快捷键"),
                (L10n.explanationShortcutDescription, "可在任意应用中全局解释选中文字；需要配置大模型。默认：⇧⌘D。"),
                (L10n.explanationNeedsConfiguration, "使用解释前请先配置大模型：可配置豆包模型，或在“翻译设置”中添加 AI 服务商。"),
            ]
        }
        guard ClipType.richText.label == "富文本" else {
            throw Failure(description: "Simplified Chinese clip type label is incomplete")
        }
    }

    private static func verify(
        language: AppLanguage,
        key: String,
        expectations: () -> [(actual: String, expected: String)]
    ) throws {
        UserDefaults.standard.set(language.rawValue, forKey: key)
        for expectation in expectations() where expectation.actual != expectation.expected {
            throw Failure(
                description: "\(language.rawValue): expected \(expectation.expected), got \(expectation.actual)"
            )
        }
    }
}
