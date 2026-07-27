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
                (L10n.searchClipboard, "Search"),
                (L10n.checkForUpdates, "Check for Updates…"),
                (L10n.updateToVersion("1.2.3"), "Update to Pesty 1.2.3"),
                (L10n.unlimited, "Unlimited"),
                (
                    L10n.historyLimitDelayDescription,
                    "If a lower limit would remove existing items, deletion waits 10 seconds so you can undo it."
                ),
                (L10n.storageUsed, "Current storage used"),
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
                (L10n.searchClipboard, "搜索"),
                (L10n.checkForUpdates, "检查更新…"),
                (L10n.updateToVersion("1.2.3"), "更新到 Pesty 1.2.3"),
                (L10n.unlimited, "无限"),
                (
                    L10n.historyLimitDelayDescription,
                    "如果降低上限会删除已有记录，Pesty 将等待 10 秒再清理，期间可以调高或切回无限。"
                ),
                (L10n.storageUsed, "当前占用空间"),
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
