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
                    L10n.accessibilityGuideExactPrompt(language: .english),
                    "Find Pesty.app, then turn on the switch on the right."
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
                    L10n.accessibilityGuideExactPrompt(language: .chinese),
                    "找到 Pesty.app，然后打开右侧开关完成授权。"
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
